# Fast Split Pane Focus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 双击 Cmd 键在每个 split pane 右上角显示编号 badge（`#0`…`#z`），键入对应字符即可跳转焦点。

**Architecture:** 新增 `CmdDoubleTapDetector` 单例（对称 `ShiftDoubleTapDetector`）检测双击，发送 `.togglePaneSelector` 通知。`PaneSelectorViewModel`（ObservableObject 全局单例）接收通知、计算 pane 编号、注册 keyDown monitor 拦截输入。`TerminalSplitLeafContainer` 通过 `@EnvironmentObject` 读取状态并叠加 `PaneBadgeView`。

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit (NSEvent monitors), Carbon (kVK_Command keycodes)

**关键参考文件：**
- 设计文档：`docs/superpowers/specs/2026-03-23-fast-split-pane-focus-design.md`
- 参考实现：`macos/Sources/Features/App Launcher/ShiftDoubleTapDetector.swift`（模式完全对称）
- Notification 名定义模式：`macos/Sources/Features/App Launcher/AppLauncherView.swift:29`
- AppDelegate start 调用位置：`macos/Sources/App/macOS/AppDelegate.swift:871`

**PR Review 必查项（development-rules.md 要求）：**
- `syncFocusToSurfaceTree` 路径：本功能使用 `Ghostty.moveFocus(to:)`，不触碰该路径
- `localEventLeftMouseDown` 坐标：本功能不引入新的 hit test / mouse event

---

## 文件清单

**新增：**
- `macos/Sources/Features/Splits/CmdDoubleTapDetector.swift` — 双击 Cmd 检测器单例
- `macos/Sources/Features/Splits/PaneSelectorViewModel.swift` — 选择模式状态 + keyDown monitor
- `macos/Sources/Features/Splits/PaneBadgeView.swift` — 编号 badge SwiftUI 视图

**修改：**
- `macos/Sources/Features/Splits/TerminalSplitTreeView.swift:96-141` — `TerminalSplitLeafContainer` 加 `@EnvironmentObject` + badge overlay
- `macos/Sources/Features/Terminal/TerminalView.swift:85` — 注入 `PaneSelectorViewModel.shared`
- `macos/Sources/App/macOS/AppDelegate.swift:871` — 启动 `CmdDoubleTapDetector`

---

## Task 1: CmdDoubleTapDetector

**Files:**
- Create: `macos/Sources/Features/Splits/CmdDoubleTapDetector.swift`

- [ ] **Step 1: 新建文件，写入完整实现**

```swift
// macos/Sources/Features/Splits/CmdDoubleTapDetector.swift
import AppKit
import Carbon
import OSLog

/// 检测双击 Cmd 键（间隔 ≤ 350ms），触发时发送 togglePaneSelector 通知。
/// 监听 .flagsChanged 事件（Cmd 产生此事件，不产生 keyDown）。
/// 两次 Cmd 之间有任何其他键按下或修饰符变化则重置计时器。
final class CmdDoubleTapDetector {
    static let shared = CmdDoubleTapDetector()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "CmdDoubleTapDetector"
    )

    private let threshold: TimeInterval = 0.35
    private var lastCmdTime: Date?
    private var flagsMonitor: Any?
    private var keyDownMonitor: Any?

    private init() {}

    deinit { stop() }

    func start() {
        guard flagsMonitor == nil else { return }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.lastCmdTime = nil
            return event
        }

        Self.logger.info("CmdDoubleTapDetector started")
    }

    func stop() {
        if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
        if let m = keyDownMonitor { NSEvent.removeMonitor(m); keyDownMonitor = nil }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let isCmd = event.keyCode == UInt16(kVK_Command) || event.keyCode == UInt16(kVK_RightCommand)

        guard isCmd else {
            // 非 Cmd 修饰符变化（Shift/Option/Ctrl 等）→ 重置
            lastCmdTime = nil
            return
        }

        // 只处理按下瞬间（.command 存在），忽略松开（.command 不存在）
        guard event.modifierFlags.contains(.command) else { return }

        let now = Date()
        if let last = lastCmdTime, now.timeIntervalSince(last) <= threshold {
            lastCmdTime = nil
            Self.logger.debug("double-cmd detected, posting togglePaneSelector")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .togglePaneSelector, object: NSApp.keyWindow)
            }
        } else {
            lastCmdTime = now
        }
    }
}
```

