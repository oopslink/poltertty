# Git Worktree Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add git worktree navigation/management in the sidebar and worktree awareness in the status bar.

**Architecture:** `GitWorktreeMonitor` (per-window) handles worktree listing, filesystem watching, and git operations. Sidebar shows collapsible worktree children under the current workspace. Status bar displays a colored badge when in a linked worktree. All git subprocess calls run on background queues with main-thread UI updates.

**Tech Stack:** Swift, SwiftUI, DispatchSource (filesystem watching), Process (git subprocess)

**Spec:** `docs/superpowers/specs/2026-03-23-git-worktree-support-design.md`

---

### Task 1: GitWorktree Data Model & Porcelain Parser

**Files:**
- Create: `macos/Sources/Features/Workspace/GitWorktreeMonitor.swift`
- Create: `macos/Tests/Workspace/GitWorktreeParserTests.swift`

This task creates the data model and the parser for `git worktree list --porcelain` output. The monitor class skeleton is created but filesystem watching and operations are deferred to Task 2.

- [ ] **Step 1: Write parser tests**

```swift
// macos/Tests/Workspace/GitWorktreeParserTests.swift
import Testing
import Foundation
@testable import Ghostty

struct GitWorktreeParserTests {

    @Test func testParseSingleMainWorktree() {
        let output = """
        worktree /Users/dev/project
        HEAD abc123def456
        branch refs/heads/main

        """
        let result = GitWorktreeParser.parse(porcelain: output, currentPath: "/Users/dev/project")
        #expect(result.count == 1)
        #expect(result[0].path == "/Users/dev/project")
        #expect(result[0].branch == "main")
        #expect(result[0].isMain == true)
        #expect(result[0].isCurrent == true)
    }

    @Test func testParseMultipleWorktrees() {
        let output = """
        worktree /Users/dev/project
        HEAD abc123
        branch refs/heads/main

        worktree /Users/dev/project/.worktrees/feature-auth
        HEAD def456
        branch refs/heads/feature/auth

        worktree /Users/dev/project/.worktrees/detached-work
        HEAD 789abc
        detached

        """
        let result = GitWorktreeParser.parse(porcelain: output, currentPath: "/Users/dev/project/.worktrees/feature-auth")
        #expect(result.count == 3)
        // Main worktree
        #expect(result[0].isMain == true)
        #expect(result[0].isCurrent == false)
        #expect(result[0].branch == "main")
        // Feature worktree (current)
        #expect(result[1].isMain == false)
        #expect(result[1].isCurrent == true)
        #expect(result[1].branch == "feature/auth")
        // Detached worktree
        #expect(result[2].branch == nil)
        #expect(result[2].isMain == false)
    }

    @Test func testParseEmpty() {
        let result = GitWorktreeParser.parse(porcelain: "", currentPath: "/tmp")
        #expect(result.isEmpty)
    }

    @Test func testParseBareSkipped() {
        let output = """
        worktree /Users/dev/bare-repo
        HEAD abc123
        bare

        worktree /Users/dev/bare-repo/.worktrees/work
        HEAD def456
        branch refs/heads/main

        """
        let result = GitWorktreeParser.parse(porcelain: output, currentPath: "/Users/dev/bare-repo/.worktrees/work")
        #expect(result.count == 1)
        #expect(result[0].branch == "main")
    }

    @Test func testPathNormalization() {
        let output = """
        worktree /Users/dev/project/
        HEAD abc123
        branch refs/heads/main

        """
        let result = GitWorktreeParser.parse(porcelain: output, currentPath: "/Users/dev/project")
        #expect(result[0].isCurrent == true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/aaronlin/works/codes/oss/poltertty && xcodebuild test -scheme Ghostty -destination 'platform=macOS' -only-testing:GhosttyTests/GitWorktreeParserTests 2>&1 | tail -20`
Expected: Compilation error — `GitWorktreeParser` not defined.

- [ ] **Step 3: Implement data model and parser**

