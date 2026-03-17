# Bottom Status Bar Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Poltertty 终端窗口底部添加状态栏，显示当前工作目录路径和 git 分支及脏状态计数。

**Architecture:** 新增 `GitStatusMonitor`（ObservableObject，DispatchSource 监听 `.git/HEAD` + `.git/index`，私有串行 queue 防竞态）和 `BottomStatusBarView`（SwiftUI，通过 `.safeAreaInset` 挂载到 `.terminal` case HStack），在 `TerminalController` 创建 monitor 并传入 `PolterttyRootView`。

**Tech Stack:** Swift 5.9, SwiftUI, macOS 13+, DispatchSource, Swift Testing (`import Testing`)

---

## 文件清单

| 操作 | 文件 |
|------|------|
| 新增 | `macos/Sources/Features/Workspace/GitStatusMonitor.swift` |
| 新增 | `macos/Sources/Features/Workspace/BottomStatusBarView.swift` |
| 新增 | `macos/Tests/Workspace/GitStatusMonitorTests.swift` |
| 修改 | `macos/Sources/Features/Workspace/PolterttyRootView.swift` |
| 修改 | `macos/Sources/Features/Terminal/TerminalController.swift` |

---

## Task 1: GitStatus 数据模型 + porcelain 解析

**Files:**
- Create: `macos/Sources/Features/Workspace/GitStatusMonitor.swift`（仅 struct + 解析函数，暂不含 monitor 逻辑）
- Create: `macos/Tests/Workspace/GitStatusMonitorTests.swift`

- [ ] **Step 1: 创建测试目录**

```bash
mkdir -p /Users/oopslink/works/codes/oopslink/poltertty/.worktrees/feature-bottom-statusbar/macos/Tests/Workspace
```

- [ ] **Step 2: 创建测试文件**

路径：`macos/Tests/Workspace/GitStatusMonitorTests.swift`

```swift
import Testing
import Foundation
@testable import Ghostty

struct GitStatusMonitorTests {

    // MARK: - porcelain 解析

    @Test func testParseCleanRepo() {
        let result = GitStatusParser.parse(porcelain: "")
        #expect(result.added == 0)
        #expect(result.modified == 0)
    }

    @Test func testParseUntracked() {
        let result = GitStatusParser.parse(porcelain: "?? new-file.txt\n")
        #expect(result.added == 1)
        #expect(result.modified == 0)
    }

    @Test func testParseStagedNew() {
        let result = GitStatusParser.parse(porcelain: "A  staged-new.txt\n")
        #expect(result.added == 1)
        #expect(result.modified == 0)
    }

    @Test func testParseStagedModified() {
        let result = GitStatusParser.parse(porcelain: "M  staged.txt\n")
        #expect(result.modified == 1)
        #expect(result.added == 0)
    }

    @Test func testParseUnstagedModified() {
        let result = GitStatusParser.parse(porcelain: " M unstaged.txt\n")
        #expect(result.modified == 1)
        #expect(result.added == 0)
    }

    @Test func testParseMixed() {
        let porcelain = """
        ?? untracked.txt
        A  staged-new.txt
        M  staged-mod.txt
         M unstaged-mod.txt
        """
        let result = GitStatusParser.parse(porcelain: porcelain)
        #expect(result.added == 2)    // ?? + A
        #expect(result.modified == 2) // M(index) + M(worktree)
    }

    @Test func testParseRenamedNotCountedAsAdded() {
        // R 不计入 added（有意设计，只统计严格 A 状态）
        let result = GitStatusParser.parse(porcelain: "R  old.txt -> new.txt\n")
        #expect(result.added == 0)
        #expect(result.modified == 0)
    }

    @Test func testParseShortLineTooShortIsIgnored() {
        // 少于2字符的行不处理，不应崩溃
        let result = GitStatusParser.parse(porcelain: "?\n")
        #expect(result.added == 0)
        #expect(result.modified == 0)
    }

    // MARK: - GitStatus.empty

    @Test func testGitStatusEmpty() {
        let s = GitStatus.empty
        #expect(s.isGitRepo == false)
        #expect(s.branch == nil)
        #expect(s.added == 0)
        #expect(s.modified == 0)
    }

    // MARK: - updatePwd 空路径不重置状态

    @Test func testUpdatePwdEmptyDoesNotReset() async throws {
        let monitor = GitStatusMonitor(pwd: NSHomeDirectory())
        // 等待初始化完成
        try await Task.sleep(nanoseconds: 200_000_000)
        let statusBefore = monitor.status
        monitor.updatePwd("")
        try await Task.sleep(nanoseconds: 200_000_000)
        // 状态应保持不变
        #expect(monitor.status == statusBefore)
    }
}
```

