# App Launcher 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现双击 Shift 唤起悬浮命令 Launcher，支持编辑距离搜索 macOS 菜单项 + Poltertty 本地功能并执行。

**Architecture:** 新建 `App Launcher` feature 目录，包含四个独立模块：EditDistanceFilter（纯算法）、AppCommandRegistry（命令收集）、ShiftDoubleTapDetector（键盘检测）、AppLauncherView（SwiftUI UI）。`PolterttyRootView` 通过 NotificationCenter 接收触发信号并显示 overlay，`AppDelegate` 负责启动检测器。

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit (NSEvent, NSApp.mainMenu), Swift Testing framework, xcodebuild

**Dev 规则提醒：** 开发必须在独立 worktree 进行。在开始前执行：
```bash
git worktree add .worktrees/app-launcher -b feat/app-launcher
cd .worktrees/app-launcher
```

---

## 文件映射

| 操作 | 路径 | 职责 |
|------|------|------|
| 新建 | `macos/Sources/Features/App Launcher/EditDistanceFilter.swift` | Levenshtein 距离计算 + 排序 |
| 新建 | `macos/Sources/Features/App Launcher/AppCommandRegistry.swift` | 命令收集：菜单扫描 + Poltertty actions |
| 新建 | `macos/Sources/Features/App Launcher/ShiftDoubleTapDetector.swift` | 双击 Shift 检测 |
| 新建 | `macos/Sources/Features/App Launcher/AppLauncherView.swift` | 主 SwiftUI UI |
| 新建 | `macos/Tests/AppLauncher/EditDistanceFilterTests.swift` | EditDistanceFilter 单元测试 |
| 修改 | `macos/Sources/Features/Command Palette/CommandPalette.swift` | CommandRow/CommandTable/ShortcutSymbolsView 改为 internal |
| 修改 | `macos/Sources/Features/Workspace/PolterttyRootView.swift` | 添加 launcher overlay + .toggleAppLauncher 通知 |
| 修改 | `macos/Sources/App/macOS/AppDelegate.swift` | 启动 ShiftDoubleTapDetector |

---

## Task 1: EditDistanceFilter（TDD）

**Files:**
- Create: `macos/Sources/Features/App Launcher/EditDistanceFilter.swift`
- Create: `macos/Tests/AppLauncher/EditDistanceFilterTests.swift`

- [ ] **Step 1: 新建测试文件**

```swift
// macos/Tests/AppLauncher/EditDistanceFilterTests.swift
import Testing
import SwiftUI
@testable import Ghostty

struct EditDistanceFilterTests {

    // CommandOption 工厂方法
    private func option(_ title: String) -> CommandOption {
        CommandOption(title: title, action: {})
    }

    // --- levenshteinDistance ---

    @Test func testIdenticalStrings() {
        #expect(EditDistanceFilter.levenshteinDistance("abc", "abc") == 0)
    }

    @Test func testEmptyQuery() {
        #expect(EditDistanceFilter.levenshteinDistance("", "abc") == 3)
    }

    @Test func testSingleInsertion() {
        #expect(EditDistanceFilter.levenshteinDistance("ab", "abc") == 1)
    }

    @Test func testSingleDeletion() {
        #expect(EditDistanceFilter.levenshteinDistance("abc", "ab") == 1)
    }

    @Test func testSingleSubstitution() {
        #expect(EditDistanceFilter.levenshteinDistance("abc", "axc") == 1)
    }

    // --- rank ---

    @Test func testEmptyQueryReturnsEmpty() {
        let opts = [option("New Tab"), option("New Window")]
        #expect(EditDistanceFilter.rank("", in: opts).isEmpty)
    }

    @Test func testContainsMatchRankedHigher() {
        let opts = [option("New Window"), option("New Tab")]
        let result = EditDistanceFilter.rank("tab", in: opts)
        #expect(result.first?.title == "New Tab")
    }

    @Test func testResultsLimitedToEight() {
        let opts = (0..<12).map { option("tab \($0)") }
        let result = EditDistanceFilter.rank("tab", in: opts)
        #expect(result.count <= 8)
    }

    @Test func testTooDistantResultsFiltered() {
        let opts = [option("zzzzzzzzz")]
        let result = EditDistanceFilter.rank("a", in: opts)
        #expect(result.isEmpty)
    }

    @Test func testCaseInsensitiveMatching() {
        let opts = [option("New Tab")]
        let result = EditDistanceFilter.rank("TAB", in: opts)
        #expect(!result.isEmpty)
    }
}
```

