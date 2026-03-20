# Tmux Tab Attach Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 通过 File 菜单快速创建 attach 到 tmux session 的 tab，提供原生 window 切换 overlay 和 detach 操作。

**Architecture:** 在 `TabItem` 中添加可选的 `TmuxAttachState`，通过 `TmuxTabMonitor` 轮询已 attach tab 的 window 列表驱动 `TmuxWindowBar` overlay。菜单入口触发 `TmuxSessionPicker` sheet 对话框，用户选择 session 后创建新 tab 并注入 attach 命令。

**Tech Stack:** Swift 6 / SwiftUI / AppKit (NSMenuItem) / Swift Testing

---

## 重要参考

- **设计文档**：`docs/superpowers/specs/2026-03-20-tmux-tab-attach-design.md`
- **构建命令**：`make dev`（增量）；`make dev-clean`（清理后重建）
- **运行测试**：`cd macos && xcodebuild test -project Ghostty.xcodeproj -scheme GhosttyTests -destination 'platform=macOS' 2>&1 | grep -E "passed|failed|error:"`
- **Shell 转义**：`Ghostty.Shell.escape()` 定义在 `macos/Sources/Ghostty/Ghostty.Shell.swift`
- **测试格式**：`import Testing` + `@Test` + `#expect`（参考 `macos/Tests/Tmux/TmuxParserTests.swift`）
- **XIB 修改注意**：XIB 文件是 XML 格式，需手动编辑或在 Xcode 中操作

## 文件结构

### 新增文件（4 个）

| 文件 | 职责 |
|------|------|
| `macos/Sources/Features/Tmux/TmuxSessionPicker.swift` | Session 选择对话框 UI（SwiftUI Sheet） |
| `macos/Sources/Features/Tmux/TmuxSessionPickerViewModel.swift` | 对话框状态管理（加载 sessions、模式切换） |
| `macos/Sources/Features/Tmux/TmuxWindowBar.swift` | 终端右上角 window 切换 overlay + detach 按钮 |
| `macos/Sources/Features/Tmux/TmuxTabMonitor.swift` | 已 attach tab 的 tmux window 状态轮询 |

### 修改文件（6 个）

| 文件 | 变更 |
|------|------|
| `macos/Sources/Features/Tmux/TmuxModels.swift` | 新增 `TmuxAttachState` 结构体 |
| `macos/Sources/Features/Workspace/TabBar/TabBarViewModel.swift` | `TabItem` 增加 `tmuxState` 属性 |
| `macos/Sources/Features/Terminal/TerminalController.swift` | `addNewTabWithTmux()` + 关闭拦截 |
| `macos/Sources/Features/Workspace/PolterttyRootView.swift` | overlay 集成 + sheet + 通知 |
| `macos/Sources/App/macOS/AppDelegate.swift` | tmux 顶级菜单新增 "New Tab with tmux Session..."（与 Toggle tmux Panel 同级，比放在 File 菜单更符合功能分组） |

---

## Task 1: 数据模型 — TmuxAttachState + TabItem 扩展

**Files:**
- Modify: `macos/Sources/Features/Tmux/TmuxModels.swift`
- Modify: `macos/Sources/Features/Workspace/TabBar/TabBarViewModel.swift`

- [ ] **Step 1: 在 TmuxModels.swift 末尾添加 TmuxAttachState**

在 `TmuxPanelState` 枚举之后追加：

```swift
struct TmuxAttachState: Equatable {
    let sessionName: String
    var activeWindowIndex: Int
    var activeWindowName: String
    var windows: [WindowInfo]

    struct WindowInfo: Equatable, Identifiable {
        let index: Int
        let name: String
        let active: Bool
        var id: Int { index }
    }
}
```

- [ ] **Step 2: 在 TabItem 中添加 tmuxState 属性**

在 `macos/Sources/Features/Workspace/TabBar/TabBarViewModel.swift` 的 `TabItem` 结构体中，在 `surfaceId` 之后添加：