- [ ] **Step 3: 运行测试（确认失败）**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty/.worktrees/feature-bottom-statusbar/macos && \
  xcodebuild test \
    -scheme Ghostty \
    -destination 'platform=macOS' \
    -only-testing GhosttyTests/GitStatusMonitorTests \
    2>&1 | tail -20
```

期待：`error: cannot find type 'GitStatusParser'`

- [ ] **Step 4: 创建 GitStatus struct + GitStatusParser**

路径：`macos/Sources/Features/Workspace/GitStatusMonitor.swift`

```swift
// macos/Sources/Features/Workspace/GitStatusMonitor.swift

import Foundation

// MARK: - Data Model

struct GitStatus: Equatable {
    let branch: String?   // nil = detached HEAD
    let added: Int        // untracked (??) + staged new (A)
    let modified: Int     // staged modified (M?) + unstaged modified (?M)
    let isGitRepo: Bool

    static let empty = GitStatus(branch: nil, added: 0, modified: 0, isGitRepo: false)
}

// MARK: - Porcelain Parser

enum GitStatusParser {
    /// `git status --porcelain` 输出解析
    /// 每行前两字符为 XY 状态码：chars[0] = index列，chars[1] = worktree列
    static func parse(porcelain: String) -> (added: Int, modified: Int) {
        var added = 0
        var modified = 0
        for line in porcelain.components(separatedBy: "\n") {
            guard line.count >= 2 else { continue }
            let chars = Array(line)
            let x = chars[0]
            let y = chars[1]
            if x == "?" && y == "?" {
                added += 1          // untracked
            } else if x == "A" {
                added += 1          // staged new（不含 R/C，有意设计）
            }
            if x == "M" || y == "M" {
                modified += 1       // staged 或 unstaged modified
            }
        }
        return (added: added, modified: modified)
    }
}
```

- [ ] **Step 5: 运行测试（确认通过，updatePwd 测试会 fail，下一 Task 修复）**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty/.worktrees/feature-bottom-statusbar/macos && \
  xcodebuild test \
    -scheme Ghostty \
    -destination 'platform=macOS' \
    -only-testing GhosttyTests/GitStatusMonitorTests \
    2>&1 | tail -20
```

期待：解析器相关测试通过，`testUpdatePwdEmptyDoesNotReset` 因 `GitStatusMonitor` 未实现而失败

- [ ] **Step 6: 提交**

```bash
git -C /Users/oopslink/works/codes/oopslink/poltertty/.worktrees/feature-bottom-statusbar \
  add macos/Sources/Features/Workspace/GitStatusMonitor.swift \
      macos/Tests/Workspace/GitStatusMonitorTests.swift
git -C /Users/oopslink/works/codes/oopslink/poltertty/.worktrees/feature-bottom-statusbar \
  commit -m "feat(statusbar): add GitStatus model and porcelain parser with tests"
```

---

## Task 2: GitStatusMonitor（监听逻辑）

**Files:**
- Modify: `macos/Sources/Features/Workspace/GitStatusMonitor.swift`（在文件末尾追加 monitor 类）

- [ ] **Step 1: 追加 GitStatusMonitor 类**

在 `GitStatusMonitor.swift` 的 `GitStatusParser` 之后追加：

