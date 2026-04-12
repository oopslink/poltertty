# Workspace Git Clone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 New Workspace 表单中新增 "From Git" 创建模式，允许通过 `git clone` URL 直接拉取仓库并创建对应 workspace。

**Architecture:** 新增 `GitCloner` 纯逻辑模块封装 `/usr/bin/git clone` 子进程；将 `WorkspaceCreateForm` 中的 `createFromSnapshot` Toggle 重构为三段 `WorkspaceCreateSource` Picker（empty / snapshot / git）；clone 在表单内同步执行，成功后由现有 `onSubmit` 回调走老的 `WorkspaceManager.create` 路径。`WorkspaceManager` 不改动。

**Tech Stack:** Swift 5.9, SwiftUI, Foundation `Process`, Swift Testing (`@Test` / `#expect`)

**Spec:** `docs/superpowers/specs/2026-04-12-workspace-git-clone-design.md`

---

## 文件变更清单

| 操作 | 文件 |
|------|------|
| 新建 | `macos/Sources/Features/Workspace/GitCloner.swift` |
| 新建 | `macos/Tests/Workspace/GitClonerTests.swift` |
| 修改 | `macos/Sources/Features/Workspace/WorkspaceCreateForm.swift` |

`WorkspaceManager.swift` 与 `WorkspaceSidebar.swift` / `OnboardingView.swift` 等调用方**不修改**，因为表单的 `onSubmit` 签名保持不变。

---

## Task 1: GitCloner — extractRepoName 静态方法 + 测试

**Files:**
- Create: `macos/Sources/Features/Workspace/GitCloner.swift`
- Create: `macos/Tests/Workspace/GitClonerTests.swift`

- [ ] **Step 1: 写第一个失败测试**

`macos/Tests/Workspace/GitClonerTests.swift`:

```swift
// macos/Tests/Workspace/GitClonerTests.swift
import Testing
import Foundation
@testable import Ghostty

struct GitClonerTests {

    // MARK: - extractRepoName

    @Test func extractsRepoNameFromHttpsWithDotGit() {
        #expect(GitCloner.extractRepoName(from: "https://github.com/foo/bar.git") == "bar")
    }

    @Test func extractsRepoNameFromHttpsWithoutDotGit() {
        #expect(GitCloner.extractRepoName(from: "https://github.com/foo/bar") == "bar")
    }

    @Test func extractsRepoNameFromScpStyleSsh() {
        #expect(GitCloner.extractRepoName(from: "git@github.com:foo/bar.git") == "bar")
    }

    @Test func extractsRepoNameFromSshUrl() {
        #expect(GitCloner.extractRepoName(from: "ssh://git@host:22/foo/bar.git") == "bar")
    }

    @Test func extractsRepoNameWithTrailingSlash() {
        #expect(GitCloner.extractRepoName(from: "https://host/foo/bar/") == "bar")
    }

    @Test func extractsRepoNameWithMultipleDotGitSegments() {
        #expect(GitCloner.extractRepoName(from: "https://host/foo/bar.git/") == "bar")
    }

    @Test func returnsNilForEmpty() {
        #expect(GitCloner.extractRepoName(from: "") == nil)
    }

    @Test func returnsNilForWhitespace() {
        #expect(GitCloner.extractRepoName(from: "   ") == nil)
    }
}
```

- [ ] **Step 2: 编译应失败（缺少 `GitCloner`）**

Run: `make check`
Expected: 错误形如 `Cannot find 'GitCloner' in scope`。

- [ ] **Step 3: 创建最小 GitCloner**

`macos/Sources/Features/Workspace/GitCloner.swift`:

```swift
// macos/Sources/Features/Workspace/GitCloner.swift
import Foundation

final class GitCloner {

    // MARK: - Repo name extraction

    /// 从 git URL 中提取仓库名（去掉 .git 后缀和尾部斜杠）。
    /// 支持 https://, git@host:path, ssh://, 以及尾部带 / 的形式。
    /// - Returns: 仓库名；输入为空、空白或无法解析时返回 nil。
    static func extractRepoName(from url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 去掉尾部所有 / 与 .git
        var s = trimmed
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix(".git") { s.removeLast(4) }
        while s.hasSuffix("/") { s.removeLast() }

        // 取最后一个 / 或 : 之后的部分
        let lastSlash = s.lastIndex(of: "/")
        let lastColon = s.lastIndex(of: ":")
        let cutIndex: String.Index?
        switch (lastSlash, lastColon) {
        case let (l?, c?): cutIndex = l > c ? l : c
        case let (l?, nil): cutIndex = l
        case let (nil, c?): cutIndex = c
        case (nil, nil): cutIndex = nil
        }

        let name: String
        if let idx = cutIndex {
            name = String(s[s.index(after: idx)...])
        } else {
            name = s
        }

        return name.isEmpty ? nil : name
    }
}
```

