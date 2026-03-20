# tmux 管理面板 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Poltertty 新增独立的 tmux 管理面板，与文件树面板并排在左侧，支持 sessions/windows/panes 的完整管理操作。

**Architecture:** 纯 CLI 轮询方案——`TmuxCommandRunner` 封装 `Process` 执行 tmux 子命令，`TmuxParser` 纯函数解析 `-F` 格式化输出，`TmuxPanelViewModel` per-window 实例持有 2s Timer，`TmuxPanelView` 树形 SwiftUI 视图。不涉及 Zig 代码或 tmux control mode。

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Testing, macOS 14+, AppKit（Process）

---

## 文件结构

### 新增文件

| 文件 | 职责 |
|------|------|
| `macos/Sources/Features/Tmux/TmuxModels.swift` | 数据结构：`TmuxSession`, `TmuxWindow`, `TmuxPane`, `TmuxError`, `TmuxPanelState` |
| `macos/Sources/Features/Tmux/TmuxCommandRunner.swift` | `async/await` 封装 `Process` + PATH 扩展 + Task 取消 |
| `macos/Sources/Features/Tmux/TmuxParser.swift` | 纯函数：字符串 → 数据模型 |
| `macos/Sources/Features/Tmux/TmuxPanelViewModel.swift` | `@MainActor ObservableObject`，2s Timer，pause/resume/stop |
| `macos/Sources/Features/Tmux/TmuxPanelView.swift` | 面板根视图：树形列表 + 标题栏 + 错误/空状态 + banner |
| `macos/Sources/Features/Tmux/TmuxSessionRow.swift` | Session 行 + 右键菜单 |
| `macos/Sources/Features/Tmux/TmuxWindowRow.swift` | Window 行 + 右键菜单 + 双击跳转 |
| `macos/Sources/Features/Tmux/TmuxPaneRow.swift` | Pane 行 + 右键菜单 |
| `macos/Tests/Tmux/TmuxParserTests.swift` | `TmuxParser` 单元测试（Swift Testing） |

### 修改文件

| 文件 | 变更 |
|------|------|
| `macos/Sources/Features/Workspace/PolterttyRootView.swift` | 新增 `@ObservedObject tmuxPanelVM`，插入面板分支和可拖拽 divider |
| `macos/Ghostty.xcodeproj/project.pbxproj` | 注册所有新文件到 Ghostty target 和 GhosttyTests target |

---

## Task 1: 数据模型 TmuxModels.swift

**Files:**
- Create: `macos/Sources/Features/Tmux/TmuxModels.swift`

- [ ] **Step 1: 创建 TmuxModels.swift**

```swift
// macos/Sources/Features/Tmux/TmuxModels.swift
import Foundation

struct TmuxSession: Identifiable, Equatable {
    let id: String          // session name
    var windows: [TmuxWindow]
    var attached: Bool
}

struct TmuxWindow: Identifiable, Equatable {
    let id: String          // 复合 ID："\(sessionName):\(windowIndex)"
    let sessionName: String
    let windowIndex: Int
    var name: String
    var panes: [TmuxPane]
    var active: Bool
}

struct TmuxPane: Identifiable, Equatable {
    let id: Int             // pane_id 数字部分（tmux 原始格式 "%N"，去掉 % 前缀）
    var title: String
    var active: Bool
    var width: Int
    var height: Int
}

enum TmuxError: Equatable {
    case notInstalled
    case serverNotRunning(stderr: String)
    case timeout
}

enum TmuxPanelState: Equatable {
    case loading
    case empty
    case loaded([TmuxSession])
    case error(TmuxError)
}
```

- [ ] **Step 2: 提交**

```bash
git add macos/Sources/Features/Tmux/TmuxModels.swift
git commit -m "feat(tmux): add TmuxModels data structures"
```

---

## Task 2: TmuxParser 及其单元测试（TDD）

**Files:**
- Create: `macos/Sources/Features/Tmux/TmuxParser.swift`
- Create: `macos/Tests/Tmux/TmuxParserTests.swift`

- [ ] **Step 1: 先写测试 TmuxParserTests.swift**