- [ ] **Step 2: 运行测试验证失败**

```bash
xcodebuild test \
  -project macos/Ghostty.xcodeproj \
  -scheme Ghostty \
  -destination "platform=macOS" \
  -only-testing:GhosttyTests/EditDistanceFilterTests \
  2>&1 | tail -20
```

预期：编译错误，`EditDistanceFilter` 类型不存在。

- [ ] **Step 3: 新建 EditDistanceFilter.swift**

```swift
// macos/Sources/Features/App Launcher/EditDistanceFilter.swift
import SwiftUI

enum EditDistanceFilter {
    /// Levenshtein 距离（标准 DP 矩阵）
    static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                if a[i-1] == b[j-1] {
                    curr[j] = prev[j-1]
                } else {
                    curr[j] = 1 + min(prev[j], curr[j-1], prev[j-1])
                }
            }
            prev = curr
        }
        return prev[n]
    }

    /// 对 options 按相关性排序。query 为空时返回空数组。
    /// contains 匹配的 option 距离减 3（最低 0）。
    /// 过滤有效距离超过 max(query.count, 3) 的结果。
    /// 返回前 8 条。
    static func rank(_ query: String, in options: [CommandOption]) -> [CommandOption] {
        guard !query.isEmpty else { return [] }

        let q = query.lowercased()
        let threshold = max(q.count, 3)

        return options
            .compactMap { option -> (CommandOption, Int)? in
                let title = option.title.lowercased()
                var dist = levenshteinDistance(q, title)
                if title.contains(q) {
                    dist = max(0, dist - 3)
                }
                guard dist <= threshold else { return nil }
                return (option, dist)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(8)
            .map { $0.0 }
    }
}
```

- [ ] **Step 4: 运行测试验证通过**

```bash
xcodebuild test \
  -project macos/Ghostty.xcodeproj \
  -scheme Ghostty \
  -destination "platform=macOS" \
  -only-testing:GhosttyTests/EditDistanceFilterTests \
  2>&1 | tail -20
```

预期：所有测试 PASS。

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/App\ Launcher/EditDistanceFilter.swift \
        macos/Tests/AppLauncher/EditDistanceFilterTests.swift