- [ ] **Step 4: 跑测试，全部通过**

Run:
```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -destination 'platform=macOS' \
  -only-testing:GhosttyTests/GitClonerTests 2>&1 | tail -40
```
Expected: 所有 8 个 `extractRepoName*` 测试通过。

- [ ] **Step 5: 提交**

```bash
git add macos/Sources/Features/Workspace/GitCloner.swift macos/Tests/Workspace/GitClonerTests.swift
git commit -m "feat(workspace): add GitCloner.extractRepoName with tests"
```

---

## Task 2: GitCloner — Options / CloneError / 预检查

**Files:**
- Modify: `macos/Sources/Features/Workspace/GitCloner.swift`
- Modify: `macos/Tests/Workspace/GitClonerTests.swift`

- [ ] **Step 1: 写预检测试（追加到 GitClonerTests.swift）**

```swift
    // MARK: - Precheck

    private func makeTempDir(file: StaticString = #file, line: UInt = #line) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitClonerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func precheckFailsForEmptyURL() async throws {
        let parent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: parent) }
        let cloner = GitCloner()
        let err = await withCheckedContinuation { (cont: CheckedContinuation<GitCloner.CloneError?, Never>) in
            cloner.start(
                options: .init(url: "", parentDir: parent.path, branch: nil, shallow: false),
                onProgress: { _ in },
                onComplete: { result in
                    if case .failure(let e) = result { cont.resume(returning: e) }
                    else { cont.resume(returning: nil) }
                }
            )
        }
        if case .invalidURL = err { } else { Issue.record("expected .invalidURL, got \(String(describing: err))") }
    }

    @Test func precheckFailsForUnparseableURL() async throws {
        let parent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: parent) }
        let cloner = GitCloner()
        let err = await withCheckedContinuation { (cont: CheckedContinuation<GitCloner.CloneError?, Never>) in
            cloner.start(
                options: .init(url: "   ", parentDir: parent.path, branch: nil, shallow: false),
                onProgress: { _ in },
                onComplete: { result in
                    if case .failure(let e) = result { cont.resume(returning: e) }
                    else { cont.resume(returning: nil) }
                }
            )
        }
        if case .invalidURL = err { } else { Issue.record("expected .invalidURL, got \(String(describing: err))") }
    }

    @Test func precheckFailsWhenParentMissing() async throws {
        let cloner = GitCloner()
        let err = await withCheckedContinuation { (cont: CheckedContinuation<GitCloner.CloneError?, Never>) in
            cloner.start(
                options: .init(
                    url: "https://example.com/foo/bar.git",
                    parentDir: "/definitely/does/not/exist/\(UUID().uuidString)",
                    branch: nil,
                    shallow: false
                ),
                onProgress: { _ in },
                onComplete: { result in
                    if case .failure(let e) = result { cont.resume(returning: e) }
                    else { cont.resume(returning: nil) }
                }
            )
        }
        if case .parentNotWritable = err { } else { Issue.record("expected .parentNotWritable, got \(String(describing: err))") }
    }

    @Test func precheckFailsWhenTargetExists() async throws {
        let parent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: parent) }
        let target = parent.appendingPathComponent("bar")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let cloner = GitCloner()
        let err = await withCheckedContinuation { (cont: CheckedContinuation<GitCloner.CloneError?, Never>) in
            cloner.start(
                options: .init(
                    url: "https://example.com/foo/bar.git",
                    parentDir: parent.path,
                    branch: nil,
                    shallow: false
                ),
                onProgress: { _ in },
                onComplete: { result in
                    if case .failure(let e) = result { cont.resume(returning: e) }
                    else { cont.resume(returning: nil) }
                }
            )
        }
        if case .targetExists = err { } else { Issue.record("expected .targetExists, got \(String(describing: err))") }
    }
```

- [ ] **Step 2: 跑测试，应失败（缺少 Options/CloneError/start）**

Run:
```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -destination 'platform=macOS' \
  -only-testing:GhosttyTests/GitClonerTests 2>&1 | tail -40
```
Expected: 编译错误，找不到 `GitCloner.Options` / `CloneError` / `start`。

- [ ] **Step 3: 在 GitCloner.swift 内补 Options/CloneError/start（仅预检分支）**

在 `GitCloner` 类内（`extractRepoName` 之后）追加：