```swift
var tmuxState: TmuxAttachState?  // nil = 普通 tab，非 nil = 已 attach tmux session
```

- [ ] **Step 3: 构建验证**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty && make dev 2>&1 | tail -5
```

预期：`BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Tmux/TmuxModels.swift \
        macos/Sources/Features/Workspace/TabBar/TabBarViewModel.swift
git commit -m "feat(tmux): add TmuxAttachState model and TabItem.tmuxState property"
```

---

## Task 2: TmuxTabMonitor — tmux tab 状态轮询

**Files:**
- Create: `macos/Sources/Features/Tmux/TmuxTabMonitor.swift`

- [ ] **Step 1: 创建 TmuxTabMonitor.swift**

```swift
// macos/Sources/Features/Tmux/TmuxTabMonitor.swift
import Foundation

/// 追踪已 attach tmux session 的 tab，定时轮询 window 列表更新 TmuxAttachState。
@MainActor
final class TmuxTabMonitor {

    private weak var tabBarViewModel: TabBarViewModel?
    private var timer: Timer?

    init(tabBarViewModel: TabBarViewModel) {
        self.tabBarViewModel = tabBarViewModel
    }

    /// 启动轮询（幂等，重复调用不会创建多个 timer）
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
        // 立即执行一次
        poll()
    }

    /// 停止轮询
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 检查是否还有需要监控的 tmux tab，无则自动停止
    func stopIfIdle() {
        guard let vm = tabBarViewModel else { stop(); return }
        if !vm.tabs.contains(where: { $0.tmuxState != nil }) {
            stop()
        }
    }

    private func poll() {
        guard let vm = tabBarViewModel else { return }
        let tmuxTabs = vm.tabs.filter { $0.tmuxState != nil }
        guard !tmuxTabs.isEmpty else { stop(); return }

        for tab in tmuxTabs {
            guard let state = tab.tmuxState else { continue }
            Task {
                await updateWindows(for: tab.id, sessionName: state.sessionName)
            }
        }
    }

    private func updateWindows(for tabId: UUID, sessionName: String) async {
        guard let vm = tabBarViewModel else { return }

        do {
            let output = try await TmuxCommandRunner.run(
                args: ["list-windows", "-t", sessionName, "-F",
                       "#{window_index}|#{window_name}|#{window_active}"]
            )
            let tmuxWindows = TmuxParser.parseWindows(output, sessionName: sessionName)
            let windowInfos = tmuxWindows.map { w in
                TmuxAttachState.WindowInfo(
                    index: w.windowIndex,
                    name: w.name,
                    active: w.active
                )
            }
            let activeWindow = tmuxWindows.first(where: { $0.active }) ?? tmuxWindows.first
            guard let idx = vm.tabs.firstIndex(where: { $0.id == tabId }) else { return }
            vm.tabs[idx].tmuxState = TmuxAttachState(
                sessionName: sessionName,
                activeWindowIndex: activeWindow?.windowIndex ?? 0,
                activeWindowName: activeWindow?.name ?? "",
                windows: windowInfos
            )
        } catch {
            // Session 不存在或 tmux server 停止 — 清除该 tab 的 tmuxState
            guard let idx = vm.tabs.firstIndex(where: { $0.id == tabId }) else { return }
            vm.tabs[idx].tmuxState = nil
            stopIfIdle()
        }
    }
}
```

- [ ] **Step 2: 在 TabBarViewModel 中持有 TmuxTabMonitor**

在 `macos/Sources/Features/Workspace/TabBar/TabBarViewModel.swift` 的 `TabBarViewModel` 类中，在 `surfaces` 属性之后添加：

```swift
/// 追踪已 attach tmux session 的 tab 状态
lazy var tmuxMonitor: TmuxTabMonitor = TmuxTabMonitor(tabBarViewModel: self)
```

- [ ] **Step 3: 在 Xcode 中添加 TmuxTabMonitor.swift 到项目**

打开 Xcode → 将 `TmuxTabMonitor.swift` 拖入 `macos/Sources/Features/Tmux/` Group，勾选 `Ghostty` target。

- [ ] **Step 4: 构建验证**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty && make dev 2>&1 | tail -5
```

