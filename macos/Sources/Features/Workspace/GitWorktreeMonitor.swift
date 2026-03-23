// macos/Sources/Features/Workspace/GitWorktreeMonitor.swift
import Foundation

// MARK: - Data Model

struct GitWorktree: Identifiable, Equatable {
    let id: UUID
    let path: String        // absolute path to the worktree
    let branch: String?     // nil when HEAD is detached
    let isMain: Bool        // true for the primary worktree
    let isCurrent: Bool     // true when this worktree matches the monitor's rootDir
    let exists: Bool        // true when the worktree directory exists on disk
}

// MARK: - Porcelain Parser

enum GitWorktreeParser {
    /// Parse `git worktree list --porcelain` output into GitWorktree array.
    static func parse(porcelain: String, currentPath: String) -> [GitWorktree] {
        let normalizedCurrent = URL(fileURLWithPath: currentPath).standardized.path
        var worktrees: [GitWorktree] = []
        var isFirst = true

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
                isCurrent: normalizedPath == normalizedCurrent,
                exists: FileManager.default.fileExists(atPath: normalizedPath)
            ))
            isFirst = false
        }

        return worktrees
    }
}

// MARK: - Monitor

final class GitWorktreeMonitor: ObservableObject {
    @Published var worktrees: [GitWorktree] = []
    @Published var isGitRepo: Bool = false

    private let rootDir: String
    private var gitRoot: String?
    private var gitCommonDir: String?
    private let queue = DispatchQueue(label: "poltertty.git-worktree-monitor")

    private var dotGitSource: DispatchSourceFileSystemObject?
    private var worktreesSource: DispatchSourceFileSystemObject?
    private var worktreeDirSources: [String: DispatchSourceFileSystemObject] = [:]
    // 监听各 worktree 的父目录，检测 worktree 增删（比个别目录的 .delete 更可靠）
    private var worktreeParentSources: [String: DispatchSourceFileSystemObject] = [:]
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
        worktreeDirSources.values.forEach { $0.cancel() }
        worktreeParentSources.values.forEach { $0.cancel() }
        debounceWork?.cancel()
    }

    // MARK: - Git Detection

    private func detectAndSetup() {
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

        let commonDirResult = runGit(["-C", rootDir, "rev-parse", "--git-common-dir"])
        if commonDirResult.exitCode == 0,
           let commonDir = commonDirResult.output?.trimmingCharacters(in: .whitespacesAndNewlines),
           !commonDir.isEmpty {
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
        updateWorktreeDirWatchers(for: parsed)
        DispatchQueue.main.async { [weak self] in
            self?.worktrees = parsed
        }
    }

    // 监听各 worktree 目录的删除事件，使手动删除目录时侧边栏能实时更新
    private func updateWorktreeDirWatchers(for worktrees: [GitWorktree]) {
        let nonMainWorktrees = worktrees.filter { $0.exists && !$0.isMain }
        let activePaths = Set(nonMainWorktrees.map { $0.path })
        let watchedPaths = Set(worktreeDirSources.keys)

        for path in watchedPaths.subtracting(activePaths) {
            worktreeDirSources[path]?.cancel()
            worktreeDirSources.removeValue(forKey: path)
        }

        for path in activePaths.subtracting(watchedPaths) {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: .delete, queue: queue
            )
            source.setEventHandler { [weak self] in
                self?.scheduleRefresh()
            }
            source.setCancelHandler { close(fd) }
            worktreeDirSources[path] = source
            source.resume()
        }

        // 监听各 worktree 的父目录，检测增删（link count 变化比 .delete 事件更可靠）
        updateWorktreeParentWatchers(parentPaths: Set(nonMainWorktrees.map {
            URL(fileURLWithPath: $0.path).deletingLastPathComponent().path
        }))
    }

    // 监听 worktree 父目录的 .write/.link 事件；父目录中有 worktree 增删时 link count 变化
    private func updateWorktreeParentWatchers(parentPaths: Set<String>) {
        let watchedPaths = Set(worktreeParentSources.keys)

        for path in watchedPaths.subtracting(parentPaths) {
            worktreeParentSources[path]?.cancel()
            worktreeParentSources.removeValue(forKey: path)
        }

        for path in parentPaths.subtracting(watchedPaths) {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .link], queue: queue
            )
            source.setEventHandler { [weak self] in
                self?.scheduleRefresh()
            }
            source.setCancelHandler { close(fd) }
            worktreeParentSources[path] = source
            source.resume()
        }
    }

    // MARK: - Filesystem Watching

    private func setupWatching() {
        guard let gitDir = gitCommonDir else { return }
        startDotGitSource(gitDir: gitDir)
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
            fileDescriptor: fd, eventMask: [.write, .link], queue: queue
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
            fileDescriptor: fd, eventMask: [.write, .link], queue: queue
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
        worktreeDirSources.values.forEach { $0.cancel() }
        worktreeDirSources.removeAll()
        worktreeParentSources.values.forEach { $0.cancel() }
        worktreeParentSources.removeAll()
        debounceWork?.cancel()
        debounceWork = nil
    }

    // MARK: - Worktree Operations

    func addWorktree(branch: String, path: String, baseBranch: String?, createNew: Bool) throws {
        guard let root = gitRoot else {
            throw WorktreeError.notGitRepo
        }
        var args = ["-C", root, "worktree", "add"]
        if createNew {
            args += ["-b", branch]
        }
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
    }

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
        // 应用内删除：主动触发刷新，不依赖文件系统事件
        queue.async { [weak self] in self?.scheduleRefresh() }
    }

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
