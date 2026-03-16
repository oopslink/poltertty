import Foundation
import Combine

/// Represents a single git worktree
struct GitWorktree: Identifiable, Equatable {
    let id: UUID
    let path: String      // absolute path to the worktree
    let branch: String?   // nil when HEAD is detached
    let isMain: Bool      // true for the primary worktree
    let isCurrent: Bool   // true when this worktree is the monitor's rootDir
}

/// Monitors git worktrees for a repository and watches for filesystem changes
class GitWorktreeMonitor: ObservableObject {
    @Published var worktrees: [GitWorktree] = []
    @Published var isGitRepo: Bool = false

    private var rootDir: String
    private(set) var gitRoot: String?

    // Filesystem watching
    private var gitDirSource: DispatchSourceFileSystemObject?
    private var worktreesSource: DispatchSourceFileSystemObject?
    private var gitDirFd: Int32?
    private var worktreesFd: Int32?
    private var debounceWorkItem: DispatchWorkItem?

    init(rootDir: String) {
        self.rootDir = rootDir
        refresh()
        setupWatching()
    }

    deinit {
        stopWatching()
    }

    /// Reserved for future rootDir-editing feature
    func updateRootDir(_ path: String) {
        stopWatching()
        rootDir = path
        gitRoot = nil
        worktrees = []
        isGitRepo = false
        refresh()
        setupWatching()
    }

    // MARK: - Git Detection & Parsing

    private func refresh() {
        detectGitRepo()
        if isGitRepo {
            parseWorktrees()
        }
    }

    private func detectGitRepo() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "--show-toplevel"]
        process.currentDirectoryURL = URL(fileURLWithPath: rootDir)
        process.environment = ["HOME": NSHomeDirectory()]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !output.isEmpty {
                    gitRoot = output
                    isGitRepo = true
                    return
                }
            }
        } catch {
            NSLog("GitWorktreeMonitor: Failed to detect git repo: \(error)")
        }

        isGitRepo = false
        gitRoot = nil
    }

    private func parseWorktrees() {
        guard let gitRoot = gitRoot else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["worktree", "list", "--porcelain"]
        process.currentDirectoryURL = URL(fileURLWithPath: gitRoot)
        process.environment = ["HOME": NSHomeDirectory()]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let parsed = parseWorktreeList(output)
                    DispatchQueue.main.async { [weak self] in
                        self?.worktrees = parsed
                    }
                    return
                }
            }

            NSLog("GitWorktreeMonitor: git worktree list failed with exit code \(process.terminationStatus)")
        } catch {
            NSLog("GitWorktreeMonitor: Failed to parse worktrees: \(error)")
        }
    }

    private func parseWorktreeList(_ output: String) -> [GitWorktree] {
        var result: [GitWorktree] = []
        var currentPath: String?
        var currentBranch: String?
        var currentIsMain = false

        let normalizedRootDir = URL(fileURLWithPath: rootDir).standardized.path

        for line in output.components(separatedBy: .newlines) {
            if line.isEmpty {
                // End of current worktree entry
                if let path = currentPath {
                    let normalizedPath = URL(fileURLWithPath: path).standardized.path
                    let isCurrent = normalizedPath == normalizedRootDir

                    result.append(GitWorktree(
                        id: UUID(),
                        path: path,
                        branch: currentBranch,
                        isMain: currentIsMain,
                        isCurrent: isCurrent
                    ))
                }
                currentPath = nil
                currentBranch = nil
                currentIsMain = false
            } else if line.hasPrefix("worktree ") {
                currentPath = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("branch ") {
                currentBranch = String(line.dropFirst("branch ".count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "refs/heads/"))
            } else if line == "bare" {
                currentIsMain = true
            } else if line.hasPrefix("HEAD ") {
                // Detached HEAD - branch remains nil
                currentIsMain = currentPath == gitRoot
            }
        }

        // Handle last entry if no trailing newline
        if let path = currentPath {
            let normalizedPath = URL(fileURLWithPath: path).standardized.path
            let isCurrent = normalizedPath == normalizedRootDir

            result.append(GitWorktree(
                id: UUID(),
                path: path,
                branch: currentBranch,
                isMain: currentIsMain,
                isCurrent: isCurrent
            ))
        }

        return result
    }

    // MARK: - Filesystem Watching

    private func setupWatching() {
        guard let gitRoot = gitRoot, isGitRepo else { return }

        let gitDirPath = gitRoot + "/.git"
        let worktreesDirPath = gitDirPath + "/worktrees"

        // Setup .git directory watcher
        setupGitDirWatcher(path: gitDirPath)

        // Setup .git/worktrees watcher if it exists
        if FileManager.default.fileExists(atPath: worktreesDirPath) {
            setupWorktreesWatcher(path: worktreesDirPath)
        }
    }

    private func setupGitDirWatcher(path: String) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("GitWorktreeMonitor: Failed to open .git directory")
            return
        }

        gitDirFd = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: DispatchQueue.global()
        )

        source.setEventHandler { [weak self] in
            self?.handleGitDirEvent()
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.gitDirFd {
                close(fd)
                self?.gitDirFd = nil
            }
        }

        gitDirSource = source
        source.resume()
    }

    private func setupWorktreesWatcher(path: String) {
        // Prevent duplicate sources
        guard worktreesSource == nil else { return }

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("GitWorktreeMonitor: Failed to open .git/worktrees directory")
            return
        }

        worktreesFd = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: DispatchQueue.global()
        )

        source.setEventHandler { [weak self] in
            self?.handleWorktreesEvent()
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.worktreesFd {
                close(fd)
                self?.worktreesFd = nil
            }
        }

        worktreesSource = source
        source.resume()
    }

    private func handleGitDirEvent() {
        guard let gitRoot = gitRoot else { return }
        let worktreesDirPath = gitRoot + "/.git/worktrees"
        let worktreesExists = FileManager.default.fileExists(atPath: worktreesDirPath)

        // Start worktrees watcher if directory was created
        if worktreesExists && worktreesSource == nil {
            setupWorktreesWatcher(path: worktreesDirPath)
        }

        // Stop worktrees watcher if directory was deleted
        if !worktreesExists && worktreesSource != nil {
            worktreesSource?.cancel()
            worktreesSource = nil
        }

        scheduleRefresh()
    }

    private func handleWorktreesEvent() {
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        // Cancel existing debounce
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.refresh()
        }

        debounceWorkItem = workItem
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func stopWatching() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        gitDirSource?.cancel()
        gitDirSource = nil

        worktreesSource?.cancel()
        worktreesSource = nil
    }
}
