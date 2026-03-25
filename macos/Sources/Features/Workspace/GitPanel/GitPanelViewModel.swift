// macos/Sources/Features/Workspace/GitPanel/GitPanelViewModel.swift
import Foundation
import SwiftUI

@MainActor
class GitPanelViewModel: ObservableObject {
    // 状态栏数据
    @Published var branch: String?
    var changedCount: Int { stagedFiles.count + unstagedFiles.count }

    // Changes 区
    @Published var stagedFiles: [GitChange] = []
    @Published var unstagedFiles: [GitChange] = []

    // Commits 区（v1 固定 100 条）
    @Published var commits: [GitCommit] = []
    @Published var expandedCommits: Set<String> = []
    @Published var commitFiles: [String: [GitCommitFile]] = [:]  // oid → files

    // Diff 显示
    @Published var selectedDiff: GitFileDiff?

    @Published var isLoading = false
    @Published var error: String?
    @Published var isGitRepo = false
    @Published var gitPanelWidth: CGFloat
    @Published var lastAttemptedDir: String = ""

    private(set) var repo: GitRepository?

    // nonisolated(unsafe) 保证 deinit 可以安全访问（H-1 修复）
    nonisolated(unsafe) private var headSource: DispatchSourceFileSystemObject?
    nonisolated(unsafe) private var indexSource: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "poltertty.git-panel-vm")
    private var pendingRefreshTask: Task<Void, Never>?
    private var currentGitDir: String?

    init(gitPanelWidth: CGFloat = 600) {
        self.gitPanelWidth = gitPanelWidth
    }

    func load(rootDir: String) async {
        guard !rootDir.isEmpty else { return }
        lastAttemptedDir = rootDir
        isLoading = true
        error = nil
        do {
            let newRepo = try GitRepository(path: rootDir)
            repo = newRepo
            isGitRepo = true
            await refresh()
            if let gitDir = await newRepo.gitDir {
                currentGitDir = gitDir
                setupWatching(gitDir: gitDir)
            }
        } catch {
            isGitRepo = false
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func refresh() async {
        guard let repo = repo else { return }
        do {
            async let branchTask = repo.currentBranch()
            async let statusTask = repo.status()
            async let commitsTask = repo.log()
            let (b, changes, logs) = try await (branchTask, statusTask, commitsTask)
            branch = b
            stagedFiles = changes.filter { $0.isStaged }
            unstagedFiles = changes.filter { !$0.isStaged }
            commits = logs
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stage(_ change: GitChange) async {
        guard let repo = repo else { return }
        do {
            try await repo.stage(paths: [change.path])
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func unstage(_ change: GitChange) async {
        guard let repo = repo else { return }
        do {
            try await repo.unstage(paths: [change.path])
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func discard(_ change: GitChange) async {
        guard let repo = repo else { return }
        do {
            try await repo.discard(paths: [change.path])
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func expandCommit(_ commit: GitCommit) async {
        if expandedCommits.contains(commit.id) {
            expandedCommits.remove(commit.id)
            return
        }
        expandedCommits.insert(commit.id)
        guard commitFiles[commit.id] == nil, let repo = repo else { return }
        do {
            commitFiles[commit.id] = try await repo.commitDiff(oid: commit.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func selectCommitFile(_ file: GitCommitFile, oid: String) async {
        guard let repo = repo else { return }
        do {
            selectedDiff = try await repo.fileDiff(oid: oid, path: file.path)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func selectWorkingFile(_ change: GitChange) async {
        guard let repo = repo else { return }
        do {
            selectedDiff = try await repo.workingDiff(path: change.path, staged: change.isStaged)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - DispatchSource watching

    private func setupWatching(gitDir: String) {
        stopWatching()
        startSource(path: "\(gitDir)HEAD", store: &headSource)
        startSource(path: "\(gitDir)index", store: &indexSource)
    }

    private func startSource(path: String, store: inout DispatchSourceFileSystemObject?) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue
        )
        source.setEventHandler { [weak self] in
            let data = source.data
            // H-3 修复：文件被删除/重命名后 fd 失效，需要重建监听
            if data.contains(.delete) || data.contains(.rename) {
                // M-5 修复：防抖 200ms，避免高频 git 操作导致大量并发刷新
                self?.pendingRefreshTask?.cancel()
                self?.pendingRefreshTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    if let gitDir = await self?.currentGitDir {
                        await self?.setupWatching(gitDir: gitDir)
                    }
                    await self?.refresh()
                }
            } else {
                self?.pendingRefreshTask?.cancel()
                self?.pendingRefreshTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard !Task.isCancelled else { return }
                    await self?.refresh()
                }
            }
        }
        source.setCancelHandler { close(fd) }
        store = source
        source.resume()
    }

    private func stopWatching() {
        headSource?.cancel(); headSource = nil
        indexSource?.cancel(); indexSource = nil
    }

    deinit {
        headSource?.cancel()
        indexSource?.cancel()
    }
}