```swift
    // MARK: - Types

    enum CloneError: LocalizedError {
        case invalidURL
        case parentNotWritable(path: String)
        case targetExists(path: String)
        case gitFailed(exitCode: Int32, stderr: String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid or empty Git URL"
            case .parentNotWritable(let p):
                return "Parent directory is not writable: \(p)"
            case .targetExists(let p):
                return "Target already exists: \(p)"
            case .gitFailed(_, let stderr):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "git clone failed" : trimmed
            case .cancelled:
                return "Clone cancelled"
            }
        }
    }

    struct Options {
        let url: String
        let parentDir: String   // 已展开 ~ 的绝对路径
        let branch: String?     // nil = 默认分支
        let shallow: Bool       // true = --depth 1
    }

    // MARK: - State

    private var process: Process?
    private var targetPath: String?
    private(set) var isRunning: Bool = false

    // MARK: - Start

    /// 启动 clone。回调统一在主线程触发。
    /// 预检失败会同步调用 onComplete(.failure(...))。
    func start(
        options: Options,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, CloneError>) -> Void
    ) {
        // 预检 1：URL 有效
        let trimmedURL = options.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty,
              let repoName = Self.extractRepoName(from: trimmedURL) else {
            DispatchQueue.main.async { onComplete(.failure(.invalidURL)) }
            return
        }

        // 预检 2：父目录存在且可写
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: options.parentDir, isDirectory: &isDir),
              isDir.boolValue,
              fm.isWritableFile(atPath: options.parentDir) else {
            DispatchQueue.main.async { onComplete(.failure(.parentNotWritable(path: options.parentDir))) }
            return
        }

        // 预检 3：目标子目录不存在
        let target = (options.parentDir as NSString).appendingPathComponent(repoName)
        if fm.fileExists(atPath: target) {
            DispatchQueue.main.async { onComplete(.failure(.targetExists(path: target))) }
            return
        }

        // 预检通过 — 后续 task 会接上子进程逻辑
        self.targetPath = target
        DispatchQueue.main.async {
            onComplete(.failure(.gitFailed(exitCode: -1, stderr: "subprocess not implemented yet")))
        }
        _ = onProgress // 显式标注已捕获，避免后续添加时遗漏
    }
```

注意：第 4 个预检测试（`targetExists`）因为目标存在会被预检拦下，**永远不会**真正调用 git，因此可以安全使用 `https://example.com/foo/bar.git` 作为占位 URL。

- [ ] **Step 4: 跑测试**

Run: 同 Step 2 命令。
Expected: 4 个预检测试通过（`precheckFailsForEmptyURL`、`precheckFailsForUnparseableURL`、`precheckFailsWhenParentMissing`、`precheckFailsWhenTargetExists`），加上 Task 1 的 8 个 extract 测试，共 12 个通过。

- [ ] **Step 5: 提交**

```bash
git add macos/Sources/Features/Workspace/GitCloner.swift macos/Tests/Workspace/GitClonerTests.swift
git commit -m "feat(workspace): add GitCloner precheck logic"
```

---

## Task 3: GitCloner — 子进程执行 + 成功/失败路径

**Files:**
- Modify: `macos/Sources/Features/Workspace/GitCloner.swift`
- Modify: `macos/Tests/Workspace/GitClonerTests.swift`

- [ ] **Step 1: 写一个真正调用 git 的成功测试（用本地 bare repo）**

追加到 `GitClonerTests.swift`（放在文件末尾，结构体内）：

```swift
    // MARK: - Real git subprocess

    /// 创建一个本地 bare repo 作为 clone 源。返回 (sourceURL, cleanup)。
    private func makeBareSourceRepo() throws -> (path: String, cleanup: () -> Void) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitClonerSrc-\(UUID().uuidString)")
        let work = root.appendingPathComponent("work")
        let bare = root.appendingPathComponent("bare.git")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        func runGit(_ args: [String], cwd: URL? = nil) throws {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = args
            if let cwd { p.currentDirectoryURL = cwd }
            p.environment = [
                "HOME": NSHomeDirectory(),
                "GIT_AUTHOR_NAME": "test",
                "GIT_AUTHOR_EMAIL": "test@test",
                "GIT_COMMITTER_NAME": "test",
                "GIT_COMMITTER_EMAIL": "test@test",
            ]
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus != 0 {
                throw NSError(domain: "git", code: Int(p.terminationStatus))
            }
        }

        try runGit(["init", "-q", "-b", "main", work.path])
        let readme = work.appendingPathComponent("README.md")
        try "hello".write(to: readme, atomically: true, encoding: .utf8)
        try runGit(["add", "."], cwd: work)
        try runGit(["commit", "-q", "-m", "init"], cwd: work)
        try runGit(["clone", "-q", "--bare", work.path, bare.path])

        return (bare.path, { try? FileManager.default.removeItem(at: root) })
    }

    @Test func clonesLocalBareRepoSuccessfully() async throws {
        let parent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: parent) }
        let src = try makeBareSourceRepo()
        defer { src.cleanup() }

        // 改名让 extractRepoName 拿到一个稳定名 "bare"
        let cloner = GitCloner()
        let result = await withCheckedContinuation { (cont: CheckedContinuation<Result<String, GitCloner.CloneError>, Never>) in
            cloner.start(
                options: .init(url: src.path, parentDir: parent.path, branch: nil, shallow: false),
                onProgress: { _ in },
                onComplete: { cont.resume(returning: $0) }
            )
        }

        switch result {
        case .success(let path):
            #expect(path == (parent.path as NSString).appendingPathComponent("bare"))
            #expect(FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(".git")))
        case .failure(let e):
            Issue.record("expected success, got \(e)")
        }
    }

    @Test func cleansUpOnGitFailure() async throws {
        let parent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: parent) }

        let bogusURL = parent.appendingPathComponent("nonexistent.git").path
        let cloner = GitCloner()
        let result = await withCheckedContinuation { (cont: CheckedContinuation<Result<String, GitCloner.CloneError>, Never>) in
            cloner.start(
                options: .init(url: bogusURL, parentDir: parent.path, branch: nil, shallow: false),
                onProgress: { _ in },
                onComplete: { cont.resume(returning: $0) }
            )
        }

        if case .failure(.gitFailed) = result { } else {
            Issue.record("expected .gitFailed, got \(result)")
        }
        // 目标目录已被清理
        let target = (parent.path as NSString).appendingPathComponent("nonexistent")
        #expect(!FileManager.default.fileExists(atPath: target))
    }
```