- [ ] **Step 2: 构建确认无编译错误**

```bash
cd /Users/aaronlin/works/codes/oss/poltertty/.worktrees/feature-fast-split-pane
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | tail -5
```

期望输出：`** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Splits/CmdDoubleTapDetector.swift
git commit -m "feat(splits): add CmdDoubleTapDetector for double-tap Cmd detection"
```

---

## Task 2: PaneSelectorViewModel

**Files:**
- Create: `macos/Sources/Features/Splits/PaneSelectorViewModel.swift`

- [ ] **Step 1: 新建文件，写入完整实现**

```swift
// macos/Sources/Features/Splits/PaneSelectorViewModel.swift
import AppKit
import Combine
import OSLog

extension Notification.Name {
    static let togglePaneSelector = Notification.Name("poltertty.togglePaneSelector")
}

/// 管理 pane 选择模式的状态：激活/停用、编号分配、键盘事件拦截。
@MainActor
final class PaneSelectorViewModel: ObservableObject {
    static let shared = PaneSelectorViewModel()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "PaneSelectorViewModel"
    )

    @Published var isActive: Bool = false
    /// surfaceId → 0-indexed pane 序号（0-35）
    @Published var assignments: [UUID: Int] = [:]

    private var keyMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        // 监听双击 Cmd 通知
        NotificationCenter.default.publisher(for: .togglePaneSelector)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self else { return }
                if self.isActive {
                    self.deactivate()
                } else {
                    self.activate(for: notification.object as? NSWindow)
                }
            }
            .store(in: &cancellables)

        // 窗口失焦时自动取消
        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isActive else { return }
                self.deactivate()
            }
            .store(in: &cancellables)
    }

    // MARK: - 编号标签

    /// 将 0-indexed 序号转换为显示标签："0"…"9"，"a"…"z"，超出范围返回 "?"
    static func label(for index: Int) -> String {
        guard index >= 0 else { return "?" }
        if index <= 9 { return "\(index)" }
        guard index <= 35 else { return "?" }
        let char = Character(UnicodeScalar(Int(("a" as UnicodeScalar).value) + index - 10)!)
        return String(char)
    }

    // MARK: - 激活/停用

    private func activate(for window: NSWindow?) {
        // 从 keyWindow 取当前 tab 的 TerminalController
        // native tab 模式下每个 tab 是独立 NSWindow，keyWindow 就是当前 tab
        guard let controller = window?.windowController as? TerminalController else {
            Self.logger.warning("activate: no TerminalController for window")
            return
        }

        // 枚举可见 pane（zoom 模式下只有 1 个）
        let visibleNode = controller.surfaceTree.zoomed ?? controller.surfaceTree.root
        let leaves = visibleNode?.leaves() ?? []

        guard !leaves.isEmpty else { return }

        // 建立 surfaceId → 0-indexed 编号映射
        var newAssignments: [UUID: Int] = [:]
        for (index, surface) in leaves.enumerated() {
            newAssignments[surface.id] = index
        }

        assignments = newAssignments
        isActive = true

        // 注册 keyDown monitor（必须保存引用以便移除）
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }

        Self.logger.debug("activated with \(leaves.count) panes")
    }

    func deactivate() {
        isActive = false
        assignments = [:]
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        Self.logger.debug("deactivated")
    }

    // MARK: - 键盘事件处理

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        // Esc → 取消（有意消费，选择模式期间不透传给终端）
        if event.keyCode == 53 {
            deactivate()
            return nil
        }

        guard let char = event.charactersIgnoringModifiers?.lowercased().first else {
            return event
        }

        let index: Int?
        switch char {
        case "0"..."9":
            index = Int(String(char))
        case "a"..."z":
            index = Int(char.asciiValue! - Character("a").asciiValue!) + 10
        default:
            return event  // 其他键透传
        }

        guard let idx = index,
              let surfaceId = assignments.first(where: { $0.value == idx })?.key,
              let surface = findSurface(id: surfaceId) else {
            return event
        }

        Ghostty.moveFocus(to: surface)
        deactivate()
        return nil  // 消费事件
    }

    private func findSurface(id: UUID) -> Ghostty.SurfaceView? {
        for window in NSApp.windows {
            guard let controller = window.windowController as? TerminalController else { continue }
            if let surface = Array(controller.surfaceTree).first(where: { $0.id == id }) {
                return surface
            }
        }
        return nil
    }
}
```