```swift
// macos/Sources/Features/Workspace/GitWorktreeMonitor.swift
import Foundation

// MARK: - Data Model

struct GitWorktree: Identifiable, Equatable {
    let id: UUID
    let path: String        // absolute path to the worktree
    let branch: String?     // nil when HEAD is detached
    let isMain: Bool        // true for the primary worktree
    let isCurrent: Bool     // true when this worktree matches the monitor's rootDir
}

// MARK: - Porcelain Parser

enum GitWorktreeParser {
    /// Parse `git worktree list --porcelain` output into GitWorktree array.
    /// - Parameters:
    ///   - porcelain: raw output from git
    ///   - currentPath: the monitor's rootDir, used to set `isCurrent`
    static func parse(porcelain: String, currentPath: String) -> [GitWorktree] {
        let normalizedCurrent = URL(fileURLWithPath: currentPath).standardized.path
        var worktrees: [GitWorktree] = []
        var isFirst = true

        // Split into blocks separated by blank lines
        let blocks = porcelain.components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n")
            guard !lines.isEmpty else { continue }

            var path: String?
            var branch: String?
            var isBare = false
            var isDetached = false

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("worktree ") {
                    path = String(trimmed.dropFirst("worktree ".count))
                } else if trimmed.hasPrefix("branch refs/heads/") {
                    branch = String(trimmed.dropFirst("branch refs/heads/".count))
                } else if trimmed == "detached" {
                    isDetached = true
                } else if trimmed == "bare" {
                    isBare = true
                }
            }

            guard let wtPath = path, !isBare else { continue }

            let normalizedPath = URL(fileURLWithPath: wtPath).standardized.path
            worktrees.append(GitWorktree(
                id: UUID(),
                path: normalizedPath,
                branch: isDetached ? nil : branch,
                isMain: isFirst,
                isCurrent: normalizedPath == normalizedCurrent
            ))
            isFirst = false
        }

        return worktrees
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/aaronlin/works/codes/oss/poltertty && xcodebuild test -scheme Ghostty -destination 'platform=macOS' -only-testing:GhosttyTests/GitWorktreeParserTests 2>&1 | tail -20`
Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Workspace/GitWorktreeMonitor.swift macos/Tests/Workspace/GitWorktreeParserTests.swift
git commit -m "feat(worktree): add GitWorktree data model and porcelain parser"
```

---

### Task 2: GitWorktreeMonitor — Git Detection, Refresh, Filesystem Watching

**Files:**
- Modify: `macos/Sources/Features/Workspace/GitWorktreeMonitor.swift`

This task adds the full monitor class: git detection, worktree listing via subprocess, filesystem watching with the two-source strategy, and debounced refresh. No UI integration yet.

- [ ] **Step 1: Add the GitWorktreeMonitor class with git detection and refresh**

Append to `GitWorktreeMonitor.swift` after the parser:

```swift
// MARK: - Monitor

final class GitWorktreeMonitor: ObservableObject {
    @Published var worktrees: [GitWorktree] = []
    @Published var isGitRepo: Bool = false

    private let rootDir: String
    private var gitRoot: String?           // resolved via --show-toplevel
    private var gitCommonDir: String?      // resolved via --git-common-dir (main .git)
    private let queue = DispatchQueue(label: "poltertty.git-worktree-monitor")

    private var dotGitSource: DispatchSourceFileSystemObject?
    private var worktreesSource: DispatchSourceFileSystemObject?
    private var debounceWork: DispatchWorkItem?

    init(rootDir: String) {
        self.rootDir = rootDir
        queue.async { [weak self] in
            self?.detectAndSetup()
        }
    }

    deinit {
        dotGitSource?.cancel()
        worktreesSource?.cancel()
        debounceWork?.cancel()
    }

    // MARK: - Git Detection

    private func detectAndSetup() {
        // Find the worktree root
        let toplevelResult = runGit(["-C", rootDir, "rev-parse", "--show-toplevel"])
        guard toplevelResult.exitCode == 0,
              let toplevel = toplevelResult.output?.trimmingCharacters(in: .whitespacesAndNewlines),
              !toplevel.isEmpty else {
            DispatchQueue.main.async { [weak self] in
                self?.isGitRepo = false
                self?.worktrees = []
            }
            return
        }
        gitRoot = toplevel

        // Find the common .git directory (for linked worktrees, this points to main repo's .git)
        let commonDirResult = runGit(["-C", rootDir, "rev-parse", "--git-common-dir"])
        if commonDirResult.exitCode == 0,
           let commonDir = commonDirResult.output?.trimmingCharacters(in: .whitespacesAndNewlines),
           !commonDir.isEmpty {
            // Resolve relative path to absolute
            if commonDir.hasPrefix("/") {
                gitCommonDir = commonDir
            } else {
                let resolved = URL(fileURLWithPath: toplevel).appendingPathComponent(commonDir).standardized.path
                gitCommonDir = resolved
            }
        } else {
            gitCommonDir = "\(toplevel)/.git"
        }

        DispatchQueue.main.async { [weak self] in
            self?.isGitRepo = true
        }

        refresh()
        setupWatching()
    }

    // MARK: - Refresh

    private func refresh() {
        guard let root = gitRoot else { return }
        let result = runGit(["-C", root, "worktree", "list", "--porcelain"])
        guard result.exitCode == 0, let output = result.output else {
            NSLog("[GitWorktreeMonitor] git worktree list failed: exit=\(result.exitCode)")
            return
        }
        let parsed = GitWorktreeParser.parse(porcelain: output, currentPath: rootDir)
        DispatchQueue.main.async { [weak self] in
            self?.worktrees = parsed
        }
    }