预期：`BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Tmux/TmuxTabMonitor.swift \
        macos/Sources/Features/Workspace/TabBar/TabBarViewModel.swift \
        macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "feat(tmux): add TmuxTabMonitor for polling tmux tab window state"
```

---

## Task 3: TmuxSessionPickerViewModel — 对话框状态管理

**Files:**
- Create: `macos/Sources/Features/Tmux/TmuxSessionPickerViewModel.swift`

- [ ] **Step 1: 创建 TmuxSessionPickerViewModel.swift**

```swift
// macos/Sources/Features/Tmux/TmuxSessionPickerViewModel.swift
import Foundation

@MainActor
final class TmuxSessionPickerViewModel: ObservableObject {
    enum Mode {
        case attachExisting
        case createNew
    }

    @Published var mode: Mode = .attachExisting
    @Published var sessions: [TmuxSession] = []
    @Published var selectedSessionName: String? = nil
    @Published var newSessionName: String = ""
    @Published var isLoading: Bool = true
    @Published var errorMessage: String? = nil

    /// 加载现有 tmux sessions（复用 TmuxCommandRunner + TmuxParser）
    func loadSessions() async {
        isLoading = true
        errorMessage = nil
        do {
            let output = try await TmuxCommandRunner.run(
                args: ["list-sessions", "-F", "#{session_name}|#{session_attached}"]
            )
            sessions = TmuxParser.parseSessions(output)
            // 默认选中第一个
            if selectedSessionName == nil, let first = sessions.first {
                selectedSessionName = first.id
            }
        } catch let error as TmuxError {
            switch error {
            case .notInstalled:
                errorMessage = "tmux 未安装"
            case .serverNotRunning:
                // 无 session 时 tmux 也报这个错
                sessions = []
            case .timeout:
                errorMessage = "tmux 响应超时"
            }
        } catch {
            errorMessage = "未知错误"
        }
        // 无 session 时自动切换到新建模式
        if sessions.isEmpty && errorMessage == nil {
            mode = .createNew
        }
        isLoading = false
    }

    /// 是否可以执行 Open
    var canOpen: Bool {
        switch mode {
        case .attachExisting:
            return selectedSessionName != nil
        case .createNew:
            return true  // name 可空，tmux 自动分配
        }
    }

    /// 获取最终要 attach 的 session name（新建 session 时先创建）
    func resolveSessionName() async -> String? {
        switch mode {
        case .attachExisting:
            return selectedSessionName
        case .createNew:
            let name = newSessionName.trimmingCharacters(in: .whitespaces)
            if name.isEmpty {
                // 不指定名称，tmux 自动分配
                do {
                    let output = try await TmuxCommandRunner.run(
                        args: ["new-session", "-d", "-P", "-F", "#{session_name}"]
                    )
                    return output.trimmingCharacters(in: .whitespacesAndNewlines)
                } catch {
                    errorMessage = "创建 session 失败"
                    return nil
                }
            } else {
                do {
                    try await TmuxCommandRunner.runSilent(
                        args: ["new-session", "-d", "-s", name]
                    )
                    return name
                } catch {
                    errorMessage = "创建 session \"\(name)\" 失败（可能已存在）"
                    return nil
                }
            }
        }
    }
}
```

- [ ] **Step 2: 在 Xcode 中添加文件到项目**

将 `TmuxSessionPickerViewModel.swift` 拖入 `macos/Sources/Features/Tmux/` Group，勾选 `Ghostty` target。