- [ ] **Step 2: 构建确认无编译错误**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | tail -5
```

期望：`** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Splits/PaneSelectorViewModel.swift
git commit -m "feat(splits): add PaneSelectorViewModel for pane selection state"
```

---

## Task 3: PaneBadgeView

**Files:**
- Create: `macos/Sources/Features/Splits/PaneBadgeView.swift`

- [ ] **Step 1: 新建文件**

```swift
// macos/Sources/Features/Splits/PaneBadgeView.swift
import SwiftUI

/// 显示在 split pane 右上角的编号 badge，如 "#0"、"#a"。
struct PaneBadgeView: View {
    /// 单字符标签："0"…"9" 或 "a"…"z"
    let label: String

    var body: some View {
        Text("#\(label)")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
    }
}
```

- [ ] **Step 2: 构建确认**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | tail -5
```

期望：`** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Splits/PaneBadgeView.swift
git commit -m "feat(splits): add PaneBadgeView for pane number badge overlay"
```

---

## Task 4: TerminalSplitLeafContainer — badge overlay

**Files:**
- Modify: `macos/Sources/Features/Splits/TerminalSplitTreeView.swift:96-141`

- [ ] **Step 1: 在 `TerminalSplitLeafContainer` 顶部添加 `@EnvironmentObject`**

在 `macos/Sources/Features/Splits/TerminalSplitTreeView.swift` 第 103 行（`@FocusedValue` 那行）之后插入：

```swift
    @EnvironmentObject private var paneSelectorVM: PaneSelectorViewModel
```

完整上下文（修改后）：

```swift
private struct TerminalSplitLeafContainer: View {
    let surfaceView: Ghostty.SurfaceView
    let isSplit: Bool
    let action: (TerminalSplitOperation) -> Void

    @StateObject private var statusMonitor = GitStatusMonitor(pwd: "")
    @Environment(\.showStatusBar) private var showStatusBar
    @FocusedValue(\.ghosttySurfaceView) private var focusedSurface
    @EnvironmentObject private var paneSelectorVM: PaneSelectorViewModel   // ← 新增

    // Dashboard: 脉冲高亮
    @State private var highlightOpacity: CGFloat = 0
```

- [ ] **Step 2: 在 `body` 的 overlay 链末尾追加 badge overlay**

找到 `onReceive(NotificationCenter.default.publisher(for: PaneLocator.highlightSurface))` 闭包的结束括号之后（第 140 行附近），在 `}` 之前追加：

```swift
            .overlay(alignment: .topTrailing) {
                if paneSelectorVM.isActive,
                   let idx = paneSelectorVM.assignments[surfaceView.id] {
                    PaneBadgeView(label: PaneSelectorViewModel.label(for: idx))
                        .padding(6)
                        .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                }
            }
```

完整 `body` 结尾（修改后）：