git commit -m "feat(app-launcher): add EditDistanceFilter with Levenshtein ranking"
```

---

## Task 2: 开放 CommandPalette 内部组件

**Files:**
- Modify: `macos/Sources/Features/Command Palette/CommandPalette.swift`

目的：将 `CommandRow`、`CommandTable`、`ShortcutSymbolsView` 从 `private` 改为 `internal`，供 `AppLauncherView` 复用。`CommandPaletteQuery` **不改动**（`FocusState` 跨 view 污染风险）。

- [ ] **Step 1: 去掉三个组件的 `private` 修饰符**

在 `CommandPalette.swift` 中找到以下三处，删除 `private` 关键字（保持其他代码不变）：

```swift
// 第 287 行附近：
private struct CommandTable: View {
// 改为：
struct CommandTable: View {

// 第 335 行附近：
private struct CommandRow: View {
// 改为：
struct CommandRow: View {

// 第 409 行附近：
private struct ShortcutSymbolsView: View {
// 改为：
struct ShortcutSymbolsView: View {
```

- [ ] **Step 2: 验证编译通过**

```bash
make check 2>&1 | grep "error:" | head -20
```

预期：无 error 输出。

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Command\ Palette/CommandPalette.swift
git commit -m "refactor(command-palette): expose CommandRow/CommandTable/ShortcutSymbolsView as internal"
```

---

## Task 3: AppCommandRegistry

**Files:**
- Create: `macos/Sources/Features/App Launcher/AppCommandRegistry.swift`

- [ ] **Step 1: 新建 AppCommandRegistry.swift**

```swift
// macos/Sources/Features/App Launcher/AppCommandRegistry.swift
import AppKit
import SwiftUI

/// 收集所有可用命令，供 AppLauncherView 使用。
/// 每次调用 refresh() 时重新扫描菜单（须在 @MainActor 执行）。
@MainActor
final class AppCommandRegistry: ObservableObject {
    static let shared = AppCommandRegistry()

    @Published private(set) var commands: [CommandOption] = []

    private init() {}

    /// 重新扫描所有命令来源。在 AppLauncherView.onAppear 中调用。
    func refresh() {
        var result: [CommandOption] = []
        result += scanMenuItems()
        result += polterttyActions()
        commands = result
    }

    // MARK: - macOS 菜单项扫描

    private func scanMenuItems() -> [CommandOption] {
        guard let mainMenu = NSApp.mainMenu else { return [] }
        return collectItems(from: mainMenu)
    }

    private func collectItems(from menu: NSMenu) -> [CommandOption] {
        var result: [CommandOption] = []
        for item in menu.items {
            guard !item.isSeparatorItem else { continue }
            if let submenu = item.submenu {
                result += collectItems(from: submenu)
            } else if let action = item.action, item.isEnabled {
                let symbols = keyEquivalentSymbols(for: item)
                result.append(CommandOption(
                    title: item.title,
                    symbols: symbols.isEmpty ? nil : symbols,
                    leadingIcon: "menubar.rectangle",
                    action: {
                        NSApp.sendAction(action, to: item.target, from: item)
                    }
                ))
            }
        }
        return result
    }

    /// 将 NSMenuItem 的 keyEquivalent + modifiers 转换为符号字符串数组
    private func keyEquivalentSymbols(for item: NSMenuItem) -> [String] {
        guard !item.keyEquivalent.isEmpty else { return [] }
        var symbols: [String] = []
        let mods = item.keyEquivalentModifierMask
        if mods.contains(.command) { symbols.append("⌘") }
        if mods.contains(.shift) { symbols.append("⇧") }
        if mods.contains(.option) { symbols.append("⌥") }
        if mods.contains(.control) { symbols.append("⌃") }
        symbols.append(item.keyEquivalent.uppercased())
        return symbols
    }

    // MARK: - Poltertty 本地 actions

    private func polterttyActions() -> [CommandOption] {
        [
            CommandOption(
                title: "切换侧边栏",
                subtitle: "Workspace Sidebar",
                leadingIcon: "sidebar.left",
                action: {
                    NotificationCenter.default.post(name: .toggleWorkspaceSidebar, object: nil)
                }
            ),
            CommandOption(
                title: "切换文件浏览器",
                subtitle: "File Browser",
                leadingIcon: "folder",
                action: {
                    NotificationCenter.default.post(name: .toggleFileBrowser, object: nil)
                }
            ),
            CommandOption(
                title: "切换 Workspace",
                subtitle: "Quick Switcher",
                leadingIcon: "square.stack",
                action: {
                    NotificationCenter.default.post(name: .toggleWorkspaceQuickSwitcher, object: nil)
                }
            ),
            CommandOption(
                title: "打开 Agent Monitor",
                subtitle: "Agent Monitor",
                leadingIcon: "cpu",
                action: {
                    NotificationCenter.default.post(name: .toggleAgentMonitor, object: nil)
                }
            ),
            CommandOption(
                title: "tmux Session 选择",
                subtitle: "Tmux Session Picker",
                leadingIcon: "terminal",
                action: {
                    NotificationCenter.default.post(name: .showTmuxSessionPicker, object: nil)
                }
            ),
        ]
    }
}
```

- [ ] **Step 2: 验证编译通过**

```bash
make check 2>&1 | grep "error:" | head -20
```

预期：无 error 输出。

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/App\ Launcher/AppCommandRegistry.swift
git commit -m "feat(app-launcher): add AppCommandRegistry with menu scan and Poltertty actions"
```

---

## Task 4: AppLauncherView

**Files:**
- Create: `macos/Sources/Features/App Launcher/AppLauncherView.swift`

- [ ] **Step 1: 新建 AppLauncherView.swift**

```swift
// macos/Sources/Features/App Launcher/AppLauncherView.swift
import SwiftUI

struct AppLauncherView: View {
    @Binding var isPresented: Bool
    var backgroundColor: Color = Color(nsColor: .windowBackgroundColor)