```swift
// MARK: - Monitor

final class GitStatusMonitor: ObservableObject {
    @Published var status: GitStatus = .empty

    private let queue = DispatchQueue(label: "poltertty.git-status-monitor")
    private var currentPwd: String
    private var gitRoot: String?
    private var headSource: DispatchSourceFileSystemObject?
    private var indexSource: DispatchSourceFileSystemObject?
    private var debounceWork: DispatchWorkItem?

    init(pwd: String) {
        self.currentPwd = pwd
        queue.async { [weak self] in
            self?.detectAndSetup(pwd: pwd)
        }
    }

    func updatePwd(_ path: String) {
        guard !path.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.stopWatching()
            self.currentPwd = path
            self.detectAndSetup(pwd: path)
        }
    }

    deinit {
        // deinit 可能在任意线程调用，直接 cancel source（不走串行 queue）
        headSource?.cancel()
        indexSource?.cancel()
        debounceWork?.cancel()
    }

    // MARK: - Private

    private func detectAndSetup(pwd: String) {
        let result = runGit(["-C", pwd, "rev-parse", "--show-toplevel"])
        guard result.exitCode == 0,
              let root = result.output?.trimmingCharacters(in: .whitespacesAndNewlines),
              !root.isEmpty else {
            DispatchQueue.main.async { [weak self] in
                self?.status = .empty
            }
            return
        }
        gitRoot = root
        setupWatching(gitRoot: root)
        refresh()
    }

    private func setupWatching(gitRoot: String) {
        startSource(path: "\(gitRoot)/.git/HEAD", store: &headSource)
        startSource(path: "\(gitRoot)/.git/index", store: &indexSource)
    }

    private func startSource(path: String, store: inout DispatchSourceFileSystemObject?) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("[GitStatusMonitor] open failed for \(path): errno=\(errno)")
            return
        }
        // queue: 参数直接指定目标队列（等效于 setTarget(queue:)）
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.scheduleRefresh()
        }
        source.setCancelHandler {
            close(fd)
        }
        store = source
        source.resume()
    }

    private func scheduleRefresh() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refresh()
        }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func refresh() {
        let pwd = gitRoot ?? currentPwd
        guard !pwd.isEmpty else { return }

        let branchResult = runGit(["-C", pwd, "branch", "--show-current"])
        let branchOutput = branchResult.output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let branch: String? = branchOutput.isEmpty ? nil : branchOutput

        let statusResult = runGit(["-C", pwd, "status", "--porcelain"])
        let porcelain = statusResult.output ?? ""
        let counts = GitStatusParser.parse(porcelain: porcelain)

        let newStatus = GitStatus(
            branch: branch,
            added: counts.added,
            modified: counts.modified,
            isGitRepo: true
        )
        DispatchQueue.main.async { [weak self] in
            self?.status = newStatus
        }
    }

    private func stopWatching() {
        headSource?.cancel()
        headSource = nil
        indexSource?.cancel()
        indexSource = nil
        debounceWork?.cancel()
        debounceWork = nil
        gitRoot = nil
    }

    // MARK: - Subprocess

    private struct GitResult {
        let exitCode: Int32
        let output: String?
    }

    private func runGit(_ args: [String]) -> GitResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)
            return GitResult(exitCode: proc.terminationStatus, output: output)
        } catch {
            NSLog("[GitStatusMonitor] git error: \(error)")
            return GitResult(exitCode: -1, output: nil)
        }
    }
}
```

- [ ] **Step 2: 全テスト実行（全部通ることを确认）**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty/.worktrees/feature-bottom-statusbar/macos && \
  xcodebuild test \
    -scheme Ghostty \
    -destination 'platform=macOS' \
    -only-testing GhosttyTests/GitStatusMonitorTests \
    2>&1 | tail -20
```

期待：`** TEST SUCCEEDED **`（全テスト通過）

- [ ] **Step 3: 提交**

```bash
git -C /Users/oopslink/works/codes/oopslink/poltertty/.worktrees/feature-bottom-statusbar \
  add macos/Sources/Features/Workspace/GitStatusMonitor.swift