- [ ] **Step 3: 构建验证**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty && make dev 2>&1 | tail -5
```

预期：`BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Tmux/TmuxSessionPickerViewModel.swift \
        macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "feat(tmux): add TmuxSessionPickerViewModel for session selection dialog"
```

---

## Task 4: TmuxSessionPicker — 对话框 UI

**Files:**
- Create: `macos/Sources/Features/Tmux/TmuxSessionPicker.swift`

- [ ] **Step 1: 创建 TmuxSessionPicker.swift**

```swift
// macos/Sources/Features/Tmux/TmuxSessionPicker.swift
import SwiftUI

struct TmuxSessionPicker: View {
    @StateObject private var viewModel = TmuxSessionPickerViewModel()
    let onOpen: (String) -> Void  // 传回 session name
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("New Tab with tmux Session")
                .font(.system(size: 14, weight: .semibold))

            if viewModel.isLoading {
                ProgressView()
                    .frame(height: 120)
            } else if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.system(size: 12))
            } else {
                // Mode picker
                Picker("", selection: $viewModel.mode) {
                    Text("Attach to existing").tag(TmuxSessionPickerViewModel.Mode.attachExisting)
                    Text("Create new").tag(TmuxSessionPickerViewModel.Mode.createNew)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if viewModel.mode == .attachExisting {
                    existingSessionList
                } else {
                    newSessionForm
                }
            }

            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Open") {
                    Task {
                        guard let name = await viewModel.resolveSessionName() else { return }
                        onOpen(name)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canOpen)
            }
        }
        .padding(24)
        .frame(width: 360)
        .task {
            await viewModel.loadSessions()
        }
    }

    @ViewBuilder
    private var existingSessionList: some View {
        if viewModel.sessions.isEmpty {
            Text("没有可用的 tmux session")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
                .frame(height: 80)
        } else {
            List(viewModel.sessions, selection: $viewModel.selectedSessionName) { session in
                HStack {
                    Text(session.id)
                        .font(.system(size: 12))
                    Spacer()
                    if session.attached {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .help("已有 client 连接")
                    }
                }
                .tag(session.id)
                .contentShape(Rectangle())
            }
            .listStyle(.bordered)
            .frame(height: min(CGFloat(viewModel.sessions.count) * 28 + 8, 160))
        }
    }

    @ViewBuilder
    private var newSessionForm: some View {
        HStack {
            Text("Session name:")
                .font(.system(size: 12))
            TextField("留空自动命名", text: $viewModel.newSessionName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
        }
    }
}
```

- [ ] **Step 2: 在 Xcode 中添加文件到项目**

将 `TmuxSessionPicker.swift` 拖入 `macos/Sources/Features/Tmux/` Group，勾选 `Ghostty` target。

- [ ] **Step 3: 构建验证**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty && make dev 2>&1 | tail -5
```

预期：`BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Tmux/TmuxSessionPicker.swift \
        macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "feat(tmux): add TmuxSessionPicker dialog UI"
```

---

## Task 5: TerminalController — addNewTabWithTmux + 关闭拦截

**Files:**
- Modify: `macos/Sources/Features/Terminal/TerminalController.swift`

- [ ] **Step 1: 添加 addNewTabWithTmux 方法**

在 `TerminalController` 的 `addNewTab()` 方法之后，添加：

```swift
/// 创建新 tab 并 attach 到指定 tmux session
@MainActor
func addNewTabWithTmux(sessionName: String) {
    addNewTab()

    // 设置新 tab 的初始 tmuxState
    if let activeId = tabBarViewModel.activeTabId,
       let idx = tabBarViewModel.tabs.firstIndex(where: { $0.id == activeId }) {
        tabBarViewModel.tabs[idx].tmuxState = TmuxAttachState(
            sessionName: sessionName,
            activeWindowIndex: 0,
            activeWindowName: "",
            windows: []
        )
        // 锁定 tab 标题为 session name
        tabBarViewModel.renameTab(activeId, title: "tmux: \(sessionName)")
    }

    // 延迟注入 attach 命令（等待 shell 就绪）
    let escapedName = Ghostty.Shell.escape(sessionName)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
        self?.injectToActiveSurface("tmux attach-session -t \(escapedName)\n")
    }

    // 启动 tmux tab monitor
    tabBarViewModel.tmuxMonitor.start()
}
```