```swift
// macos/Tests/Tmux/TmuxParserTests.swift
import Testing
@testable import Ghostty

struct TmuxParserTests {

    // MARK: - parseSessions

    @Test func parseSessions_normalOutput() {
        let input = """
        my-project|1
        dotfiles|0
        """
        let sessions = TmuxParser.parseSessions(input)
        #expect(sessions.count == 2)
        #expect(sessions[0].id == "my-project")
        #expect(sessions[0].attached == true)
        #expect(sessions[1].id == "dotfiles")
        #expect(sessions[1].attached == false)
    }

    @Test func parseSessions_emptyOutput() {
        #expect(TmuxParser.parseSessions("").isEmpty)
        #expect(TmuxParser.parseSessions("\n\n").isEmpty)
    }

    @Test func parseSessions_sessionNameWithSpaces() {
        let input = "my project|1"
        let sessions = TmuxParser.parseSessions(input)
        #expect(sessions.count == 1)
        #expect(sessions[0].id == "my project")
    }

    // MARK: - parseWindows

    @Test func parseWindows_normalOutput() {
        let input = """
        0|vim|1
        1|server|0
        2|logs|0
        """
        let windows = TmuxParser.parseWindows(input, sessionName: "proj")
        #expect(windows.count == 3)
        #expect(windows[0].id == "proj:0")
        #expect(windows[0].sessionName == "proj")
        #expect(windows[0].windowIndex == 0)
        #expect(windows[0].name == "vim")
        #expect(windows[0].active == true)
        #expect(windows[1].active == false)
    }

    @Test func parseWindows_emptyOutput() {
        #expect(TmuxParser.parseWindows("", sessionName: "s").isEmpty)
    }

    @Test func parseWindows_idIsComposite() {
        // 不同 session 的 window 0 ID 不能相同
        let w1 = TmuxParser.parseWindows("0|vim|1", sessionName: "a")
        let w2 = TmuxParser.parseWindows("0|vim|1", sessionName: "b")
        #expect(w1[0].id != w2[0].id)
    }

    // MARK: - parsePanes

    @Test func parsePanes_normalOutput() {
        let input = """
        %0|nvim|1|220|50
        %1|zsh|0|220|50
        """
        let panes = TmuxParser.parsePanes(input)
        #expect(panes.count == 2)
        #expect(panes[0].id == 0)
        #expect(panes[0].title == "nvim")
        #expect(panes[0].active == true)
        #expect(panes[0].width == 220)
        #expect(panes[0].height == 50)
        #expect(panes[1].id == 1)
        #expect(panes[1].active == false)
    }

    @Test func parsePanes_emptyOutput() {
        #expect(TmuxParser.parsePanes("").isEmpty)
    }

    @Test func parsePanes_stripsPercentPrefix() {
        let panes = TmuxParser.parsePanes("%42|bash|0|80|24")
        #expect(panes[0].id == 42)
    }

    @Test func parsePanes_invalidLineSkipped() {
        let input = """
        %0|nvim|1|220|50
        invalid_line
        %1|zsh|0|80|24
        """
        let panes = TmuxParser.parsePanes(input)
        #expect(panes.count == 2)
    }
}
```

- [ ] **Step 2: 注册测试文件和源文件到 Xcode project**

**方式 A（Xcode GUI）**：
- 打开 `macos/Ghostty.xcodeproj`
- File → Add Files → 选择 `macos/Tests/Tmux/TmuxParserTests.swift` → 勾选 GhosttyTests target
- File → Add Files → 选择 `macos/Sources/Features/Tmux/TmuxParser.swift`（及同目录下的 `TmuxModels.swift`）→ 勾选 Ghostty target

**方式 B（agentic worker / 命令行）**：
直接编辑 `macos/Ghostty.xcodeproj/project.pbxproj`，参考文件中现有条目（如 `FileBrowserViewModel.swift` 的注册格式）为新文件添加：
1. `PBXBuildFile` 条目（每个文件一条，含 fileRef）
2. `PBXFileReference` 条目（每个文件一条）
3. 将文件引用加入对应 target 的 `PBXSourcesBuildPhase.files` 列表

验证注册正确：

```bash
xcodebuild build -project macos/Ghostty.xcodeproj \
  -scheme Ghostty -destination 'platform=macOS' 2>&1 | grep -E "error:|Build succeeded"
```

此时应报错"cannot find type 'TmuxParser'"（测试已注册但实现尚未注册），确认测试已被编译系统识别。

- [ ] **Step 3: 实现 TmuxParser.swift**