    // MARK: - Filesystem Watching

    private func setupWatching() {
        guard let gitDir = gitCommonDir else { return }

        // Source 1: watch .git directory itself
        startDotGitSource(gitDir: gitDir)

        // Source 2: watch .git/worktrees if it exists
        let worktreesPath = "\(gitDir)/worktrees"
        if FileManager.default.fileExists(atPath: worktreesPath) {
            startWorktreesSource(path: worktreesPath)
        }
    }

    private func startDotGitSource(gitDir: String) {
        let fd = open(gitDir, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("[GitWorktreeMonitor] open failed for \(gitDir): errno=\(errno)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: .write, queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let worktreesPath = "\(gitDir)/worktrees"
            let exists = FileManager.default.fileExists(atPath: worktreesPath)

            if exists && self.worktreesSource == nil {
                self.startWorktreesSource(path: worktreesPath)
            } else if !exists && self.worktreesSource != nil {
                self.worktreesSource?.cancel()
                self.worktreesSource = nil
            }
            self.scheduleRefresh()
        }
        source.setCancelHandler { close(fd) }
        dotGitSource = source
        source.resume()
    }

    private func startWorktreesSource(path: String) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("[GitWorktreeMonitor] open failed for \(path): errno=\(errno)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: .write, queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.scheduleRefresh()
        }
        source.setCancelHandler { close(fd) }
        worktreesSource = source
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

    func stopWatching() {
        dotGitSource?.cancel()
        dotGitSource = nil
        worktreesSource?.cancel()
        worktreesSource = nil
        debounceWork?.cancel()
        debounceWork = nil
    }

    // MARK: - Subprocess

    private struct GitResult {
        let exitCode: Int32
        let output: String?
        let stderr: String?
    }

    private func runGit(_ args: [String]) -> GitResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = args
        proc.environment = ["HOME": NSHomeDirectory()]
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            return GitResult(
                exitCode: proc.terminationStatus,
                output: String(data: outData, encoding: .utf8),
                stderr: String(data: errData, encoding: .utf8)
            )
        } catch {
            NSLog("[GitWorktreeMonitor] git error: \(error)")
            return GitResult(exitCode: -1, output: nil, stderr: nil)
        }
    }
}
```

- [ ] **Step 2: Verify build compiles**

Run: `cd /Users/aaronlin/works/codes/oss/poltertty && xcodebuild build -scheme Ghostty -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/GitWorktreeMonitor.swift
git commit -m "feat(worktree): add GitWorktreeMonitor with git detection, refresh, and filesystem watching"
```

---

### Task 3: GitWorktreeMonitor — Worktree Operations & Branch Listing

**Files:**
- Modify: `macos/Sources/Features/Workspace/GitWorktreeMonitor.swift`

Adds `addWorktree`, `removeWorktree`, `listBranches`, and `checkDirtyStatus` methods.

- [ ] **Step 1: Add operations to GitWorktreeMonitor**

Add these methods to the `GitWorktreeMonitor` class, before the `// MARK: - Subprocess` section:

```swift
    // MARK: - Worktree Operations

    /// Add a new worktree.
    /// - Parameters:
    ///   - branch: branch name (new or existing)
    ///   - path: worktree path (relative to git root or absolute)
    ///   - baseBranch: base branch to create from (only used when createNew is true)
    ///   - createNew: if true, creates a new branch with `-b`
    /// - Throws: Error with git stderr message on failure
    func addWorktree(branch: String, path: String, baseBranch: String?, createNew: Bool) throws {
        guard let root = gitRoot else {
            throw WorktreeError.notGitRepo
        }
        var args = ["-C", root, "worktree", "add"]
        if createNew {
            args += ["-b", branch]
        }
        // Resolve relative path against git root
        let resolvedPath: String
        if path.hasPrefix("/") {
            resolvedPath = path
        } else {
            resolvedPath = URL(fileURLWithPath: root).appendingPathComponent(path).path
        }
        args.append(resolvedPath)
        if createNew, let base = baseBranch {
            args.append(base)
        } else if !createNew {
            args.append(branch)
        }
        let result = runGit(args)
        if result.exitCode != 0 {
            let message = result.stderr?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
            throw WorktreeError.gitError(message)
        }
        // Filesystem watcher will auto-trigger refresh
    }

    /// Remove a worktree.
    /// - Parameters:
    ///   - path: absolute path of the worktree to remove
    ///   - force: if true, uses --force (for dirty worktrees)
    /// - Throws: Error with git stderr message on failure
    func removeWorktree(path: String, force: Bool) throws {
        guard let root = gitRoot else {
            throw WorktreeError.notGitRepo
        }
        var args = ["-C", root, "worktree", "remove"]
        if force { args.append("--force") }
        args.append(path)
        let result = runGit(args)
        if result.exitCode != 0 {
            let message = result.stderr?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
            throw WorktreeError.gitError(message)
        }
    }

    /// List available branches, excluding those that already have a worktree.
    func listBranches() -> [String] {
        guard let root = gitRoot else { return [] }
        let result = runGit(["-C", root, "branch", "-a", "--format=%(refname:short)"])
        guard result.exitCode == 0, let output = result.output else { return [] }
        let allBranches = output.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let worktreeBranches = Set(worktrees.compactMap { $0.branch })
        return allBranches.filter { !worktreeBranches.contains($0) }
    }

    /// Check the number of uncommitted changes in a worktree.
    func dirtyFileCount(at path: String) -> Int {
        let result = runGit(["-C", path, "status", "--porcelain"])
        guard result.exitCode == 0, let output = result.output else { return 0 }
        return output.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }

    // MARK: - Errors

    enum WorktreeError: LocalizedError {
        case notGitRepo
        case gitError(String)

        var errorDescription: String? {
            switch self {
            case .notGitRepo: return "Not a git repository"
            case .gitError(let msg): return msg
            }
        }
    }
```