- [ ] **Step 2: 修改 closePolterttyTab 添加 tmux 拦截**

找到 `closePolterttyTab(_:)` 方法，替换为：

```swift
/// Close a tab in the custom poltertty tab bar
@MainActor
func closePolterttyTab(_ id: UUID) {
    guard tabBarViewModel.tabs.count > 1 else {
        // 单 tab 时走 window 关闭流程
        if let state = tabBarViewModel.tabs.first?.tmuxState {
            showTmuxCloseConfirmation(tabId: id, sessionName: state.sessionName) {
                self.window?.close()
            }
            return
        }
        window?.close()
        return
    }
    // 检查是否是 tmux tab
    if let tab = tabBarViewModel.tabs.first(where: { $0.id == id }),
       let state = tab.tmuxState {
        showTmuxCloseConfirmation(tabId: id, sessionName: state.sessionName) {
            self.tabBarViewModel.closeTab(id)
            self.tabBarViewModel.tmuxMonitor.stopIfIdle()
        }
        return
    }
    tabBarViewModel.closeTab(id)
}
```

- [ ] **Step 3: 添加 tmux 关闭确认对话框方法**

在 `closePolterttyTab` 之后添加：

```swift
/// 显示 tmux tab 关闭确认对话框
private func showTmuxCloseConfirmation(tabId: UUID, sessionName: String, onClose: @escaping () -> Void) {
    guard let window else { return }
    let alert = NSAlert()
    alert.messageText = "Tmux Session \"\(sessionName)\""
    alert.informativeText = "该 tab 已 attach 到 tmux session，你想要："
    alert.addButton(withTitle: "Detach")           // returnCode 1000
    alert.addButton(withTitle: "Kill Session")     // returnCode 1001
    alert.addButton(withTitle: "取消")              // returnCode 1002
    alert.buttons[1].hasDestructiveAction = true

    alert.beginSheetModal(for: window) { response in
        switch response {
        case .alertFirstButtonReturn:
            // Detach：通过子进程 detach，不依赖终端状态
            Task {
                try? await TmuxCommandRunner.runSilent(
                    args: ["detach-client", "-s", sessionName]
                )
                await MainActor.run {
                    // 等 shell 恢复
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        onClose()
                    }
                }
            }
        case .alertSecondButtonReturn:
            // Kill Session
            Task {
                try? await TmuxCommandRunner.runSilent(
                    args: ["kill-session", "-t", sessionName]
                )
                await MainActor.run { onClose() }
            }
        default:
            break  // 取消
        }
    }
}
```

- [ ] **Step 4: 添加统一的 tmux tab 检查辅助方法**

在 `showTmuxCloseConfirmation` 之后添加：

```swift
/// 检查是否有任何 tab 包含 tmux session（用于 window 级关闭拦截）
private func anyTmuxTab() -> (tabId: UUID, sessionName: String)? {
    for tab in tabBarViewModel.tabs {
        if let state = tab.tmuxState {
            return (tab.id, state.sessionName)
        }
    }
    return nil
}
```

- [ ] **Step 5: 修改 closeSurface 添加 tmux 拦截**

找到 `override func closeSurface` 方法（约 line 819），在方法开头 `if surfaceTree.root != node` 之前添加：

```swift
// 如果关闭的是 root（即整个 tab），检查 tmux 状态
if surfaceTree.root == node,
   let activeId = tabBarViewModel.activeTabId,
   let tab = tabBarViewModel.tabs.first(where: { $0.id == activeId }),
   let state = tab.tmuxState {
    closePolterttyTab(activeId)  // 复用已有的 tmux 拦截逻辑
    return
}
```

