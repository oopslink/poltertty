// macos/Sources/GitKit/GitRepository.swift
import Foundation

actor GitRepository {
    private var repo: OpaquePointer?  // git_repository*
    private let rootDir: String

    // 初始化：传入任意工作目录路径，自动 discover git root
    // 非 git repo 时 throw GitError.notARepository
    init(path: String) throws {
        var repoPtr: OpaquePointer?
        let code = git_repository_open_ext(&repoPtr, path, 0, nil)
        guard code == 0, let ptr = repoPtr else {
            throw GitError.notARepository
        }
        self.repo = ptr
        // 获取 workdir（linked worktree 下也是正确的 workdir）
        if let workdir = git_repository_workdir(ptr) {
            var dir = String(cString: workdir)
            if dir.hasSuffix("/") { dir = String(dir.dropLast()) }
            self.rootDir = dir
        } else {
            git_repository_free(ptr)
            throw GitError.notARepository
        }
    }

    deinit {
        if let r = repo { git_repository_free(r) }
    }

    // git dir 路径（供 ViewModel 用于 DispatchSource 监听）
    var gitDir: String {
        guard let r = repo,
              let gitdir = git_repository_path(r) else { return "" }
        return String(cString: gitdir)
    }

    // MARK: - Branch

    func currentBranch() throws -> String? {
        guard let r = repo else { return nil }
        var ref: OpaquePointer?
        let code = git_repository_head(&ref, r)
        defer { git_reference_free(ref) }
        guard code == 0, let ref = ref else {
            if code == GIT_EUNBORNBRANCH.rawValue || code == GIT_EDETACHED.rawValue {
                return nil // detached HEAD
            }
            throw GitError.fromLibgit2(code)
        }
        if let name = git_reference_shorthand(ref) {
            return String(cString: name)
        }
        return nil
    }

    // MARK: - Status

    func status() throws -> [GitChange] {
        guard let r = repo else { return [] }
        var statusList: OpaquePointer?
        var opts = git_status_options()
        git_status_options_init(&opts, UInt32(GIT_STATUS_OPTIONS_VERSION))
        opts.show = GIT_STATUS_SHOW_INDEX_AND_WORKDIR
        opts.flags = UInt32(
            GIT_STATUS_OPT_INCLUDE_UNTRACKED.rawValue |
            GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS.rawValue
        )
        let code = git_status_list_new(&statusList, r, &opts)
        guard code == 0, let list = statusList else {
            throw GitError.fromLibgit2(code)
        }
        defer { git_status_list_free(list) }

        var changes: [GitChange] = []
        let count = git_status_list_entrycount(list)
        for i in 0..<count {
            guard let entry = git_status_byindex(list, i) else { continue }
            let flags = entry.pointee.status.rawValue
            let path = entry.pointee.head_to_index?.pointee.new_file.path
                ?? entry.pointee.index_to_workdir?.pointee.new_file.path
            guard let rawPath = path else { continue }
            let filePath = String(cString: rawPath)

            // Staged changes (index vs HEAD)
            let indexFlags = flags & (
                GIT_STATUS_INDEX_NEW.rawValue |
                GIT_STATUS_INDEX_MODIFIED.rawValue |
                GIT_STATUS_INDEX_DELETED.rawValue |
                GIT_STATUS_INDEX_RENAMED.rawValue |
                GIT_STATUS_INDEX_TYPECHANGE.rawValue
            )
            if indexFlags != 0 {
                let delta = deltaFromIndexFlags(indexFlags)
                changes.append(GitChange(path: filePath, delta: delta, isStaged: true))
            }

            // Unstaged / untracked changes (workdir vs index)
            let wtFlags = flags & (
                GIT_STATUS_WT_NEW.rawValue |
                GIT_STATUS_WT_MODIFIED.rawValue |
                GIT_STATUS_WT_DELETED.rawValue |
                GIT_STATUS_WT_RENAMED.rawValue |
                GIT_STATUS_WT_TYPECHANGE.rawValue
            )
            if wtFlags != 0 {
                let delta = deltaFromWtFlags(wtFlags)
                changes.append(GitChange(path: filePath, delta: delta, isStaged: false))
            }
        }
        return changes
    }

    // MARK: - Private helpers

    private func deltaFromIndexFlags(_ flags: UInt32) -> GitDelta {
        if flags & GIT_STATUS_INDEX_NEW.rawValue != 0 { return .added }
        if flags & GIT_STATUS_INDEX_MODIFIED.rawValue != 0 { return .modified }
        if flags & GIT_STATUS_INDEX_DELETED.rawValue != 0 { return .deleted }
        if flags & GIT_STATUS_INDEX_RENAMED.rawValue != 0 { return .renamed }
        return .modified
    }

    private func deltaFromWtFlags(_ flags: UInt32) -> GitDelta {
        if flags & GIT_STATUS_WT_NEW.rawValue != 0 { return .untracked }
        if flags & GIT_STATUS_WT_MODIFIED.rawValue != 0 { return .modified }
        if flags & GIT_STATUS_WT_DELETED.rawValue != 0 { return .deleted }
        if flags & GIT_STATUS_WT_RENAMED.rawValue != 0 { return .renamed }
        return .modified
    }
}