- [ ] **Step 2: Verify build compiles**

Run: `cd /Users/aaronlin/works/codes/oss/poltertty && xcodebuild build -scheme Ghostty -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/GitWorktreeMonitor.swift
git commit -m "feat(worktree): add worktree add/remove operations and branch listing"
```

---

### Task 4: GitStatusMonitor — Add isLinkedWorktree Detection

**Files:**
- Modify: `macos/Sources/Features/Workspace/GitStatusMonitor.swift`
- Modify: `macos/Tests/Workspace/GitStatusMonitorTests.swift`

- [ ] **Step 1: Add isLinkedWorktree to GitRepoStatus**

In `GitStatusMonitor.swift`, modify the `GitRepoStatus` struct:

```swift
struct GitRepoStatus: Equatable {
    let branch: String?
    let added: Int
    let modified: Int
    let isGitRepo: Bool
    let isLinkedWorktree: Bool   // NEW: true when cwd is inside a linked worktree

    static let empty = GitRepoStatus(branch: nil, added: 0, modified: 0, isGitRepo: false, isLinkedWorktree: false)
}
```

- [ ] **Step 2: Update refresh() to detect linked worktree**

In `GitStatusMonitor.refresh()` (line 136-157), replace the entire method body:

```swift
    private func refresh() {
        let pwd = gitRoot ?? currentPwd
        guard !pwd.isEmpty else { return }

        let branchResult = runGit(["-C", pwd, "branch", "--show-current"])
        let branchOutput = branchResult.output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let branch: String? = branchOutput.isEmpty ? nil : branchOutput

        let statusResult = runGit(["-C", pwd, "status", "--porcelain"])
        let porcelain = statusResult.output ?? ""
        let counts = GitStatusParser.parse(porcelain: porcelain)

        // Detect linked worktree: --git-common-dir returns ".git" for main worktree,
        // or a relative/absolute path for linked worktrees
        let commonDirResult = runGit(["-C", pwd, "rev-parse", "--git-common-dir"])
        let commonDir = commonDirResult.output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ".git"
        let isLinked = commonDir != ".git"

        let newStatus = GitRepoStatus(
            branch: branch,
            added: counts.added,
            modified: counts.modified,
            isGitRepo: true,
            isLinkedWorktree: isLinked
        )
        DispatchQueue.main.async { [weak self] in
            self?.status = newStatus
        }
    }
```

Also update the `detectAndSetup` fallback (line 90-93) where `GitRepoStatus.empty` is used — no change needed since `empty` is updated in Step 1.

- [ ] **Step 3: Fix test compilation errors**

The existing tests don't construct `GitRepoStatus` directly (they only test `GitStatusParser.parse`), so no test changes needed. But verify by running the tests.

- [ ] **Step 4: Run tests**

Run: `cd /Users/aaronlin/works/codes/oss/poltertty && xcodebuild test -scheme Ghostty -destination 'platform=macOS' -only-testing:GhosttyTests/GitStatusMonitorTests 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Workspace/GitStatusMonitor.swift macos/Tests/Workspace/GitStatusMonitorTests.swift
git commit -m "feat(worktree): add isLinkedWorktree detection to GitStatusMonitor"
```

---

### Task 5: BottomStatusBarView — Worktree Badge

**Files:**
- Modify: `macos/Sources/Features/Workspace/BottomStatusBarView.swift`

- [ ] **Step 1: Add worktree badge to status bar**