    @StateObject private var registry = AppCommandRegistry.shared
    @State private var query = ""
    @State private var selectedIndex: UInt?
    @State private var hoveredOptionID: UUID?
    @FocusState private var isTextFieldFocused: Bool

    var filteredOptions: [CommandOption] {
        EditDistanceFilter.rank(query, in: registry.commands)
    }

    var selectedOption: CommandOption? {
        guard let selectedIndex else { return nil }
        let opts = filteredOptions
        guard !opts.isEmpty else { return nil }
        return selectedIndex < opts.count ? opts[Int(selectedIndex)] : opts.last
    }

    var body: some View {
        let scheme: ColorScheme = OSColor(backgroundColor).isLightColor ? .light : .dark

        // 全屏遮罩
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Launcher 面板（居中偏上 1/4 屏）
            VStack {
                Spacer().frame(maxHeight: .infinity).frame(height: 0)
                    .frame(maxHeight: UIScreen.main == nil ? 200 : nil)

                launcherPanel(scheme: scheme)
                    .frame(maxWidth: 500)
                    .padding(.top, 80)

                Spacer()
            }
        }
        .environment(\.colorScheme, scheme)
        .task {
            isTextFieldFocused = true
        }
        .onChange(of: isPresented) { newValue in
            isTextFieldFocused = newValue
            if !newValue { query = "" }
        }
    }

    @ViewBuilder
    private func launcherPanel(scheme: ColorScheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 输入框
            inputField

            // 结果列表
            if !filteredOptions.isEmpty {
                Divider()
                CommandTable(
                    options: filteredOptions,
                    selectedIndex: $selectedIndex,
                    hoveredOptionID: $hoveredOptionID
                ) { option in
                    dismiss()
                    option.action()
                }
            }
        }
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(backgroundColor).blendMode(.color)
            }
            .compositingGroup()
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .tertiaryLabelColor).opacity(0.75))
        )
        .shadow(radius: 32, x: 0, y: 12)
        .padding(.horizontal)
        .onAppear {
            Task { @MainActor in
                registry.refresh()
            }
        }
        .onChange(of: query) { newValue in
            if !newValue.isEmpty {
                if selectedIndex == nil { selectedIndex = 0 }
            } else {
                if selectedIndex == 0 { selectedIndex = nil }
            }
        }
    }

    private var inputField: some View {
        ZStack {
            // 键盘导航按钮（隐藏）
            Group {
                Button { moveSelection(-1) } label: { Color.clear }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.upArrow, modifiers: [])
                Button { moveSelection(1) } label: { Color.clear }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.downArrow, modifiers: [])
                Button { moveSelection(-1) } label: { Color.clear }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.init("p"), modifiers: [.control])
                Button { moveSelection(1) } label: { Color.clear }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.init("n"), modifiers: [.control])
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)

            TextField("输入想找的功能…", text: $query)
                .padding()
                .font(.system(size: 20, weight: .light))
                .frame(height: 48)
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .onChange(of: isTextFieldFocused) { focused in
                    if !focused { dismiss() }
                }
                .onExitCommand { dismiss() }
                .onMoveCommand { dir in
                    switch dir {
                    case .up: moveSelection(-1)
                    case .down: moveSelection(1)
                    default: break
                    }
                }
                .onSubmit {
                    dismiss()
                    selectedOption?.action()
                }
        }
    }

    private func moveSelection(_ delta: Int) {
        let count = filteredOptions.count
        guard count > 0 else { return }
        let current = Int(selectedIndex ?? (delta > 0 ? UInt.max : 0))
        let next = (current + delta + count) % count
        selectedIndex = UInt(next)
    }

    private func dismiss() {
        isPresented = false
        query = ""
    }
}
```

- [ ] **Step 2: 验证编译通过**

```bash
make check 2>&1 | grep "error:" | head -20
```

预期：无 error 输出。

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/App\ Launcher/AppLauncherView.swift
git commit -m "feat(app-launcher): add AppLauncherView with edit distance search"
```