- [ ] **Step 2: 跑测试，应失败（成功路径返回的是 stub error）**

Run:
```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -destination 'platform=macOS' \
  -only-testing:GhosttyTests/GitClonerTests 2>&1 | tail -40
```
Expected: `clonesLocalBareRepoSuccessfully` 失败（拿到 stub gitFailed），其它通过。

- [ ] **Step 3: 实现真正的子进程调用**

在 `GitCloner.swift` 中，把 `start()` 末尾的 stub 段（从 `self.targetPath = target` 开始的部分）替换为：

```swift
        // 预检通过 — 启动子进程
        self.targetPath = target
        self.isRunning = true

        var args = ["clone", "--progress", trimmedURL, target]
        if let branch = options.branch, !branch.isEmpty {
            args.append(contentsOf: ["-b", branch])
        }
        if options.shallow {
            args.append(contentsOf: ["--depth", "1"])
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = args
        proc.environment = [
            "HOME": NSHomeDirectory(),
            "PATH": "/usr/bin:/bin:/usr/local/bin",
            "GIT_TERMINAL_PROMPT": "0",
        ]

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        let stderrBuffer = StderrBuffer()

        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stderrBuffer.append(data)
            if let line = stderrBuffer.lastLine() {
                DispatchQueue.main.async { onProgress(line) }
            }
        }

        proc.terminationHandler = { [weak self] p in
            guard let self else { return }
            errPipe.fileHandleForReading.readabilityHandler = nil
            let stderrText = stderrBuffer.snapshot()
            let exitCode = p.terminationStatus

            DispatchQueue.main.async {
                self.isRunning = false
                self.process = nil

                if exitCode == 0 {
                    onComplete(.success(target))
                } else {
                    // 清理半成品目录（只删 target 自身）
                    self.cleanupTargetIfPresent()
                    if self.cancelRequested {
                        self.cancelRequested = false
                        onComplete(.failure(.cancelled))
                    } else {
                        onComplete(.failure(.gitFailed(exitCode: exitCode, stderr: stderrText)))
                    }
                }
                self.targetPath = nil
            }
        }

        do {
            try proc.run()
            self.process = proc
        } catch {
            self.isRunning = false
            self.process = nil
            self.cleanupTargetIfPresent()
            self.targetPath = nil
            DispatchQueue.main.async {
                onComplete(.failure(.gitFailed(exitCode: -1, stderr: error.localizedDescription)))
            }
        }
```

并在 `GitCloner` 类内追加这些字段与辅助：

```swift
    private var cancelRequested: Bool = false

    /// 只删 target 自身，不递归动 parentDir。
    private func cleanupTargetIfPresent() {
        guard let path = targetPath else { return }
        try? FileManager.default.removeItem(atPath: path)
    }
```

并在 `GitCloner.swift` 文件末尾（类外）追加 stderr 缓冲器：

```swift
private final class StderrBuffer {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
    }

    /// 返回最近一行（按 \n 分割），用于进度显示。
    func lastLine() -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
        return lines.last.map(String.init)
    }

    func snapshot() -> String {
        lock.lock(); defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
```

- [ ] **Step 4: 跑测试**

Run: 同 Step 2 命令。
Expected: 全部通过（含 `clonesLocalBareRepoSuccessfully` 和 `cleansUpOnGitFailure`）。

- [ ] **Step 5: 提交**