In `BottomStatusBarView.swift`, inside the `if status.isGitRepo { ... }` block, add the badge before the branch name. Replace the existing git status HStack:

```swift
if status.isGitRepo {
    Text("|")
        .foregroundColor(.secondary)
    HStack(spacing: 4) {
        Image(systemName: "arrow.triangle.branch")
            .foregroundColor(status.isLinkedWorktree ? Color(hex: "#cba6f7") ?? .purple : .secondary)
        if status.isLinkedWorktree {
            Text(String(localized: "worktree"))
                .font(.system(size: 9))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill((Color(hex: "#cba6f7") ?? .purple).opacity(0.15))
                )
                .foregroundColor(Color(hex: "#cba6f7") ?? .purple)
        }
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
```

- [ ] **Step 2: Verify build compiles**

Run: `cd /Users/aaronlin/works/codes/oss/poltertty && xcodebuild build -scheme Ghostty -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/BottomStatusBarView.swift
git commit -m "feat(worktree): add worktree badge to bottom status bar"
```

---

### Task 6: TerminalController — Own GitWorktreeMonitor & Navigation Methods

**Files:**
- Modify: `macos/Sources/Features/Terminal/TerminalController.swift`

- [ ] **Step 1: Add worktreeMonitor property and initialize it**

In `TerminalController`, add the stored property near the other properties (around line 67):

```swift
/// Git worktree monitor for sidebar worktree list
let worktreeMonitor: GitWorktreeMonitor
```

In `init()`, before `super.init(ghostty, baseConfig: config, surfaceTree: tree)` (around line 103), add:

```swift
let wtRootDir = workspaceId
    .flatMap { WorkspaceManager.shared.workspace(for: $0) }?.rootDirExpanded
    ?? NSHomeDirectory()
self.worktreeMonitor = GitWorktreeMonitor(rootDir: wtRootDir)
```

- [ ] **Step 2: Add navigation methods**

Add these methods to `TerminalController` (near the existing `switchToWorkspace` method):

```swift
// MARK: - Worktree Navigation

func openNewTab(cdTo path: String) {
    guard let window = self.window else { return }
    var config = Ghostty.SurfaceConfiguration()
    config.workingDirectory = path
    config.workspaceId = self.workspaceId
    _ = TerminalController.newTab(ghostty, from: window, withBaseConfig: config)
}

func openNewWindow(cdTo path: String) {
    var config = Ghostty.SurfaceConfiguration()
    config.workingDirectory = path
    config.workspaceId = self.workspaceId
    let controller = TerminalController.newWindow(
        ghostty,
        withBaseConfig: config,
        withParent: self.window,
        workspaceId: self.workspaceId
    )
    controller.showWindow(self)
}
```

Note: `GitWorktreeMonitor.deinit` already cancels all DispatchSources, so explicit cleanup in `TerminalController` is not needed — when the controller is deallocated, the monitor is deallocated too, triggering `deinit`.

- [ ] **Step 3: Verify build compiles**

Run: `cd /Users/aaronlin/works/codes/oss/poltertty && xcodebuild build -scheme Ghostty -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Terminal/TerminalController.swift
git commit -m "feat(worktree): add GitWorktreeMonitor to TerminalController with navigation methods"
```

---

### Task 7: WorktreeListView — Sidebar Worktree Child List

**Files:**
- Create: `macos/Sources/Features/Workspace/WorktreeListView.swift`

- [ ] **Step 1: Create WorktreeListView**