```swift
// macos/Sources/Features/Tmux/TmuxParser.swift
import Foundation

enum TmuxParser {

    /// 解析 `tmux list-sessions -F "#{session_name}|#{session_attached}"` 输出
    static func parseSessions(_ output: String) -> [TmuxSession] {
        output.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { line -> TmuxSession? in
                // 用 lastIndex(of:) 从末尾分割，session name 可能含 "|"
                guard let sep = line.lastIndex(of: "|") else { return nil }
                let name = String(line[line.startIndex..<sep])
                let attachedStr = String(line[line.index(after: sep)...])
                guard !name.isEmpty else { return nil }
                return TmuxSession(id: name, windows: [], attached: attachedStr == "1")
            }
    }

    /// 解析 `tmux list-windows -t <s> -F "#{window_index}|#{window_name}|#{window_active}"` 输出
    static func parseWindows(_ output: String, sessionName: String) -> [TmuxWindow] {
        output.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { line -> TmuxWindow? in
                let parts = line.components(separatedBy: "|")
                guard parts.count >= 3,
                      let index = Int(parts[0]) else { return nil }
                let name = parts[1]
                let active = parts[2] == "1"
                return TmuxWindow(
                    id: "\(sessionName):\(index)",
                    sessionName: sessionName,
                    windowIndex: index,
                    name: name,
                    panes: [],
                    active: active
                )
            }
    }

    /// 解析 `tmux list-panes -t <s> -F "#{pane_id}|#{pane_title}|#{pane_active}|#{pane_width}|#{pane_height}"` 输出
    static func parsePanes(_ output: String) -> [TmuxPane] {
        output.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { line -> TmuxPane? in
                let parts = line.components(separatedBy: "|")
                guard parts.count >= 5 else { return nil }
                // pane_id 格式是 "%N"，去掉 % 前缀
                let rawId = parts[0].hasPrefix("%") ? String(parts[0].dropFirst()) : parts[0]
                guard let paneId = Int(rawId),
                      let width = Int(parts[3]),
                      let height = Int(parts[4]) else { return nil }
                return TmuxPane(
                    id: paneId,
                    title: parts[1],
                    active: parts[2] == "1",
                    width: width,
                    height: height
                )
            }
    }
}
```

- [ ] **Step 4: 注册 TmuxParser.swift 到 Xcode project（Ghostty target）**

- [ ] **Step 5: 编译并运行测试，确认全部通过**

```bash
xcodebuild test -project macos/Ghostty.xcodeproj \
  -scheme Ghostty -destination 'platform=macOS' \
  -only-testing:GhosttyTests/TmuxParserTests 2>&1 | tail -20
```

期望输出：全部测试 PASSED

- [ ] **Step 6: 提交**

```bash
git add macos/Sources/Features/Tmux/TmuxParser.swift \
        macos/Tests/Tmux/TmuxParserTests.swift \
        macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "feat(tmux): add TmuxParser with unit tests"
```

---

## Task 3: TmuxCommandRunner

**Files:**
- Create: `macos/Sources/Features/Tmux/TmuxCommandRunner.swift`

- [ ] **Step 1: 创建 TmuxCommandRunner.swift**

```swift
// macos/Sources/Features/Tmux/TmuxCommandRunner.swift
import Foundation

/// 封装 Process 执行 tmux 子命令。async/await，不阻塞主线程。
/// PATH 扩展覆盖 Homebrew 常见安装位置。
enum TmuxCommandRunner {

    private static let tmuxPath = "/usr/bin/tmux"  // 系统自带路径；Homebrew 路径通过 PATH 查找

    /// 执行 tmux 命令，返回 stdout 字符串，超时 3s 自动取消
    static func run(args: [String]) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await execute(args: args) }
            group.addTask {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                throw TmuxError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// 执行 tmux 命令，忽略输出（用于写操作：new-window、kill-session 等）
    static func runSilent(args: [String]) async throws {
        _ = try await run(args: args)
    }

    private static func execute(args: [String]) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()

            // 扩展 PATH 覆盖 Homebrew 安装位置
            var env = ProcessInfo.processInfo.environment
            let extraPaths = "/usr/local/bin:/opt/homebrew/bin:/opt/local/bin"
            if let existing = env["PATH"] {
                env["PATH"] = "\(extraPaths):\(existing)"
            } else {
                env["PATH"] = extraPaths
            }

            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["tmux"] + args
            process.standardOutput = stdout
            process.standardError = stderr
            process.environment = env

            process.terminationHandler = { p in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let outStr = String(data: outData, encoding: .utf8) ?? ""
                let errStr = String(data: errData, encoding: .utf8) ?? ""

                if p.terminationStatus == 0 {
                    continuation.resume(returning: outStr)
                } else {
                    let lower = errStr.lowercased()
                    if lower.contains("no server running") || lower.contains("no sessions") {
                        continuation.resume(throwing: TmuxError.serverNotRunning(stderr: errStr))
                    } else {
                        // 其他非零退出：当作 notInstalled（找不到 tmux）或 serverNotRunning
                        continuation.resume(throwing: TmuxError.notInstalled)
                    }
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: TmuxError.notInstalled)
            }
        }
    }
}
```

- [ ] **Step 2: 注册到 Xcode project（Ghostty target），确认编译通过**

```bash
xcodebuild build -project macos/Ghostty.xcodeproj \
  -scheme Ghostty -destination 'platform=macOS' 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Step 3: 提交**

```bash
git add macos/Sources/Features/Tmux/TmuxCommandRunner.swift \
        macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "feat(tmux): add TmuxCommandRunner with PATH extension"