- [ ] **Step 6: 修改 windowShouldClose 添加 tmux 拦截**

找到 `override func windowShouldClose(_ sender: NSWindow) -> Bool` 方法（约 line 1484），在 `tabGroupCloseCoordinator.windowShouldClose` 调用之前添加：

```swift
// 检查是否有 tmux tab 需要确认
if let tmux = anyTmuxTab() {
    showTmuxCloseConfirmation(tabId: tmux.tabId, sessionName: tmux.sessionName) {
        // detach/kill 完成后，清除 tmuxState 再走正常关闭流程
        if let idx = self.tabBarViewModel.tabs.firstIndex(where: { $0.id == tmux.tabId }) {
            self.tabBarViewModel.tabs[idx].tmuxState = nil
        }
        // 重新触发关闭（此时不再有 tmux tab）
        self.window?.performClose(nil)
    }
    return false
}
```

- [ ] **Step 7: 构建验证**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty && make dev 2>&1 | tail -5
```

预期：`BUILD SUCCEEDED`

- [ ] **Step 8: Commit**

```bash
git add macos/Sources/Features/Terminal/TerminalController.swift
git commit -m "feat(tmux): add addNewTabWithTmux and tmux tab close confirmation on all paths"
```

---

## Task 6: TmuxWindowBar — Window 切换 Overlay

**Files:**
- Create: `macos/Sources/Features/Tmux/TmuxWindowBar.swift`

- [ ] **Step 1: 创建 TmuxWindowBar.swift**

```swift
// macos/Sources/Features/Tmux/TmuxWindowBar.swift
import SwiftUI

/// 终端右上角 tmux window 切换 overlay + detach 按钮
struct TmuxWindowBar: View {
    let state: TmuxAttachState
    let onSelectWindow: (Int) -> Void   // window index
    let onDetach: () -> Void

    @State private var isHovered = false
    @State private var showOverflowPopover = false

    /// 最多显示 4 个 window
    private let maxVisible = 4