---

## Task 5: ShiftDoubleTapDetector

**Files:**
- Create: `macos/Sources/Features/App Launcher/ShiftDoubleTapDetector.swift`

- [ ] **Step 1: 新建 ShiftDoubleTapDetector.swift**

```swift
// macos/Sources/Features/App Launcher/ShiftDoubleTapDetector.swift
import AppKit
import Carbon
import OSLog

/// 检测双击 Shift 键（间隔 ≤ 350ms），触发时发送 toggleAppLauncher 通知。
/// 监听 .flagsChanged 事件（Shift 产生此事件，不产生 keyDown）。
/// 两次 Shift 之间有任何其他键按下或修饰符变化则重置计时器。
final class ShiftDoubleTapDetector {
    static let shared = ShiftDoubleTapDetector()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "ShiftDoubleTapDetector"
    )

    private let threshold: TimeInterval = 0.35
    private var lastShiftTime: Date?
    private var flagsMonitor: Any?
    private var keyDownMonitor: Any?

    private init() {}

    deinit { stop() }

    func start() {
        guard flagsMonitor == nil else { return }

        // 监听修饰键变化（Shift 按下/松开）
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        // 监听普通键按下，用于重置计时器
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.lastShiftTime = nil
            return event
        }

        Self.logger.info("ShiftDoubleTapDetector started")
    }

    func stop() {
        if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
        if let m = keyDownMonitor { NSEvent.removeMonitor(m); keyDownMonitor = nil }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let isShift = event.keyCode == UInt16(kVK_Shift) || event.keyCode == UInt16(kVK_RightShift)

        guard isShift else {
            // 非 Shift 修饰符变化（Cmd/Option/Ctrl 等）→ 重置
            lastShiftTime = nil
            return
        }

        // 只处理按下瞬间（.shift 存在），忽略松开（.shift 不存在）
        guard event.modifierFlags.contains(.shift) else { return }

        let now = Date()
        if let last = lastShiftTime, now.timeIntervalSince(last) <= threshold {
            // 双击成立
            lastShiftTime = nil
            Self.logger.debug("double-shift detected, posting toggleAppLauncher")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .toggleAppLauncher, object: nil)
            }
        } else {
            lastShiftTime = now
        }
    }
}
```

- [ ] **Step 2: 验证编译通过**

```bash
make check 2>&1 | grep "error:" | head -20
```

预期：无 error 输出。注意：`kVK_Shift`、`kVK_RightShift` 来自 Carbon 框架，确保 `import Carbon` 存在。

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/App\ Launcher/ShiftDoubleTapDetector.swift
git commit -m "feat(app-launcher): add ShiftDoubleTapDetector with flagsChanged event handling"
```

---

## Task 6: 集成到 PolterttyRootView + AppDelegate

**Files:**
- Modify: `macos/Sources/Features/Workspace/PolterttyRootView.swift`
- Modify: `macos/Sources/App/macOS/AppDelegate.swift`

### Step 1: 添加 `.toggleAppLauncher` 通知名

在 `PolterttyRootView.swift` 顶部的 `Notification.Name` 扩展中添加：

- [ ] **在 `PolterttyRootView.swift` 的通知扩展中添加新通知名**

找到文件顶部的 `extension Notification.Name {` 块（约第 4-17 行），在末尾的 `}` 之前添加：

```swift
static let toggleAppLauncher = Notification.Name("poltertty.toggleAppLauncher")
```

### Step 2: 在 PolterttyRootView 添加 launcher 状态和 overlay

- [ ] **添加 @State private var launcherVisible = false**

在 `PolterttyRootView` 的 `@State private var showTmuxPicker` 附近（约第 43 行）添加：

```swift
@State private var launcherVisible = false
```

- [ ] **在 ZStack 的 `.terminal` case 最外层 overlay 区域之后添加 launcher overlay**

在 `body` 的 ZStack 内，找到 `// Quick switcher overlay (always available in terminal mode)` 块（约第 250 行），在该块之后（快速切换器的 `}` 后面）添加：