```

---

## Task 4: TmuxPanelViewModel

**Files:**
- Create: `macos/Sources/Features/Tmux/TmuxPanelViewModel.swift`

- [ ] **Step 1: 创建 TmuxPanelViewModel.swift**

```swift
// macos/Sources/Features/Tmux/TmuxPanelViewModel.swift
import Foundation
import SwiftUI

@MainActor
final class TmuxPanelViewModel: ObservableObject {

    // MARK: - Published State

    @Published var state: TmuxPanelState = .loading
    @Published var isVisible: Bool = false
    @Published var panelWidth: CGFloat = 240
    @Published var bannerMessage: String? = nil  // 操作失败时短暂显示

    // MARK: - Private

    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?

    // MARK: - Lifecycle

    init() {}

    deinit {
        timer?.invalidate()
        refreshTask?.cancel()
    }

    func resume() {
        scheduleTimer()
        refresh()
    }

    func pause() {
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    func stop() {
        pause()
    }

    // MARK: - Refresh

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            await loadSessions()
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private func loadSessions() async {
        do {
            let sessionsOutput = try await TmuxCommandRunner.run(
                args: ["list-sessions", "-F", "#{session_name}|#{session_attached}"]
            )
            var sessions = TmuxParser.parseSessions(sessionsOutput)

            if sessions.isEmpty {
                state = .empty
                return
            }

            // 并发加载每个 session 的 windows + panes
            sessions = await withTaskGroup(of: TmuxSession.self) { group in
                for session in sessions {
                    group.addTask {
                        await self.loadWindowsAndPanes(for: session)
                    }
                }
                var result: [TmuxSession] = []
                for await s in group { result.append(s) }
                // 保持 sessions 原始顺序
                return sessions.map { s in result.first { $0.id == s.id } ?? s }
            }

            state = .loaded(sessions)
        } catch let error as TmuxError {
            state = .error(error)
        } catch {
            state = .error(.notInstalled)
        }
    }

    private func loadWindowsAndPanes(for session: TmuxSession) async -> TmuxSession {
        var s = session
        guard let windowsOutput = try? await TmuxCommandRunner.run(
            args: ["list-windows", "-t", session.id, "-F",
                   "#{window_index}|#{window_name}|#{window_active}"]
        ) else { return s }

        var windows = TmuxParser.parseWindows(windowsOutput, sessionName: session.id)

        windows = await withTaskGroup(of: TmuxWindow.self) { group in
            for window in windows {
                group.addTask {
                    await self.loadPanes(for: window, sessionName: session.id)
                }
            }
            var result: [TmuxWindow] = []
            for await w in group { result.append(w) }
            return windows.map { w in result.first { $0.id == w.id } ?? w }
        }

        s.windows = windows
        return s
    }

    private func loadPanes(for window: TmuxWindow, sessionName: String) async -> TmuxWindow {
        var w = window
        guard let panesOutput = try? await TmuxCommandRunner.run(
            args: ["list-panes", "-t", "\(sessionName):\(window.windowIndex)", "-F",
                   "#{pane_id}|#{pane_title}|#{pane_active}|#{pane_width}|#{pane_height}"]
        ) else { return w }
        w.panes = TmuxParser.parsePanes(panesOutput)
        return w
    }

    // MARK: - Banner

    func showBanner(_ message: String) {
        bannerMessage = message
        bannerTask?.cancel()
        bannerTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled {
                bannerMessage = nil
            }
        }
    }

    // MARK: - Commands

    func newSession(name: String) async {
        try? await TmuxCommandRunner.runSilent(
            args: ["new-session", "-d", "-s", name]
        )
        refresh()
    }

    func attachSession(_ sessionName: String) async {
        do {
            try await TmuxCommandRunner.runSilent(
                args: ["switch-client", "-t", sessionName]
            )
        } catch {
            showBanner("无 tmux client，请在终端运行 `tmux attach-session -t \(sessionName)`")
        }
        refresh()
    }

    func renameSession(old: String, new: String) async {
        try? await TmuxCommandRunner.runSilent(
            args: ["rename-session", "-t", old, new]
        )
        refresh()
    }

    func killSession(_ name: String) async {
        try? await TmuxCommandRunner.runSilent(
            args: ["kill-session", "-t", name]
        )
        refresh()
    }

    func switchToWindow(sessionName: String, windowIndex: Int) async {
        do {
            try await TmuxCommandRunner.runSilent(
                args: ["switch-client", "-t", "\(sessionName):\(windowIndex)"]
            )
        } catch {
            showBanner("无 tmux client，请在终端运行 `tmux attach-session -t \(sessionName)`")
        }
        refresh()
    }