git -C /Users/oopslink/works/codes/oopslink/poltertty/.worktrees/feature-bottom-statusbar \
  commit -m "feat(statusbar): add GitStatusMonitor with DispatchSource watching"
```

---

## Task 3: BottomStatusBarView

**Files:**
- Create: `macos/Sources/Features/Workspace/BottomStatusBarView.swift`

- [ ] **Step 1: 创建 BottomStatusBarView**

```swift
// macos/Sources/Features/Workspace/BottomStatusBarView.swift

import SwiftUI
import AppKit

struct BottomStatusBarView: View {
    @ObservedObject var monitor: GitStatusMonitor
    let pwd: String

    var body: some View {
        let status = monitor.status
        if !status.isGitRepo {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 6) {
                    // 左：当前目录路径
                    Label(abbreviatedPwd, systemImage: "folder")
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundColor(.secondary)
                    Spacer()
                    // 右：git 状态
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundColor(.secondary)
                        Text(status.branch ?? "detached")
                            .foregroundColor(.primary)
                        if status.added > 0 {
                            Text("+\(status.added)")
                                .foregroundColor(.green)
                        }
                        if status.modified > 0 {
                            Text("~\(status.modified)")
                                .foregroundColor(.yellow)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
            }
            .font(.system(size: 11))
        }
    }