```swift
// macos/Sources/Features/Workspace/WorktreeListView.swift
import SwiftUI

struct WorktreeListView: View {
    @ObservedObject var monitor: GitWorktreeMonitor
    let onOpenInTab: (String) -> Void
    let onOpenInWindow: (String) -> Void
    let onDelete: (String, Bool) -> Void  // path, force
    let onShowCreateForm: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(monitor.worktrees) { worktree in
                WorktreeRow(
                    worktree: worktree,
                    onOpenInTab: onOpenInTab,
                    onOpenInWindow: onOpenInWindow,
                    onDelete: onDelete
                )
            }

            // + Add Worktree button
            Button(action: onShowCreateForm) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 9))
                    Text(String(localized: "Add Worktree"))
                        .font(.system(size: 10))
                }
                .foregroundColor(.secondary.opacity(0.6))
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 16)
    }
}

// MARK: - Worktree Row

private struct WorktreeRow: View {
    let worktree: GitWorktree
    let onOpenInTab: (String) -> Void
    let onOpenInWindow: (String) -> Void
    let onDelete: (String, Bool) -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10))
                .foregroundColor(worktree.isCurrent ? .accentColor : .secondary)
            Text(worktree.branch ?? "detached")
                .font(.system(size: 11, weight: worktree.isCurrent ? .medium : .regular))
                .foregroundColor(worktree.isCurrent ? .primary : .secondary)
                .lineLimit(1)
            Spacer()
            if worktree.isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(worktree.isCurrent
                    ? Color.accentColor.opacity(0.05)
                    : (isHovering ? Color.primary.opacity(0.04) : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpenInWindow(worktree.path) }
        .onTapGesture { onOpenInTab(worktree.path) }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(String(localized: "Open in New Tab")) { onOpenInTab(worktree.path) }
            Button(String(localized: "Open in New Window")) { onOpenInWindow(worktree.path) }
            if !worktree.isMain && !worktree.isCurrent {
                Divider()
                Button(String(localized: "Delete Worktree"), role: .destructive) {
                    onDelete(worktree.path, false)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Verify build compiles**

Run: `cd /Users/aaronlin/works/codes/oss/poltertty && xcodebuild build -scheme Ghostty -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/WorktreeListView.swift
git commit -m "feat(worktree): add WorktreeListView for sidebar worktree child list"
```

---

### Task 8: WorktreeCreateForm — Create Worktree Sheet

**Files:**
- Create: `macos/Sources/Features/Workspace/WorktreeCreateForm.swift`

Note: This file name conflicts with `WorkspaceCreateForm.swift`. Name it `WorktreeCreateForm.swift` to be distinct.

- [ ] **Step 1: Create the form view**

```swift
// macos/Sources/Features/Workspace/WorktreeCreateForm.swift
import SwiftUI

struct WorktreeCreateForm: View {
    @ObservedObject var monitor: GitWorktreeMonitor
    let onDismiss: () -> Void

    @State private var branchName = ""
    @State private var path = ""
    @State private var createNewBranch = true
    @State private var selectedExistingBranch: String?
    @State private var baseBranch: String?
    @State private var availableBranches: [String] = []
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    private var currentBranch: String? {
        monitor.worktrees.first(where: { $0.isCurrent })?.branch
    }

    private var autoPath: String {
        let name = createNewBranch ? branchName : (selectedExistingBranch ?? "")
        return ".worktrees/" + name.replacingOccurrences(of: "/", with: "-")
    }