    func newWindow(sessionName: String) async {
        try? await TmuxCommandRunner.runSilent(
            args: ["new-window", "-t", sessionName]
        )
        refresh()
    }

    func renameWindow(sessionName: String, windowIndex: Int, newName: String) async {
        try? await TmuxCommandRunner.runSilent(
            args: ["rename-window", "-t", "\(sessionName):\(windowIndex)", newName]
        )
        refresh()
    }

    func killWindow(sessionName: String, windowIndex: Int) async {
        try? await TmuxCommandRunner.runSilent(
            args: ["kill-window", "-t", "\(sessionName):\(windowIndex)"]
        )
        refresh()
    }

    func selectPane(paneId: Int) async {
        try? await TmuxCommandRunner.runSilent(
            args: ["select-pane", "-t", "%\(paneId)"]
        )
        refresh()
    }

    func splitPane(paneId: Int, horizontal: Bool) async {
        let flag = horizontal ? "-h" : "-v"
        try? await TmuxCommandRunner.runSilent(
            args: ["split-window", flag, "-t", "%\(paneId)"]
        )
        refresh()
    }

    func killPane(paneId: Int) async {
        try? await TmuxCommandRunner.runSilent(
            args: ["kill-pane", "-t", "%\(paneId)"]
        )
        refresh()
    }
}
```

- [ ] **Step 2: 注册到 Xcode project，编译通过**

- [ ] **Step 3: 提交**

```bash
git add macos/Sources/Features/Tmux/TmuxPanelViewModel.swift \
        macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "feat(tmux): add TmuxPanelViewModel with timer and commands"
```

---

## Task 5: Row 视图

**Files:**
- Create: `macos/Sources/Features/Tmux/TmuxSessionRow.swift`
- Create: `macos/Sources/Features/Tmux/TmuxWindowRow.swift`
- Create: `macos/Sources/Features/Tmux/TmuxPaneRow.swift`

- [ ] **Step 1: 创建 TmuxSessionRow.swift**

```swift
// macos/Sources/Features/Tmux/TmuxSessionRow.swift
import SwiftUI

struct TmuxSessionRow: View {
    let session: TmuxSession
    @Binding var isExpanded: Bool
    let onAttach: () -> Void
    let onRename: () -> Void
    let onKill: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .frame(width: 12)
                .foregroundStyle(.secondary)
            Image(systemName: "terminal")
                .frame(width: 14)
                .foregroundStyle(.secondary)
            Text(session.id)
                .lineLimit(1)
            if session.attached {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { isExpanded.toggle() }
        .contextMenu {
            Button("Attach") { onAttach() }
            Divider()
            Button("Rename…") { onRename() }
            Divider()
            Button("Kill Session", role: .destructive) { onKill() }
        }
        .padding(.vertical, 2)
    }
}
```

- [ ] **Step 2: 创建 TmuxWindowRow.swift**

注意：expand/collapse 绑定在 chevron 按钮上，双击绑定在文字区域，两者互不干扰，避免 SwiftUI 单击/双击手势冲突。

```swift
// macos/Sources/Features/Tmux/TmuxWindowRow.swift
import SwiftUI

struct TmuxWindowRow: View {
    let window: TmuxWindow
    @Binding var isExpanded: Bool
    let onSwitch: () -> Void
    let onNewWindow: () -> Void
    let onRename: () -> Void
    let onKill: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            // Chevron 区域：单击 expand/collapse
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .frame(width: 12)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .onTapGesture { isExpanded.toggle() }

            // 文字区域：双击跳转（单击无操作）
            HStack(spacing: 4) {
                Text("\(window.windowIndex):")
                    .foregroundStyle(.secondary)
                    .font(.system(.caption, design: .monospaced))
                Text(window.name)
                    .lineLimit(1)
                    .fontWeight(window.active ? .semibold : .regular)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onSwitch() }
        }
        .contextMenu {
            Button("Switch To") { onSwitch() }
            Button("New Window") { onNewWindow() }
            Divider()
            Button("Rename…") { onRename() }
            Divider()
            Button("Kill Window", role: .destructive) { onKill() }
        }
        .padding(.vertical, 2)
    }
}
```

- [ ] **Step 3: 创建 TmuxPaneRow.swift**

```swift
// macos/Sources/Features/Tmux/TmuxPaneRow.swift
import SwiftUI