```swift
// App Launcher overlay
if launcherVisible {
    AppLauncherView(
        isPresented: $launcherVisible,
        backgroundColor: Color(nsColor: .windowBackgroundColor)
    )
    .ignoresSafeArea()
}
```

- [ ] **添加 .toggleAppLauncher 通知监听**

在 `body` 末尾的 `.onChange(of: manager.formalWorkspaces.count)` 之后（约第 316 行）添加：

```swift
.onReceive(NotificationCenter.default.publisher(for: .toggleAppLauncher)) { _ in
    guard NSApp.keyWindow != nil else { return }
    launcherVisible.toggle()
}
```

- [ ] **验证编译通过**

```bash
make check 2>&1 | grep "error:" | head -20
```

### Step 3: 在 AppDelegate 启动检测器

- [ ] **在 applicationDidFinishLaunching 末尾启动 ShiftDoubleTapDetector**

在 `AppDelegate.swift` 中找到 `applicationDidFinishLaunching` 方法，在 `updateAppIcon(from: config)` 调用附近（约第 870 行）添加：

```swift
// 启动双击 Shift 检测（App Launcher 触发器）
ShiftDoubleTapDetector.shared.start()
```

- [ ] **验证编译通过**

```bash
make check 2>&1 | grep "error:" | head -20
```

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Workspace/PolterttyRootView.swift \
        macos/Sources/App/macOS/AppDelegate.swift
git commit -m "feat(app-launcher): integrate launcher overlay and shift detector into app"
```

---

## Task 7: 手动验证

- [ ] **构建 Dev 版本**

```bash
make dev
```

- [ ] **运行并测试**

```bash
make run-dev
```

验证以下行为：
1. 双击 Shift → launcher 弹出，居中显示，有半透明遮罩
2. 输入 "tab" → 显示包含 "New Tab" 等结果，按编辑距离排序
3. ↑↓ 移动选中 → 高亮行变化
4. 回车 → 执行命令，launcher 关闭
5. Escape / 点击遮罩 → launcher 关闭
6. 输入框为空 → 无结果显示，只有 placeholder
7. 双击 Shift 再次 → toggle 关闭

- [ ] **运行全部单元测试**

```bash
xcodebuild test \
  -project macos/Ghostty.xcodeproj \
  -scheme Ghostty \
  -destination "platform=macOS" \
  2>&1 | grep -E "Test Suite|passed|failed" | tail -20
```

预期：所有测试通过，无 failure。

- [ ] **最终 Commit**

```bash
git add -A
git status  # 确认无遗漏
git commit -m "feat(app-launcher): complete App Launcher feature - double-shift launcher with edit distance search"
```

- [ ] **提 PR**

```bash
git push origin feat/app-launcher
gh pr create \
  --title "feat: App Launcher - 双击 Shift 唤起命令搜索" \
  --body "$(cat <<'EOF'
## 功能说明

双击 Shift 键唤起悬浮命令 Launcher，输入任意字符后显示基于编辑距离排序的菜单项，回车执行。

## 新增文件

- `EditDistanceFilter.swift` — Levenshtein 距离排序
- `AppCommandRegistry.swift` — 命令收集（菜单扫描 + Poltertty actions）
- `ShiftDoubleTapDetector.swift` — 双击 Shift 检测
- `AppLauncherView.swift` — SwiftUI 浮层 UI

## 测试

- `EditDistanceFilterTests.swift` — 单元测试（纯算法逻辑）
- 手动验证：双击 Shift 弹出、搜索、键盘导航、执行、关闭

🤖 Generated with Claude Code
EOF
)"
```