    var body: some View {
        HStack(spacing: 4) {
            // Window 药丸标签
            ForEach(visibleWindows) { window in
                windowPill(window)
            }

            // 溢出按钮
            if state.windows.count > maxVisible {
                overflowPill
            }

            // Detach 按钮
            detachButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .opacity(isHovered ? 1.0 : 0.4)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var visibleWindows: [TmuxAttachState.WindowInfo] {
        Array(state.windows.prefix(maxVisible))
    }

    private func windowPill(_ window: TmuxAttachState.WindowInfo) -> some View {
        Button {
            onSelectWindow(window.index)
        } label: {
            Text("\(window.index):\(window.name)")
                .font(.system(size: 10, weight: window.active ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    window.active
                        ? AnyShapeStyle(Color.accentColor.opacity(0.3))
                        : AnyShapeStyle(.quaternary)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var overflowPill: some View {
        Button {
            showOverflowPopover = true
        } label: {
            Text("···")
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showOverflowPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(state.windows) { window in
                    Button {
                        onSelectWindow(window.index)
                        showOverflowPopover = false
                    } label: {
                        HStack {
                            Text("\(window.index):\(window.name)")
                                .font(.system(size: 11))
                            Spacer()
                            if window.active {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .frame(minWidth: 140)
        }
    }

    private var detachButton: some View {
        Button {
            onDetach()
        } label: {
            Image(systemName: "eject")
                .font(.system(size: 10))
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Detach from tmux session")
    }
}
```

- [ ] **Step 2: 在 Xcode 中添加文件到项目**

将 `TmuxWindowBar.swift` 拖入 `macos/Sources/Features/Tmux/` Group，勾选 `Ghostty` target。

- [ ] **Step 3: 构建验证**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty && make dev 2>&1 | tail -5
```

预期：`BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Tmux/TmuxWindowBar.swift \
        macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "feat(tmux): add TmuxWindowBar overlay for window switching and detach"
```

---

## Task 7: PolterttyRootView — 集成 overlay + sheet

**Files:**
- Modify: `macos/Sources/Features/Workspace/PolterttyRootView.swift`

- [ ] **Step 1: 添加通知名和 State 变量**

在 `PolterttyRootView.swift` 的 `Notification.Name` 扩展中添加：

```swift
static let showTmuxSessionPicker = Notification.Name("poltertty.showTmuxSessionPicker")
```

在 `PolterttyRootView` 结构体的 `@State` 变量区域添加：

```swift
@State private var showTmuxPicker = false
```

- [ ] **Step 2: 在 terminalAreaView 中添加 TmuxWindowBar overlay**

找到 `terminalAreaView` 计算属性中的 `terminalView` 行，将其包裹在 overlay 中：

将：
```swift
terminalView
```

替换为：
```swift
terminalView
    .overlay(alignment: .topTrailing) {
        if let activeId = tabBarViewModel.activeTabId,
           let tab = tabBarViewModel.tabs.first(where: { $0.id == activeId }),
           let tmuxState = tab.tmuxState,
           !tmuxState.windows.isEmpty {
            TmuxWindowBar(
                state: tmuxState,
                onSelectWindow: { index in
                    guard let sessionName = tab.tmuxState?.sessionName else { return }
                    Task {
                        try? await TmuxCommandRunner.runSilent(
                            args: ["select-window", "-t", "\(sessionName):\(index)"]
                        )
                    }
                },
                onDetach: {
                    guard let sessionName = tab.tmuxState?.sessionName else { return }
                    Task {
                        try? await TmuxCommandRunner.runSilent(
                            args: ["detach-client", "-s", sessionName]
                        )
                        // 清除 tmuxState
                        if let idx = tabBarViewModel.tabs.firstIndex(where: { $0.id == activeId }) {
                            tabBarViewModel.tabs[idx].tmuxState = nil
                            tabBarViewModel.tmuxMonitor.stopIfIdle()
                        }
                    }
                }
            )
            .padding(8)
            .transition(.opacity)
        }
    }
```

- [ ] **Step 3: 添加 sheet 和通知接收**

在 `body` 的 `.onReceive(NotificationCenter.default.publisher(for: .toggleTmuxPanel))` 之后添加：

```swift
.onReceive(NotificationCenter.default.publisher(for: .showTmuxSessionPicker)) { _ in
    showTmuxPicker = true
}
.sheet(isPresented: $showTmuxPicker) {
    TmuxSessionPicker(
        onOpen: { sessionName in
            showTmuxPicker = false
            // 通过通知让 TerminalController 创建 tmux tab
            NotificationCenter.default.post(
                name: .tmuxAttachNewTab,
                object: nil,
                userInfo: ["sessionName": sessionName]
            )
        },
        onCancel: { showTmuxPicker = false }
    )
}
```

- [ ] **Step 4: 添加 tmuxAttachNewTab 通知名**

在 `Notification.Name` 扩展中添加：

```swift
static let tmuxAttachNewTab = Notification.Name("poltertty.tmuxAttachNewTab")
```

- [ ] **Step 5: 构建验证**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty && make dev 2>&1 | tail -5
```

预期：`BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Workspace/PolterttyRootView.swift
git commit -m "feat(tmux): integrate TmuxWindowBar overlay and TmuxSessionPicker sheet"
```

---

## Task 8: TerminalController — 监听 tmuxAttachNewTab 通知

**Files:**
- Modify: `macos/Sources/Features/Terminal/TerminalController.swift`

- [ ] **Step 1: 注册通知观察**

在 `init` 中 `onTmuxAttachInCurrentPane` 通知注册之后添加：

```swift
center.addObserver(
    self,
    selector: #selector(onTmuxAttachNewTab(_:)),
    name: .tmuxAttachNewTab,
    object: nil
)
```

- [ ] **Step 2: 添加通知处理方法**

在 `onTmuxAttachInCurrentPane` 方法之后添加：

```swift
@objc private func onTmuxAttachNewTab(_ notification: Notification) {
    guard window?.isKeyWindow == true,
          let sessionName = notification.userInfo?["sessionName"] as? String else { return }
    addNewTabWithTmux(sessionName: sessionName)
}
```

- [ ] **Step 3: 构建验证**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty && make dev 2>&1 | tail -5
```

预期：`BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Terminal/TerminalController.swift
git commit -m "feat(tmux): handle tmuxAttachNewTab notification in TerminalController"
```

---

## Task 9: AppDelegate — 菜单项

**Files:**
- Modify: `macos/Sources/App/macOS/AppDelegate.swift`

- [ ] **Step 1: 在 setupWorkspaceMenu 的 tmux 菜单中添加菜单项**

在 `setupWorkspaceMenu()` 方法中，找到 tmux 菜单部分（`let tmuxMenu = NSMenu(title: "tmux")`），在 `tmuxPanelItem` 之前插入新菜单项：

```swift
let newTabTmux = NSMenuItem(
    title: "New Tab with tmux Session...",
    action: #selector(AppDelegate.newTabWithTmuxSession(_:)),
    keyEquivalent: "t"
)
newTabTmux.keyEquivalentModifierMask = [.command, .option]
tmuxMenu.addItem(newTabTmux)
tmuxMenu.addItem(.separator())
```

- [ ] **Step 2: 添加 action 方法**

在 `toggleTmuxPanel(_:)` 方法之后添加：

```swift
@objc func newTabWithTmuxSession(_ sender: Any?) {
    NotificationCenter.default.post(
        name: .showTmuxSessionPicker,
        object: nil
    )
}
```

- [ ] **Step 3: 构建验证**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty && make dev 2>&1 | tail -5
```

预期：`BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/App/macOS/AppDelegate.swift
git commit -m "feat(tmux): add 'New Tab with tmux Session...' menu item (Cmd+Option+T)"
```

---

## Task 10: 手动验证 + 最终清理

- [ ] **Step 1: 完整构建**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty && make dev-clean 2>&1 | tail -10
```

预期：`BUILD SUCCEEDED`

- [ ] **Step 2: 手动测试 — 菜单与对话框**

1. 启动 Poltertty
2. 顶部菜单栏 → tmux → "New Tab with tmux Session..."（或 `Cmd+Option+T`）
3. 确认对话框正确显示
4. 如果有 tmux session：选择一个，点 Open → 新 tab 打开并 attach
5. 如果无 tmux session：切换到 Create new，输入名称，点 Open → 创建并 attach

- [ ] **Step 3: 手动测试 — Window 切换 overlay**

1. 在已 attach 的 tmux tab 中
2. 确认右上角出现 window 药丸标签
3. 在 tmux 中创建新 window（`Ctrl+B c`）
4. 等待 2 秒，确认 overlay 更新显示新 window
5. 点击非 active window 药丸 → 确认切换成功

- [ ] **Step 4: 手动测试 — Detach**

1. 在已 attach 的 tmux tab 中
2. 点击 `⏏` 按钮
3. 确认 detach 成功：overlay 消失，终端回到普通 shell
4. 确认 tmux session 仍在运行：`tmux ls`

- [ ] **Step 5: 手动测试 — 关闭 tab 确认**

1. 在已 attach 的 tmux tab 中
2. 关闭 tab（点关闭按钮或 `Cmd+W`）
3. 确认弹出 Detach/Kill Session/取消 对话框
4. 测试 Detach：session 应保留
5. 重复，测试 Kill Session：session 应被删除

- [ ] **Step 6: 最终 Commit（若有修复）**

```bash
git status
# 若有未提交的修复文件：
git add <files>
git commit -m "fix(tmux): post-testing fixes for tmux tab attach"
```