```bash
git add macos/Sources/Features/Workspace/GitCloner.swift macos/Tests/Workspace/GitClonerTests.swift
git commit -m "feat(workspace): GitCloner runs git clone with stderr progress and cleanup on failure"
```

---

## Task 4: GitCloner — 取消支持

**Files:**
- Modify: `macos/Sources/Features/Workspace/GitCloner.swift`
- Modify: `macos/Tests/Workspace/GitClonerTests.swift`

- [ ] **Step 1: 写取消测试**

追加到 `GitClonerTests.swift`：

```swift
    @Test func cancelTerminatesAndCleansUp() async throws {
        let parent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: parent) }
        let src = try makeBareSourceRepo()
        defer { src.cleanup() }

        let cloner = GitCloner()
        async let resultFuture: Result<String, GitCloner.CloneError> = withCheckedContinuation { cont in
            cloner.start(
                options: .init(url: src.path, parentDir: parent.path, branch: nil, shallow: false),
                onProgress: { _ in },
                onComplete: { cont.resume(returning: $0) }
            )
        }

        // 让 git 进程有机会启动
        try await Task.sleep(nanoseconds: 50_000_000)
        cloner.cancel()

        let result = await resultFuture
        // 因为本地 clone 极快，可能在 cancel 前已成功；任一结果都接受，但若 cancelled 则 target 必须清理
        switch result {
        case .success:
            break
        case .failure(.cancelled):
            let target = (parent.path as NSString).appendingPathComponent("bare")
            #expect(!FileManager.default.fileExists(atPath: target))
        case .failure(let other):
            Issue.record("unexpected failure: \(other)")
        }
    }
```

- [ ] **Step 2: 跑测试，应失败（缺 cancel 方法）**

Run:
```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -destination 'platform=macOS' \
  -only-testing:GhosttyTests/GitClonerTests/cancelTerminatesAndCleansUp 2>&1 | tail -30
```
Expected: 编译错误 `value of type 'GitCloner' has no member 'cancel'`。

- [ ] **Step 3: 实现 cancel**

在 `GitCloner` 类内追加：

```swift
    /// 中止当前 clone。SIGTERM → 250ms 宽限 → SIGKILL。
    /// terminationHandler 会负责清理目标目录并以 .cancelled 触发 onComplete。
    func cancel() {
        guard let proc = process, proc.isRunning else { return }
        cancelRequested = true
        proc.terminate()
        let pid = proc.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
            if proc.isRunning {
                kill(pid, SIGKILL)
            }
        }
    }
```

- [ ] **Step 4: 跑测试**

Run:
```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -destination 'platform=macOS' \
  -only-testing:GhosttyTests/GitClonerTests 2>&1 | tail -40
```
Expected: 全部通过。

- [ ] **Step 5: 提交**

```bash
git add macos/Sources/Features/Workspace/GitCloner.swift macos/Tests/Workspace/GitClonerTests.swift
git commit -m "feat(workspace): GitCloner.cancel terminates subprocess and cleans up"
```

---

## Task 5: WorkspaceCreateForm — 引入 WorkspaceCreateSource，重构 snapshot 模式

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceCreateForm.swift`

**目标**：把 `createFromSnapshot: Bool` 重构为 `source: WorkspaceCreateSource` 三态枚举，UI 顶部加 segmented Picker，empty / snapshot 模式行为完全保留。**本任务不引入 git 模式字段**，留到 Task 6。

- [ ] **Step 1: 在文件顶部、`struct WorkspaceCreateForm` 之前插入枚举**

在 `import SwiftUI` 之后追加：

```swift
enum WorkspaceCreateSource: String, CaseIterable, Identifiable {
    case empty
    case snapshot
    case git

    var id: String { rawValue }

    var label: String {
        switch self {
        case .empty: return "Empty"
        case .snapshot: return "From Snapshot"
        case .git: return "From Git"
        }
    }
}
```

- [ ] **Step 2: 替换 `createFromSnapshot` State**

把：

```swift
    @State private var createFromSnapshot = false
```

替换为：

```swift
    @State private var source: WorkspaceCreateSource = .empty
```

- [ ] **Step 3: 全量替换所有 `createFromSnapshot` 引用**

在文件内把所有 `createFromSnapshot` 替换为 `source == .snapshot`，并把所有写赋值（如 `createFromSnapshot = true`）改为 `source = .snapshot`：

具体位置：
1. `if createFromSnapshot { ... }` 字段渲染段 → `if source == .snapshot { ... }`
2. `Toggle("Create from snapshot", isOn: $createFromSnapshot)` → 删掉这一整行（picker 替代）
3. `if createFromSnapshot, let wsId = snapshotWorkspaceId, ...`（在 Create 按钮的 action 内）→ `if source == .snapshot, let wsId = snapshotWorkspaceId, ...`
4. `.onChange(of: snapshotWorkspaceId) { wsId in guard createFromSnapshot, ... }` → `guard source == .snapshot, ...`
5. `.onAppear { ... } else if let wsId = preselectedSourceWorkspaceId { createFromSnapshot = true; ... }` → `source = .snapshot`

- [ ] **Step 4: 在 Title 下方插入 segmented Picker（仅在非 editing 模式显示）**

在文件中找到：

```swift
            Text(editing != nil ? "Edit Workspace" : "New Workspace")
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 20)
                .padding(.bottom, 16)