    private var abbreviatedPwd: String {
        pwd.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
```

- [ ] **Step 2: 构建确认**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty/.worktrees/feature-bottom-statusbar && \
  make check 2>&1 | tail -10
```

期待：`** BUILD SUCCEEDED **`

- [ ] **Step 3: 提交**

```bash
git -C /Users/oopslink/works/codes/oopslink/poltertty/.worktrees/feature-bottom-statusbar \
  add macos/Sources/Features/Workspace/BottomStatusBarView.swift
git -C /Users/oopslink/works/codes/oopslink/poltertty/.worktrees/feature-bottom-statusbar \
  commit -m "feat(statusbar): add BottomStatusBarView"
```

---

## Task 4: PolterttyRootView 集成

**Files:**
- Modify: `macos/Sources/Features/Workspace/PolterttyRootView.swift`

变更 3 处：
1. stored properties + init 参数（新参数插入在 `onSwitchTab` 之前，因为 `onSwitchTab` 有默认值，Swift 不允许在默认参数后添加无默认值参数）
2. `@FocusedValue` 属性
3. `.terminal` case 的 `HStack` 末尾追加 `.safeAreaInset` + `.onChange`

- [ ] **Step 1: 在 onSwitchTab 之前添加 stored properties 和 init 参数**

在 `PolterttyRootView` 的 stored properties 中，`onSwitchTab` 属性声明之前添加：

```swift
let statusMonitor: GitStatusMonitor
let showStatusBar: Bool
```

在 `init` 参数列表中，`onSwitchTab: ((UUID) -> Void)? = nil` 之前添加：

```swift
statusMonitor: GitStatusMonitor,
showStatusBar: Bool,
```

在 `init` 本体中（`self.onSwitchTab = onSwitchTab` 附近）添加：

```swift
self.statusMonitor = statusMonitor
self.showStatusBar = showStatusBar
```

- [ ] **Step 2: 添加 @FocusedValue**

在现有 `@State private var quickSwitcherVisible = false` 附近添加：

```swift
@FocusedValue(\.ghosttySurfacePwd) private var focusedPwd
```

- [ ] **Step 3: 在 .terminal case 的 HStack 末尾添加 .safeAreaInset 和 .onChange**

找到 `.terminal` case 的 `HStack(spacing: 0) { ... }` 结束位置，追加：

```swift
.safeAreaInset(edge: .bottom, spacing: 0) {
    if showStatusBar {
        BottomStatusBarView(
            monitor: statusMonitor,
            pwd: focusedPwd ?? ""
        )
    }
}
.onChange(of: focusedPwd) { newPwd in
    // 单参数 closure，兼容 macOS 13+（项目最低支持版本）
    guard let pwd = newPwd, !pwd.isEmpty else { return }
    statusMonitor.updatePwd(pwd)
}
```

- [ ] **Step 4: 构建确认（会有 TerminalController 调用侧未更新的错误）**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty/.worktrees/feature-bottom-statusbar && \
  make check 2>&1 | grep -E "error:|BUILD"
```

期待：`TerminalController.swift` 处有 `missing argument` 编译错误，其余文件无错误

---

## Task 5: TerminalController 集成（与 Task 4 连续，不单独提交直到构建通过）

**Files:**
- Modify: `macos/Sources/Features/Terminal/TerminalController.swift`

- [ ] **Step 1: 添加 statusMonitor 属性**

在 `let tabBarViewModel = TabBarViewModel()`（L67 付近）的近旁添加：

```swift
let statusMonitor: GitStatusMonitor
```

- [ ] **Step 2: 在 init 中初始化 statusMonitor**

在 `self.workspaceId = workspaceId`（L80）之后、`super.init(...)` 之前添加：

```swift
let rootDir = workspaceId
    .flatMap { WorkspaceManager.shared.workspace(for: $0) }?.rootDirExpanded
    ?? NSHomeDirectory()
self.statusMonitor = GitStatusMonitor(pwd: rootDir)
```

- [ ] **Step 3: 在 windowDidLoad の PolterttyRootView 呼び出しに追加**

`PolterttyRootView(...)` 呼び出し（L1258-L1295）内の `onSwitchTab:` の直前に追加：

```swift
statusMonitor: self.statusMonitor,
showStatusBar: {
    guard let id = workspaceId,
          let ws = WorkspaceManager.shared.workspace(for: id) else { return false }
    return !ws.isTemporary
}(),
```

- [ ] **Step 4: 构建确认（必须通过）**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty/.worktrees/feature-bottom-statusbar && \
  make check 2>&1 | tail -10
```

期待：`** BUILD SUCCEEDED **`（无编译错误）

- [ ] **Step 5: 全テスト実行**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty/.worktrees/feature-bottom-statusbar/macos && \
  xcodebuild test \
    -scheme Ghostty \
    -destination 'platform=macOS' \
    -only-testing GhosttyTests/GitStatusMonitorTests \
    2>&1 | tail -10
```

期待：`** TEST SUCCEEDED **`

- [ ] **Step 6: Tasks 4+5 をまとめてコミット**

```bash
git -C /Users/oopslink/works/codes/oopslink/poltertty/.worktrees/feature-bottom-statusbar \
  add macos/Sources/Features/Workspace/PolterttyRootView.swift \
      macos/Sources/Features/Terminal/TerminalController.swift
git -C /Users/oopslink/works/codes/oopslink/poltertty/.worktrees/feature-bottom-statusbar \
  commit -m "feat(statusbar): integrate status bar into PolterttyRootView and TerminalController"
```

---

## Task 6: 手動動作確認

- [ ] **Step 1: 开发版构建并启动**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty/.worktrees/feature-bottom-statusbar && \
  make run-dev
```

- [ ] **Step 2: 动作确认清单**

| 场景 | 期待行为 |
|------|----------|
| 打开 git repo 下的正式 workspace | 状态栏显示（左: `~/.../path`，右: `⎇ branch-name`） |
| 终端中执行 `cd` | 左侧路径更新 |
| `git checkout other-branch` | 右侧分支名更新 |
| `touch newfile && git add newfile` | 显示 `+1` |
| `echo x >> existing.txt` | 显示 `~1` |
| `git clean -fd && git checkout .` | `+N ~M` 消失 |
| `cd` 到 git repo 外目录 | 整个状态栏消失（EmptyView） |
| 再 `cd` 回 git repo | 状态栏重新出现 |
| 打开临时 workspace（Temporary） | 状态栏不显示 |
| 无 workspace 的普通 Ghostty 窗口 | 状态栏不显示 |

---

## 完了後の手順

全 Task 完了・手动确认后，使用 `superpowers:finishing-a-development-branch` skill 创建 PR。