```swift
        .onReceive(NotificationCenter.default.publisher(for: PaneLocator.highlightSurface)) { notif in
            guard let targetId = notif.userInfo?["surfaceId"] as? UUID,
                  targetId == surfaceView.id else { return }
            triggerPulse()
        }
        .overlay(alignment: .topTrailing) {
            if paneSelectorVM.isActive,
               let idx = paneSelectorVM.assignments[surfaceView.id] {
                PaneBadgeView(label: PaneSelectorViewModel.label(for: idx))
                    .padding(6)
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
    }
```

- [ ] **Step 3: 构建确认**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | tail -5
```

期望：`** BUILD SUCCEEDED **`

如果出现 `EnvironmentObject<PaneSelectorViewModel> not found`，说明 Step 5 的注入还未完成，属正常——继续往下做注入后再验证。

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Splits/TerminalSplitTreeView.swift
git commit -m "feat(splits): add pane selector badge overlay to TerminalSplitLeafContainer"
```

---

## Task 5: 注入 EnvironmentObject + 启动检测器

**Files:**
- Modify: `macos/Sources/Features/Terminal/TerminalView.swift:85`
- Modify: `macos/Sources/App/macOS/AppDelegate.swift:871`

- [ ] **Step 1: 在 `TerminalView.swift` 注入 `PaneSelectorViewModel`**

在第 85 行 `.environmentObject(ghostty)` 之后插入：

```swift
                        .environmentObject(ghostty)
                        .environmentObject(PaneSelectorViewModel.shared)   // ← 新增
```

- [ ] **Step 2: 在 `AppDelegate.swift` 启动检测器**

在第 871 行 `ShiftDoubleTapDetector.shared.start()` 之后插入：

```swift
        ShiftDoubleTapDetector.shared.start()
        CmdDoubleTapDetector.shared.start()   // ← 新增：启动双击 Cmd 检测
```

- [ ] **Step 3: 全量构建确认**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | tail -5
```

期望：`** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Terminal/TerminalView.swift \
        macos/Sources/App/macOS/AppDelegate.swift
git commit -m "feat(splits): wire PaneSelectorViewModel and start CmdDoubleTapDetector"
```

---

## Task 6: 手动验证

- [ ] **Step 1: 运行 App**

在 Xcode 中 Run，或：

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug
open build/Debug/Ghostty.app
```

- [ ] **Step 2: 基本流程验证**

1. 创建 2-3 个 split pane（`Cmd+D` 水平分屏，`Cmd+Shift+D` 垂直分屏）
2. 快速双击 Cmd 键（间隔 < 350ms）
3. ✅ 每个 pane 右上角出现 `#0`、`#1`、`#2` badge
4. 按 `1` → 焦点跳到第二个 pane，badge 全部消失
5. 再次双击 Cmd → badge 重新出现
6. 按 Esc → badge 消失

- [ ] **Step 3: 取消流程验证**

1. 双击 Cmd，badge 出现
2. 再次双击 Cmd → badge 消失（切换逻辑）

- [ ] **Step 4: 窗口失焦验证**

1. 双击 Cmd，badge 出现
2. 点击另一个应用（失焦）→ badge 自动消失
3. 回到 App → 不残留 badge

- [ ] **Step 5: 字母键验证（≥11 个 pane）**

1. 创建 11 个分屏（可通过 `Cmd+D` 连续分屏）
2. 双击 Cmd → 第 11 个 pane 显示 `#a`
3. 按 `a` → 焦点跳到该 pane

- [ ] **Step 6: zoom 模式验证**

1. 用 `Cmd+Shift+Return`（或菜单）zoom 某个 pane
2. 双击 Cmd → 只显示 `#0` 一个 badge
3. 按 `0` → 焦点保持在当前 pane，badge 消失

- [ ] **Step 7: PR Review 必查项确认**

1. 确认光标仍然正常（无空心方块）：打开多个分屏，来回切换焦点，光标保持实心
2. 确认上下分屏点击焦点正常：垂直分屏时鼠标点击底部 pane 能正确聚焦

- [ ] **Step 8: 最终 Commit（如有遗漏）**

```bash
git status  # 确认无未提交文件
```
