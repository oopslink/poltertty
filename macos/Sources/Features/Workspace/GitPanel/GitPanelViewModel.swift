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
    @Published var isVisible = false  // Git panel 显隐

    private(set) var repo: GitRepository?
    private var headSource: DispatchSourceFileSystemObject?
    private var indexSource: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "poltertty.git-panel-vm")

    init() {}

    func load(rootDir: String) async {
        guard !rootDir.isEmpty else { return }
        isLoading = true
        error = nil
        do {
            let newRepo = try GitRepository(path: rootDir)
            repo = newRepo
            isGitRepo = true
            await refresh()
            setupWatching(gitDir: await newRepo.gitDir)
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
        source.setEventHandler {
            Task { [weak self] in await self?.refresh() }
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
