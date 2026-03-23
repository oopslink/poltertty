// macos/Sources/Features/Workspace/GitStatusMonitor.swift

import Foundation

// MARK: - Data Model

/// 仓库级 Git 状态（用于底部状态栏展示）
/// 与 FileBrowser 的 GitStatus（per-file 状态）不同，此结构体描述整个仓库的聚合状态
struct GitRepoStatus: Equatable {
    let branch: String?   // nil = detached HEAD
    let added: Int        // untracked (??) + staged new (A)
    let modified: Int     // staged modified (M?) + unstaged modified (?M)
    let isGitRepo: Bool
    let isLinkedWorktree: Bool

    static let empty = GitRepoStatus(branch: nil, added: 0, modified: 0, isGitRepo: false, isLinkedWorktree: false)
}

// MARK: - Typealias for task compatibility
// 任务规范中使用 GitStatus，但模块内已有同名 enum，使用 GitRepoStatus 替代

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

// MARK: - Monitor

final class GitStatusMonitor: ObservableObject {
    @Published var status: GitRepoStatus = .empty

    private let queue = DispatchQueue(label: "poltertty.git-status-monitor")
    private var currentPwd: String
    private var gitRoot: String?
    private var headSource: DispatchSourceFileSystemObject?
    private var indexSource: DispatchSourceFileSystemObject?
    private var debounceWork: DispatchWorkItem?

    // MARK: - Foreground process polling
    // shellPid 必须在 MainActor 上赋值（来自 SwiftUI onReceive）。
    // timer 操作全部派发到 queue，确保线程安全。
    var shellPid: pid_t = 0 {
        didSet {
            guard shellPid != oldValue else { return }
            let pid = shellPid
            queue.async { [weak self] in
                guard let self else { return }
                if pid == 0 { self.stopPwdPolling() } else { self.startPwdPolling(pid: pid) }
            }
        }
    }
    private var pwdPollTimer: DispatchSourceTimer?  // accessed only on queue
    private var pollingPid: pid_t = 0              // queue 侧的 shellPid 副本

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
        pwdPollTimer?.cancel()
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

        // 获取实际的 git dir。对于 linked worktree，--git-dir 返回绝对路径
        // （如 /repo/.git/worktrees/feature）；对于主 worktree 返回 ".git"（相对路径）
        let gitDirResult = runGit(["-C", root, "rev-parse", "--git-dir"])
        let gitDir: String
        if let dir = gitDirResult.output?.trimmingCharacters(in: .whitespacesAndNewlines),
           !dir.isEmpty {
            gitDir = dir.hasPrefix("/") ? dir : "\(root)/\(dir)"
        } else {
            gitDir = "\(root)/.git"
        }

        setupWatching(gitDir: gitDir)
        refresh()
    }

    private func setupWatching(gitDir: String) {
        startSource(path: "\(gitDir)/HEAD", store: &headSource)
        startSource(path: "\(gitDir)/index", store: &indexSource)
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
            eventMask: [.write, .rename, .delete],
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

    private func stopWatching() {
        headSource?.cancel()
        headSource = nil
        indexSource?.cancel()
        indexSource = nil
        debounceWork?.cancel()
        debounceWork = nil
        gitRoot = nil
    }

    // MARK: - Polling（在 queue 上执行）

    private func startPwdPolling(pid: pid_t) {
        stopPwdPolling()
        pollingPid = pid
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2.0, repeating: 2.0, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            guard let self, self.pollingPid > 0 else { return }
            guard let newCwd = ProcessTreeCwd.foregroundCwd(shellPid: self.pollingPid),
                  newCwd != self.currentPwd else { return }
            self.updatePwd(newCwd)
        }
        pwdPollTimer = timer
        timer.resume()
    }

    private func stopPwdPolling() {
        pwdPollTimer?.cancel()
        pwdPollTimer = nil
        pollingPid = 0
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