    private var effectivePath: String {
        path.isEmpty ? autoPath : path
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(String(localized: "Add Worktree"))
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 20)
                .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 12) {
                // Create new branch toggle
                Toggle(isOn: $createNewBranch) {
                    Text("Create new branch")
                        .font(.system(size: 12, weight: .medium))
                }
                .toggleStyle(.checkbox)

                // Branch name / picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Branch")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    if createNewBranch {
                        TextField("feature/my-feature", text: $branchName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                    } else {
                        Picker("", selection: $selectedExistingBranch) {
                            Text("Select a branch").tag(nil as String?)
                            ForEach(availableBranches, id: \.self) { branch in
                                Text(branch).tag(branch as String?)
                            }
                        }
                        .labelsHidden()
                    }
                }

                // Path
                VStack(alignment: .leading, spacing: 4) {
                    Text("Path")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField(autoPath, text: $path)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                    Text("Relative to repo root. Leave empty for default.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.6))
                }

                // Base branch (only for new branches)
                if createNewBranch {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Base branch")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Picker("", selection: $baseBranch) {
                            Text(currentBranch ?? "HEAD").tag(nil as String?)
                            ForEach(availableBranches, id: \.self) { branch in
                                Text(branch).tag(branch as String?)
                            }
                        }
                        .labelsHidden()
                    }
                }

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 20)

            // Buttons
            HStack {
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSubmitDisabled)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 380)
        .onAppear {
            availableBranches = monitor.listBranches()
            baseBranch = nil
        }
    }

    private var isSubmitDisabled: Bool {
        if isSubmitting { return true }
        if createNewBranch { return branchName.trimmingCharacters(in: .whitespaces).isEmpty }
        return selectedExistingBranch == nil
    }

    private func submit() {
        errorMessage = nil
        isSubmitting = true

        let branch = createNewBranch ? branchName : (selectedExistingBranch ?? "")
        let targetPath = effectivePath

        // Path validation
        if let gitRoot = monitor.worktrees.first?.path {
            let absPath = targetPath.hasPrefix("/")
                ? targetPath
                : URL(fileURLWithPath: gitRoot).appendingPathComponent(targetPath).path
            if FileManager.default.fileExists(atPath: absPath) {
                errorMessage = String(localized: "Directory already exists")
                isSubmitting = false
                return
            }
        }

        DispatchQueue.global().async {
            do {
                try monitor.addWorktree(
                    branch: branch,
                    path: targetPath,
                    baseBranch: baseBranch,
                    createNew: createNewBranch
                )
                DispatchQueue.main.async {
                    isSubmitting = false
                    onDismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }
}
```

- [ ] **Step 2: Verify build compiles**

Run: `cd /Users/aaronlin/works/codes/oss/poltertty && xcodebuild build -scheme Ghostty -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/WorktreeCreateForm.swift
git commit -m "feat(worktree): add WorktreeCreateForm sheet for creating worktrees"
```

---

### Task 9: Sidebar Integration — Embed Worktree List & Delete Confirmation

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceSidebar.swift`

- [ ] **Step 1: Add new parameters to WorkspaceSidebar**

Add these properties to the `WorkspaceSidebar` struct (after the existing `onLaunchAgent` property, around line 14). Use default values so existing call sites don't break until Task 10 wires them up:

```swift
var worktreeMonitor: GitWorktreeMonitor? = nil
var onOpenWorktreeInTab: ((String) -> Void)? = nil
var onOpenWorktreeInWindow: ((String) -> Void)? = nil
```

Add state properties for the worktree create form and delete confirmation:

```swift
@State private var showWorktreeCreateForm = false
@State private var worktreeExpanded = true
@State private var pendingDeleteWorktreePath: String?
@State private var pendingDeleteDirtyCount: Int = 0
@State private var showDeleteWorktreeAlert = false
```

- [ ] **Step 2: Add worktree list to expanded content**

In `expandedContent`, after each `ExpandedWorkspaceItem` in the ungrouped and grouped sections, add the worktree list conditionally. Find the `ungroupedSection` computed property and wrap each `ExpandedWorkspaceItem` — after the item, add:

```swift
// After each ExpandedWorkspaceItem, conditionally show worktree list
if workspace.id == currentWorkspaceId,
   let monitor = worktreeMonitor,
   monitor.worktrees.count > 1 {
    DisclosureGroup(isExpanded: $worktreeExpanded) {
        WorktreeListView(
            monitor: monitor,
            onOpenInTab: { path in onOpenWorktreeInTab?(path) },
            onOpenInWindow: { path in onOpenWorktreeInWindow?(path) },
            onDelete: { path, _ in confirmDeleteWorktree(path: path, monitor: monitor) },
            onShowCreateForm: { showWorktreeCreateForm = true }
        )
    } label: {
        HStack(spacing: 4) {
            Text("\(monitor.worktrees.count) worktrees")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(3)
        }
    }
    .padding(.leading, 14)
    .padding(.trailing, 6)
}
```

- [ ] **Step 3: Add worktree submenu to collapsed context menu**

In `CollapsedWorkspaceIcon`, add optional parameters with defaults (so existing call sites don't break):

```swift
var worktreeMonitor: GitWorktreeMonitor? = nil
var onOpenWorktreeInTab: ((String) -> Void)? = nil
var onOpenWorktreeInWindow: ((String) -> Void)? = nil
var onDeleteWorktree: ((String) -> Void)? = nil
```

Then add this to its `.contextMenu`, before the existing "Edit Workspace..." button:

```swift
if let monitor = worktreeMonitor, monitor.worktrees.count > 1 {
    Menu("Worktrees") {
        ForEach(monitor.worktrees) { wt in
            Menu(wt.branch ?? "detached") {
                Button(String(localized: "Open in New Tab")) { onOpenWorktreeInTab?(wt.path) }
                Button(String(localized: "Open in New Window")) { onOpenWorktreeInWindow?(wt.path) }
                if !wt.isMain && !wt.isCurrent {
                    Divider()
                    Button(String(localized: "Delete Worktree"), role: .destructive) {
                        onDeleteWorktree?(wt.path)
                    }
                }
            }
        }
    }
    Divider()
}
```

In `WorkspaceSidebar`, when constructing `CollapsedWorkspaceIcon` for the current workspace, pass the worktree params:

```swift
// Only for current workspace's collapsed icon
if workspace.id == currentWorkspaceId {
    CollapsedWorkspaceIcon(
        // ... existing params ...
        worktreeMonitor: worktreeMonitor,
        onOpenWorktreeInTab: onOpenWorktreeInTab,
        onOpenWorktreeInWindow: onOpenWorktreeInWindow,
        onDeleteWorktree: { path in
            if let monitor = worktreeMonitor {
                confirmDeleteWorktree(path: path, monitor: monitor)
            }
        }
    )
}
```

- [ ] **Step 4: Add delete confirmation and create form sheet**

Add a helper method and modifiers to `WorkspaceSidebar`:

```swift
private func confirmDeleteWorktree(path: String, monitor: GitWorktreeMonitor) {
    pendingDeleteWorktreePath = path
    // Run git status on background thread to avoid blocking UI
    DispatchQueue.global().async {
        let count = monitor.dirtyFileCount(at: path)
        DispatchQueue.main.async {
            pendingDeleteDirtyCount = count
            showDeleteWorktreeAlert = true
        }
    }
}
```

Add these modifiers to the `WorkspaceSidebar` body (after existing `.alert` modifiers):

```swift
.alert(
    String(localized: "worktree.delete.title \(pendingDeleteWorktreePath?.components(separatedBy: "/").last ?? "")"),
    isPresented: $showDeleteWorktreeAlert
) {
    Button(String(localized: "Cancel"), role: .cancel) {
        pendingDeleteWorktreePath = nil
    }
    Button(
        pendingDeleteDirtyCount > 0
            ? String(localized: "Force Delete")
            : String(localized: "Delete"),
        role: .destructive
    ) {
        if let path = pendingDeleteWorktreePath, let monitor = worktreeMonitor {
            try? monitor.removeWorktree(path: path, force: pendingDeleteDirtyCount > 0)
        }
        pendingDeleteWorktreePath = nil
    }
} message: {
    if let path = pendingDeleteWorktreePath {
        Text(path)
        if pendingDeleteDirtyCount > 0 {
            Text("⚠ \(pendingDeleteDirtyCount) uncommitted changes will be lost")
        }
    }
}
.sheet(isPresented: $showWorktreeCreateForm) {
    if let monitor = worktreeMonitor {
        WorktreeCreateForm(monitor: monitor, onDismiss: { showWorktreeCreateForm = false })
    }
}
```

Note: All user-facing strings use `String(localized:)` with the literal English string as the key (matching the existing codebase pattern in `WorkspaceSidebar.swift`). The spec's key-based format (`"worktree.badge"`) is for documentation reference only.

- [ ] **Step 5: Update all call sites of WorkspaceSidebar and CollapsedWorkspaceIcon**

No changes needed — all new parameters have default values (`= nil`), so existing call sites compile without modification. Task 10 will wire up the actual values.

- [ ] **Step 6: Verify build compiles**

Run: `cd /Users/aaronlin/works/codes/oss/poltertty && xcodebuild build -scheme Ghostty -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceSidebar.swift
git commit -m "feat(worktree): integrate worktree list and delete confirmation into sidebar"
```

---

### Task 10: PolterttyRootView & TerminalController — Wire Up Callbacks

**Files:**
- Modify: `macos/Sources/Features/Workspace/PolterttyRootView.swift`
- Modify: `macos/Sources/Features/Terminal/TerminalController.swift`

- [ ] **Step 1: Add worktree parameters to PolterttyRootView**

Add stored properties with defaults:

```swift
var worktreeMonitor: GitWorktreeMonitor? = nil
var onOpenWorktreeInTab: ((String) -> Void)? = nil
var onOpenWorktreeInWindow: ((String) -> Void)? = nil
```

**Important:** `PolterttyRootView` has a custom `init` (line 58-109). Add the new parameters to the `init` signature with default values, and assign them in the body:

```swift
init(
    // ... existing params ...,
    worktreeMonitor: GitWorktreeMonitor? = nil,
    onOpenWorktreeInTab: ((String) -> Void)? = nil,
    onOpenWorktreeInWindow: ((String) -> Void)? = nil
) {
    // ... existing assignments ...
    self.worktreeMonitor = worktreeMonitor
    self.onOpenWorktreeInTab = onOpenWorktreeInTab
    self.onOpenWorktreeInWindow = onOpenWorktreeInWindow
}
```

Then pass them through to `WorkspaceSidebar` in the body:

```swift
WorkspaceSidebar(
    // ... existing params ...
    worktreeMonitor: worktreeMonitor,
    onOpenWorktreeInTab: onOpenWorktreeInTab,
    onOpenWorktreeInWindow: onOpenWorktreeInWindow
)
```

- [ ] **Step 2: Update TerminalController.windowDidLoad call site**

In `TerminalController.windowDidLoad()`, update the `PolterttyRootView` initialization (around line 1551) to pass the new parameters:

```swift
PolterttyRootView(
    // ... existing params ...
    worktreeMonitor: self.worktreeMonitor,
    onOpenWorktreeInTab: { [weak self] path in
        self?.openNewTab(cdTo: path)
    },
    onOpenWorktreeInWindow: { [weak self] path in
        self?.openNewWindow(cdTo: path)
    }
)
```

- [ ] **Step 3: Verify build compiles**

Run: `cd /Users/aaronlin/works/codes/oss/poltertty && xcodebuild build -scheme Ghostty -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Run full test suite**

Run: `cd /Users/aaronlin/works/codes/oss/poltertty && xcodebuild test -scheme Ghostty -destination 'platform=macOS' 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Workspace/PolterttyRootView.swift macos/Sources/Features/Terminal/TerminalController.swift
git commit -m "feat(worktree): wire up worktree callbacks through PolterttyRootView to TerminalController"
```