struct TmuxPaneRow: View {
    let pane: TmuxPane
    let onSelect: () -> Void
    let onSplitH: () -> Void
    let onSplitV: () -> Void
    let onKill: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("%\(pane.id)")
                .foregroundStyle(.secondary)
                .font(.system(.caption, design: .monospaced))
                .frame(minWidth: 28, alignment: .leading)
            Text(pane.title.isEmpty ? "—" : pane.title)
                .lineLimit(1)
                .fontWeight(pane.active ? .semibold : .regular)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .contextMenu {
            Button("Select Pane") { onSelect() }
            Button("Split Horizontal") { onSplitH() }
            Button("Split Vertical") { onSplitV() }
            Divider()
            Button("Kill Pane", role: .destructive) { onKill() }
        }
        .padding(.vertical, 2)
    }
}
```

- [ ] **Step 4: 注册三个文件到 Xcode project，编译通过**

- [ ] **Step 5: 提交**

```bash
git add macos/Sources/Features/Tmux/TmuxSessionRow.swift \
        macos/Sources/Features/Tmux/TmuxWindowRow.swift \
        macos/Sources/Features/Tmux/TmuxPaneRow.swift \
        macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "feat(tmux): add session/window/pane row views"
```

---

## Task 6: TmuxPanelView（面板根视图）

**Files:**
- Create: `macos/Sources/Features/Tmux/TmuxPanelView.swift`

- [ ] **Step 1: 创建 TmuxPanelView.swift**

```swift
// macos/Sources/Features/Tmux/TmuxPanelView.swift
import SwiftUI

struct TmuxPanelView: View {
    @ObservedObject var viewModel: TmuxPanelViewModel

    // 展开/折叠状态（session id → Bool，window id → Bool）
    @State private var expandedSessions: Set<String> = []
    @State private var expandedWindows: Set<String> = []

    // Rename sheet
    @State private var renameTarget: RenameTarget? = nil
    @State private var renameText: String = ""