```

在其后插入：

```swift
            if editing == nil {
                Picker("", selection: $source) {
                    ForEach(WorkspaceCreateSource.allCases) { src in
                        Text(src.label).tag(src)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
```

- [ ] **Step 5: 删除原 `Divider() + Toggle` 那一段**

定位到字段 VStack 内：

```swift
                // Create from snapshot (new workspace only)
                if editing == nil {
                    Divider()
                        .padding(.vertical, 4)

                    Toggle("Create from snapshot", isOn: $createFromSnapshot)
                        .font(.system(size: 12, weight: .medium))

                    if createFromSnapshot {
```

替换为：

```swift
                // Snapshot source picker (new workspace only, snapshot mode)
                if editing == nil && source == .snapshot {
```

注意：原代码的 Divider 与 Toggle 一起删除。结尾的 `}` 闭合 if 也要少一层（原本是 `if editing == nil { ... if createFromSnapshot { ... } }`，现在合并成一个条件），整理时要把多余的 `}` 删掉。

- [ ] **Step 6: 编译验证**

Run: `make check`
Expected: `No Swift compilation errors found`。

- [ ] **Step 7: 提交**

```bash
git add macos/Sources/Features/Workspace/WorkspaceCreateForm.swift
git commit -m "refactor(workspace): replace snapshot toggle with WorkspaceCreateSource picker"
```

---

## Task 6: WorkspaceCreateForm — 添加 .git 模式字段 UI

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceCreateForm.swift`

**目标**：在 `.git` 模式下显示 Git URL / Parent Directory / Branch / Shallow 字段，但不接 GitCloner 逻辑（下个任务做）。

- [ ] **Step 1: 增加 git 模式 State**

在 `@State private var source` 之后追加：

```swift
    @State private var gitURL: String = ""
    @State private var gitParentDir: String = "~"
    @State private var gitBranch: String = ""
    @State private var gitShallow: Bool = false
    @State private var nameWasManuallyEdited: Bool = false
    @State private var internallySettingName: Bool = false
```

- [ ] **Step 2: 让 Root Directory 字段在 git 模式下隐藏，并在 git 模式下渲染新字段**

定位到现有 Root Directory 字段段：

```swift
                // Root directory
                VStack(alignment: .leading, spacing: 4) {
                    Text("Root Directory")
                    ...
                }
```

把它整段包裹为：

```swift
                if source != .git {
                    // Root directory
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Root Directory")
                        ...
                    }
                }
```

然后在 Color 字段**之前**追加 git 模式字段段：

```swift
                if source == .git {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Git URL")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        TextField("https://github.com/user/repo.git", text: $gitURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                            .disabled(isCloning)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Parent Directory")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        HStack(spacing: 6) {
                            TextField("~/projects", text: $gitParentDir)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13))
                                .disabled(isCloning)
                            Button("Browse...") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.allowsMultipleSelection = false
                                if panel.runModal() == .OK, let url = panel.url {
                                    gitParentDir = url.path
                                }
                            }
                            .font(.system(size: 12))
                            .disabled(isCloning)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Branch (optional)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        TextField("default branch", text: $gitBranch)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                            .disabled(isCloning)
                    }

                    Toggle("Shallow clone (--depth 1)", isOn: $gitShallow)
                        .font(.system(size: 12, weight: .medium))
                        .disabled(isCloning)
                }
```

> 注意：本步骤里出现的 `isCloning` 是占位，下个任务会添加该 State。本步骤暂时把所有 `.disabled(isCloning)` 改为 `.disabled(false)`，下个任务再统一替换。

**修订上面这些行**：把 `.disabled(isCloning)` 全部写成 `.disabled(false)`，以保证本任务结束时编译通过。

- [ ] **Step 3: 添加 Name 联动逻辑**

定位到现有的 `.onChange(of: name) { _ in errorMessage = nil }`，**替换**为：

```swift
        .onChange(of: name) { _ in
            errorMessage = nil
            // 通过 gitURL 联动设置 name 时，跳过「用户手动编辑」标记
            if internallySettingName {
                internallySettingName = false
            } else if source == .git {
                nameWasManuallyEdited = true
            }
        }
        .onChange(of: gitURL) { newURL in
            guard source == .git, !nameWasManuallyEdited else { return }
            if let repoName = GitCloner.extractRepoName(from: newURL) {
                internallySettingName = true
                name = repoName
            }
        }
        .onChange(of: source) { _ in
            // 切换创建来源时重置「是否手动编辑过 name」标记
            nameWasManuallyEdited = false
        }
```

`internallySettingName` 哨兵保证由 gitURL 联动触发的 `name` 修改不会被误判为用户手动编辑。普通用户键入 `name` 时哨兵为 false，正常走 manual edit 标记分支。

- [ ] **Step 4: 编译验证**

Run: `make check`
Expected: `No Swift compilation errors found`。

- [ ] **Step 5: 提交**

```bash
git add macos/Sources/Features/Workspace/WorkspaceCreateForm.swift
git commit -m "feat(workspace): add git source UI fields to WorkspaceCreateForm"
```

---

## Task 7: WorkspaceCreateForm — 接入 GitCloner、进度、取消、错误流程

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceCreateForm.swift`

- [ ] **Step 1: 添加 cloner 持有者类**

在 `WorkspaceCreateForm` struct 之外（同文件顶部、`enum WorkspaceCreateSource` 之后）追加：

```swift
/// `GitCloner` 是引用类型且非 ObservableObject，用一个轻量持有者把它绑到 SwiftUI 生命周期。
final class GitClonerHolder: ObservableObject {
    let inner = GitCloner()
}
```

- [ ] **Step 2: 添加 cloning state**

在 `@State private var nameWasManuallyEdited` 之后追加：

```swift
    @State private var isCloning: Bool = false
    @State private var cloneProgress: String = ""
    @StateObject private var clonerHolder = GitClonerHolder()
```

- [ ] **Step 3: 把 Task 6 中的 `.disabled(false)` 全部改回 `.disabled(isCloning)`**

在文件内对所有刚添加的 git 字段段，把 `.disabled(false)` 替换回 `.disabled(isCloning)`。同时把顶部 Picker 也加上 `.disabled(isCloning)`：

```swift
                Picker("", selection: $source) {
                    ForEach(WorkspaceCreateSource.allCases) { src in
                        Text(src.label).tag(src)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isCloning)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
```

- [ ] **Step 4: 在按钮区上方插入进度条**

定位到底部按钮区（`HStack { Button("Cancel") ... Button(...) }`）的 `HStack` **之前**插入：

```swift
            if isCloning {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.6)
                    Text(cloneProgress.isEmpty ? "Cloning…" : cloneProgress)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
```

- [ ] **Step 5: 改造 Cancel 与 Create 按钮**

定位到现有按钮 HStack：

```swift
            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button(editing != nil ? "Save" : "Create") {
                    // ... 现有 submit 逻辑 ...
                }
                .keyboardShortcut(.return)
                .disabled(name.isEmpty)
            }
```

替换为：

```swift
            HStack {
                Button(isCloning ? "Cancel Clone" : "Cancel") {
                    if isCloning {
                        clonerHolder.inner.cancel()
                    } else {
                        onCancel()
                    }
                }
                .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button(submitButtonTitle) {
                    handleSubmit()
                }
                .keyboardShortcut(.return)
                .disabled(submitDisabled)
            }
```

并在 `body` 之前的 helper 区（或紧贴 `body` 的 computed 属性区）追加：

```swift
    private var submitButtonTitle: String {
        if editing != nil { return "Save" }
        if isCloning { return "Cloning…" }
        return "Create"
    }

    private var submitDisabled: Bool {
        if name.isEmpty { return true }
        if isCloning { return true }
        if source == .git && gitURL.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        return false
    }
```

- [ ] **Step 6: 抽出 handleSubmit / startClone / finalizeCreate / showError**

把 Create 按钮原 action 的 closure 内容（从 `let existingNames = manager.workspaces` 到 `onSubmit(name, rootDir, selectedColor, description)`）整段抽到一个新方法里。在 `body` 之外、`onAppear` 引用的 helper 旁边追加：

```swift
    private func showError(_ message: String) {
        errorMessage = message
        withAnimation(.linear(duration: 0.4)) { isShaking = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { isShaking = false }
    }

    private func handleSubmit() {
        let existingNames = manager.workspaces
            .filter { $0.id != editing?.id }
            .map { $0.name }
        if let error = WorkspaceNameValidator.validate(name, existingNames: existingNames) {
            showError(error)
            return
        }
        errorMessage = nil

        switch source {
        case .empty:
            onSubmit(name, rootDir, selectedColor, description)
        case .snapshot:
            // 与原逻辑一致：未填 rootDir 时从来源 Workspace 复制
            var effectiveRoot = rootDir
            if let wsId = snapshotWorkspaceId,
               let sourceWorkspace = WorkspaceManager.shared.workspace(for: wsId),
               effectiveRoot == "~" || effectiveRoot.isEmpty {
                effectiveRoot = sourceWorkspace.rootDir
            }
            onSubmit(name, effectiveRoot, selectedColor, description)
        case .git:
            startClone()
        }
    }

    private func startClone() {
        let parent = (gitParentDir as NSString).expandingTildeInPath
        let opts = GitCloner.Options(
            url: gitURL.trimmingCharacters(in: .whitespacesAndNewlines),
            parentDir: parent,
            branch: gitBranch.trimmingCharacters(in: .whitespaces).isEmpty ? nil : gitBranch.trimmingCharacters(in: .whitespaces),
            shallow: gitShallow
        )
        isCloning = true
        cloneProgress = ""
        errorMessage = nil

        clonerHolder.inner.start(
            options: opts,
            onProgress: { line in
                cloneProgress = line
            },
            onComplete: { result in
                isCloning = false
                switch result {
                case .success(let path):
                    onSubmit(name, path, selectedColor, description)
                case .failure(let err):
                    showError(err.errorDescription ?? "Clone failed")
                }
            }
        )
    }
```

- [ ] **Step 7: 在 view 末尾添加 .onDisappear 兜底**

在 `.onAppear { ... }` 之后追加：

```swift
        .onDisappear {
            if isCloning {
                clonerHolder.inner.cancel()
            }
        }
```

- [ ] **Step 8: 编译验证**

Run: `make check`
Expected: `No Swift compilation errors found`。

- [ ] **Step 9: 提交**

```bash
git add macos/Sources/Features/Workspace/WorkspaceCreateForm.swift
git commit -m "feat(workspace): wire git clone flow into WorkspaceCreateForm"
```

---

## Task 8: 全量构建 + 单元测试通过

**Files:**
- N/A

- [ ] **Step 1: 完整构建 Debug**

Run:
```bash
make check
```
Expected: `No Swift compilation errors found`。

- [ ] **Step 2: 跑 Workspace 全部单元测试**

Run:
```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -destination 'platform=macOS' \
  -only-testing:GhosttyTests/GitClonerTests 2>&1 | tail -20
```
Expected: GitClonerTests 全绿。

- [ ] **Step 3: 构建可运行 app**

Run:
```bash
make dev
```
Expected: 构建完成，无错误。

---

## Task 9: 手工 UI 验证

**Files:**
- N/A（人工测试）

按 spec 中的「手工测试清单」逐项验证。下面只列条目，每项执行后勾选。

- [ ] 启动 `make run-dev`
- [ ] 表单顶部 segmented Picker 切换 Empty / From Snapshot / From Git，字段区跟随刷新
- [ ] **Empty 模式回归**：填 Name + Root Directory，Create，新 workspace 出现并可打开
- [ ] **Snapshot 模式回归**：从已有快照创建一个新 workspace（需要先有快照），路径复制正常
- [ ] **Snapshot 入口回归**：在快照管理面板点「从此创建」，表单打开后 Picker 已停在 From Snapshot，来源已预选
- [ ] **Git 模式公开仓库**：URL = `https://github.com/octocat/Hello-World.git`，Parent = `~/Downloads`，点 Create
  - [ ] Name 字段自动填 `Hello-World`
  - [ ] 按钮变成 Cloning…，进度小字滚动
  - [ ] 成功后表单关闭，新 workspace 出现，rootDir 指向 `~/Downloads/Hello-World`
- [ ] **手改 Name 不被覆盖**：清空 URL 重新输入一个不同 URL，Name 不再变
- [ ] **私有仓库（SSH key 已配置）**：用一个你能访问的私有仓库 URL，clone 成功
- [ ] **不存在的仓库**：URL 拼一个错的，应红字报错，目标目录不存在
- [ ] **取消 clone**：用一个大仓库 URL，clone 进行中点 Cancel Clone，红字「Clone cancelled」，目标目录不存在
- [ ] **目标已存在**：父目录里手动建一个同名目录，提交时立即报「Target already exists」，git 未启动
- [ ] **Shallow**：勾选 Shallow，clone 后目标目录的 `.git/shallow` 文件存在
- [ ] **指定 Branch**：填一个非默认分支，clone 后 `git -C <target> rev-parse --abbrev-ref HEAD` 等于该分支
- [ ] **编辑 workspace 时**：从侧边栏右键编辑现有 workspace，Picker 不显示，行为与之前一致
- [ ] **进程清理**：clone 进行中关闭表单（Cancel Clone 后再 Cancel，或直接关窗），用 Activity Monitor 确认没有遗留 git 子进程

---

## 完成判据

- 上述全部 task 步骤的 checkbox 都打勾
- `make check` 干净
- `GitClonerTests` 全绿
- 手工测试清单 9 项全过
- 工作区 git status 干净（除最后一个未提交的进度提交可在最终一次合并 commit 中处理）