    // New session sheet
    @State private var showNewSessionSheet = false
    @State private var newSessionName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Banner
            if let msg = viewModel.bannerMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange)
            }

            // Header
            HStack {
                Text("tmux")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    viewModel.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("刷新")

                Button {
                    newSessionName = ""
                    showNewSessionSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("新建 Session")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            // Content
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    contentView
                }
                .padding(.vertical, 4)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showNewSessionSheet) {
            newSessionSheet
        }
        .sheet(item: $renameTarget) { target in
            renameSheet(target: target)
        }
        .onAppear { viewModel.resume() }
        .onDisappear { viewModel.pause() }
    }

    // MARK: - Content States

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 20)

        case .empty:
            VStack(spacing: 8) {
                Image(systemName: "terminal")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text("无活跃 Session")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 20)

        case .error(let err):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text(errorMessage(err))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 20)
            .padding(.horizontal, 8)

        case .loaded(let sessions):
            ForEach(sessions) { session in
                sessionSection(session)
            }
        }
    }

    // MARK: - Session Tree

    private func sessionSection(_ session: TmuxSession) -> some View {
        let isExpanded = expandedSessions.contains(session.id)
        return Group {
            TmuxSessionRow(
                session: session,
                isExpanded: Binding(
                    get: { expandedSessions.contains(session.id) },
                    set: { if $0 { expandedSessions.insert(session.id) } else { expandedSessions.remove(session.id) } }
                ),
                onAttach: { Task { await viewModel.attachSession(session.id) } },
                onRename: { renameTarget = .session(session.id); renameText = session.id },
                onKill: { Task { await viewModel.killSession(session.id) } }
            )
            .padding(.leading, 6)

            if isExpanded {
                ForEach(session.windows) { window in
                    windowSection(window, sessionName: session.id)
                        .padding(.leading, 16)
                }
            }
        }
    }

    private func windowSection(_ window: TmuxWindow, sessionName: String) -> some View {
        Group {
            TmuxWindowRow(
                window: window,
                isExpanded: Binding(
                    get: { expandedWindows.contains(window.id) },
                    set: { if $0 { expandedWindows.insert(window.id) } else { expandedWindows.remove(window.id) } }
                ),
                onSwitch: { Task { await viewModel.switchToWindow(sessionName: sessionName, windowIndex: window.windowIndex) } },
                onNewWindow: { Task { await viewModel.newWindow(sessionName: sessionName) } },
                onRename: { renameTarget = .window(sessionName, window.windowIndex, window.name); renameText = window.name },
                onKill: { Task { await viewModel.killWindow(sessionName: sessionName, windowIndex: window.windowIndex) } }
            )

            if expandedWindows.contains(window.id) {
                ForEach(window.panes) { pane in
                    TmuxPaneRow(
                        pane: pane,
                        onSelect: { Task { await viewModel.selectPane(paneId: pane.id) } },
                        onSplitH: { Task { await viewModel.splitPane(paneId: pane.id, horizontal: true) } },
                        onSplitV: { Task { await viewModel.splitPane(paneId: pane.id, horizontal: false) } },
                        onKill: { Task { await viewModel.killPane(paneId: pane.id) } }
                    )
                    .padding(.leading, 16)
                }
            }
        }
    }

    // MARK: - Sheets

    private var newSessionSheet: some View {
        VStack(spacing: 16) {
            Text("新建 tmux Session")
                .font(.headline)
            TextField("Session 名称", text: $newSessionName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
            HStack {
                Button("取消") { showNewSessionSheet = false }
                Button("创建") {
                    showNewSessionSheet = false
                    Task { await viewModel.newSession(name: newSessionName) }
                }
                .disabled(newSessionName.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
    }

    private func renameSheet(target: RenameTarget) -> some View {
        VStack(spacing: 16) {
            Text("重命名")
                .font(.headline)
            TextField("新名称", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
            HStack {
                Button("取消") { renameTarget = nil }
                Button("确认") {
                    let text = renameText
                    renameTarget = nil
                    Task {
                        switch target {
                        case .session(let old):
                            await viewModel.renameSession(old: old, new: text)
                        case .window(let s, let idx, _):
                            await viewModel.renameWindow(sessionName: s, windowIndex: idx, newName: text)
                        }
                    }
                }
                .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
    }

    // MARK: - Helpers

    private func errorMessage(_ error: TmuxError) -> String {
        switch error {
        case .notInstalled:
            return "未找到 tmux\n请通过 Homebrew 安装：brew install tmux"
        case .serverNotRunning:
            return "tmux server 未运行\n在终端中启动 tmux 后刷新"
        case .timeout:
            return "连接 tmux 超时\n请稍后刷新"
        }
    }
}

// MARK: - RenameTarget

private enum RenameTarget: Identifiable {
    case session(String)
    case window(String, Int, String)  // sessionName, windowIndex, currentName

    var id: String {
        switch self {
        case .session(let name): return "s:\(name)"
        case .window(let s, let i, _): return "w:\(s):\(i)"
        }
    }
}
```

- [ ] **Step 2: 注册到 Xcode project，编译通过**

```bash
xcodebuild build -project macos/Ghostty.xcodeproj \
  -scheme Ghostty -destination 'platform=macOS' 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Step 3: 提交**

```bash
git add macos/Sources/Features/Tmux/TmuxPanelView.swift \
        macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "feat(tmux): add TmuxPanelView with tree UI and state views"
```

---

## Task 7: 接入 PolterttyRootView

**Files:**
- Modify: `macos/Sources/Features/Workspace/PolterttyRootView.swift`

- [ ] **Step 1: 在 Notification.Name 扩展末尾追加 toggle 通知名**

在 `PolterttyRootView.swift` 开头的 `extension Notification.Name` 块中追加：

```swift
static let toggleTmuxPanel = Notification.Name("poltertty.toggleTmuxPanel")
```

- [ ] **Step 2: 在 PolterttyRootView struct 中新增属性**

在 `@ObservedObject private var agentMonitorVM: AgentMonitorViewModel` 下方追加：

```swift
@ObservedObject private var tmuxPanelVM: TmuxPanelViewModel
@State private var tmuxDividerHovered = false
```

- [ ] **Step 3: 在 init() 中初始化 tmuxPanelVM**

在 `init()` 末尾（`agentMonitorVM` 初始化之后）追加：

```swift
self._tmuxPanelVM = ObservedObject(wrappedValue: TmuxPanelViewModel())
```

- [ ] **Step 4: 在 HStack 布局中插入 tmux 面板分支**

`PolterttyRootView.swift` 约第 171–220 行有如下布局结构（需在**两处** `terminalAreaView` 之前插入，全屏分支不插入）：

```swift
// 当前代码（需要修改）
if fileBrowserVM.isVisible {
    if fileBrowserVM.isPreviewFullscreen {
        FileBrowserPanel(...)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        // ← 全屏分支：不插入 tmux 面板（fileBrowser 独占全部空间）
    } else {
        FileBrowserPanel(...)
            .frame(...)
        fileBrowserDivider
        terminalAreaView        // ← 插入点 A
    }
} else {
    terminalAreaView            // ← 插入点 B
}
```

将**插入点 A 和 B** 的 `terminalAreaView` 替换为：

```swift
// tmux Panel（插入点 A 和 B 相同的替换片段）
if tmuxPanelVM.isVisible {
    TmuxPanelView(viewModel: tmuxPanelVM)
        .frame(width: tmuxPanelVM.panelWidth)
    tmuxDividerView
}
terminalAreaView
```

修改后结构（示例，仅展示关键行）：

```swift
if fileBrowserVM.isVisible {
    if fileBrowserVM.isPreviewFullscreen {
        FileBrowserPanel(...).frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
        FileBrowserPanel(...).frame(...)
        fileBrowserDivider
        if tmuxPanelVM.isVisible {          // 插入点 A
            TmuxPanelView(viewModel: tmuxPanelVM).frame(width: tmuxPanelVM.panelWidth)
            tmuxDividerView
        }
        terminalAreaView
    }
} else {
    if tmuxPanelVM.isVisible {              // 插入点 B
        TmuxPanelView(viewModel: tmuxPanelVM).frame(width: tmuxPanelVM.panelWidth)
        tmuxDividerView
    }
    terminalAreaView
}
```

- [ ] **Step 5: 添加 tmuxDividerView computed property**

参照 `fileBrowserDivider`（约第 360 行）的实现，在 `PolterttyRootView` 的 `fileBrowserDivider` 属性之后添加：

```swift
private var tmuxDividerView: some View {
    ZStack {
        Color(nsColor: .separatorColor)
            .frame(width: 1)
        if tmuxDividerHovered {
            DividerGripHandle()
        }
    }
    .frame(width: 16)
    .contentShape(Rectangle())
    .onHover { hovering in
        tmuxDividerHovered = hovering
        if hovering { NSCursor.resizeLeftRight.push() }
        else { NSCursor.pop() }
    }
    .gesture(
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let newWidth = tmuxPanelVM.panelWidth + value.translation.width
                tmuxPanelVM.panelWidth = max(160, min(500, newWidth))
            }
    )
}
```

注意：`DividerGripHandle` 是项目中已有的组件（与 `fileBrowserDivider` 共用），无需新建。

- [ ] **Step 6: 注册 toggle 通知**

在现有 `onReceive(NotificationCenter.default.publisher(for: .toggleFileBrowser))` 附近追加：

```swift
.onReceive(NotificationCenter.default.publisher(for: .toggleTmuxPanel)) { _ in
    tmuxPanelVM.isVisible.toggle()
    if tmuxPanelVM.isVisible { tmuxPanelVM.resume() } else { tmuxPanelVM.pause() }
}
```

- [ ] **Step 7: 编译确认无报错**

```bash
xcodebuild build -project macos/Ghostty.xcodeproj \
  -scheme Ghostty -destination 'platform=macOS' 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Step 8: 提交**

```bash
git add macos/Sources/Features/Workspace/PolterttyRootView.swift
git commit -m "feat(tmux): integrate TmuxPanelView into PolterttyRootView"
```

---

## Task 8: AppDelegate 菜单项（必须完成，否则面板无触发入口）

**Files:**
- Modify: `macos/Sources/App/macOS/AppDelegate.swift`

- [ ] **Step 1: 在 `setupMenus()` 中的 Workspace 菜单里追加 tmux panel 菜单项**

找到 `AppDelegate.swift` 约第 1113 行（`toggleFileBrowser` 菜单项之后）：

```swift
// 现有代码
let toggleFileBrowser = NSMenuItem(title: "Toggle File Browser", action: #selector(toggleFileBrowser(_:)), keyEquivalent: "\\")
toggleFileBrowser.keyEquivalentModifierMask = .command
workspaceMenu.addItem(toggleFileBrowser)
```

在其**之后**追加：

```swift
let toggleTmuxPanel = NSMenuItem(title: "Toggle tmux Panel", action: #selector(toggleTmuxPanel(_:)), keyEquivalent: "x")
toggleTmuxPanel.keyEquivalentModifierMask = [.command, .shift]
workspaceMenu.addItem(toggleTmuxPanel)
```

- [ ] **Step 2: 添加 `@objc func toggleTmuxPanel`**

在 `toggleFileBrowser(_:)` 方法（约第 1148 行）之后追加：

```swift
@objc func toggleTmuxPanel(_ sender: Any?) {
    NotificationCenter.default.post(name: .toggleTmuxPanel, object: nil)
}
```

- [ ] **Step 3: 编译确认**

```bash
xcodebuild build -project macos/Ghostty.xcodeproj \
  -scheme Ghostty -destination 'platform=macOS' 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Step 4: 提交**

```bash
git add macos/Sources/App/macOS/AppDelegate.swift
git commit -m "feat(tmux): add tmux panel menu item (Cmd+Shift+X)"
```

---

## 验证

- [ ] 启动 Poltertty，确认 tmux 面板可通过通知或按钮显示/隐藏
- [ ] 有 tmux server 时：面板显示 sessions/windows/panes 树，2 秒自动刷新
- [ ] 无 tmux server 时：显示"tmux server 未运行"错误状态
- [ ] 操作（新建/重命名/kill/分屏）后面板立即刷新
- [ ] 双击 window 无 client 时显示 banner，4 秒后消失
- [ ] 面板宽度可拖拽调整
