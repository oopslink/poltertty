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

    // MARK: - Log

    /// 返回仓库提交历史（从 HEAD 开始，按时间降序）
    func log(maxCount: Int = 100) throws -> [GitCommit] {
        guard let r = repo else { return [] }
        var walker: OpaquePointer?
        var code = git_revwalk_new(&walker, r)
        guard code == 0, let w = walker else { throw GitError.fromLibgit2(code) }
        defer { git_revwalk_free(w) }
        git_revwalk_sorting(w, UInt32(GIT_SORT_TIME.rawValue))
        code = git_revwalk_push_head(w)
        guard code == 0 else { throw GitError.fromLibgit2(code) }

        var commits: [GitCommit] = []
        var oid = git_oid()
        while git_revwalk_next(&oid, w) == 0, commits.count < maxCount {
            if let commit = try? commitFromOid(&oid, repo: r) {
                commits.append(commit)
            }
        }
        return commits
    }

    /// 返回指定文件的提交历史（过滤出修改了该路径的提交）
    func fileLog(path: String, maxCount: Int = 50) throws -> [GitCommit] {
        guard let r = repo else { return [] }
        var walker: OpaquePointer?
        var code = git_revwalk_new(&walker, r)
        guard code == 0, let w = walker else { throw GitError.fromLibgit2(code) }
        defer { git_revwalk_free(w) }
        git_revwalk_sorting(w, UInt32(GIT_SORT_TIME.rawValue))
        code = git_revwalk_push_head(w)
        guard code == 0 else { throw GitError.fromLibgit2(code) }

        var commits: [GitCommit] = []
        var oid = git_oid()
        while git_revwalk_next(&oid, w) == 0, commits.count < maxCount {
            guard let commit = try? commitFromOid(&oid, repo: r) else { continue }
            if commitTouchesPath(oid: &oid, path: path, repo: r) {
                commits.append(commit)
            }
        }
        return commits
    }

    // MARK: - Diff

    /// 返回指定 commit 的变更文件列表
    func commitDiff(oid: String) throws -> [GitCommitFile] {
        guard let r = repo else { return [] }
        var gitOid = git_oid()
        guard git_oid_fromstr(&gitOid, oid) == 0 else { throw GitError.invalidOid(oid) }

        var commit: OpaquePointer?
        guard git_commit_lookup(&commit, r, &gitOid) == 0, let c = commit else {
            throw GitError.fromLibgit2(-1)
        }
        defer { git_commit_free(c) }

        var tree: OpaquePointer?
        git_commit_tree(&tree, c)
        defer { git_tree_free(tree) }

        var parentTree: OpaquePointer?
        if git_commit_parentcount(c) > 0 {
            var parent: OpaquePointer?
            git_commit_parent(&parent, c, 0)
            if let p = parent {
                git_commit_tree(&parentTree, p)
                git_commit_free(p)
            }
        }
        defer { git_tree_free(parentTree) }

        var diff: OpaquePointer?
        git_diff_tree_to_tree(&diff, r, parentTree, tree, nil)
        defer { git_diff_free(diff) }
        guard let d = diff else { return [] }

        var files: [GitCommitFile] = []
        let count = git_diff_num_deltas(d)
        for i in 0..<count {
            guard let delta = git_diff_get_delta(d, i) else { continue }
            let newPath = String(cString: delta.pointee.new_file.path)
            let oldPath: String? = delta.pointee.old_file.path.map { String(cString: $0) }
                .flatMap { $0 != newPath ? $0 : nil }
            let gitDelta = deltaFromLibgit2(delta.pointee.status)
            files.append(GitCommitFile(id: newPath, path: newPath, delta: gitDelta, oldPath: oldPath))
        }
        return files
    }

    /// 返回指定 commit 中单个文件的 diff
    func fileDiff(oid: String, path: String) throws -> GitFileDiff {
        guard let r = repo else { throw GitError.operationFailed("No repo") }
        var gitOid = git_oid()
        guard git_oid_fromstr(&gitOid, oid) == 0 else { throw GitError.invalidOid(oid) }
        var commit: OpaquePointer?
        guard git_commit_lookup(&commit, r, &gitOid) == 0, let c = commit else {
            throw GitError.fromLibgit2(-1)
        }
        defer { git_commit_free(c) }
        var tree: OpaquePointer?
        git_commit_tree(&tree, c)
        defer { git_tree_free(tree) }
        var parentTree: OpaquePointer?
        if git_commit_parentcount(c) > 0 {
            var parent: OpaquePointer?
            git_commit_parent(&parent, c, 0)
            if let p = parent { git_commit_tree(&parentTree, p); git_commit_free(p) }
        }
        defer { git_tree_free(parentTree) }
        var diff: OpaquePointer?
        var opts = git_diff_options()
        git_diff_options_init(&opts, UInt32(GIT_DIFF_OPTIONS_VERSION))
        git_diff_tree_to_tree(&diff, r, parentTree, tree, &opts)
        defer { git_diff_free(diff) }
        return try extractFileDiffFromDiff(diff: diff, path: path)
    }

    /// 返回工作区 diff（staged: true 为暂存区 vs HEAD，false 为工作区 vs 暂存区）
    func workingDiff(path: String, staged: Bool) throws -> GitFileDiff {
        guard let r = repo else { throw GitError.operationFailed("No repo") }
        var diff: OpaquePointer?
        var opts = git_diff_options()
        git_diff_options_init(&opts, UInt32(GIT_DIFF_OPTIONS_VERSION))
        opts.flags |= UInt32(GIT_DIFF_INCLUDE_UNTRACKED.rawValue)

        if staged {
            // 暂存区 vs HEAD
            var head: OpaquePointer?
            var headTree: OpaquePointer?
            if git_repository_head(&head, r) == 0, let h = head {
                var headCommit: OpaquePointer?
                var headOid = git_reference_target(h)?.pointee ?? git_oid()
                git_commit_lookup(&headCommit, r, &headOid)
                if let hc = headCommit { git_commit_tree(&headTree, hc); git_commit_free(hc) }
                git_reference_free(h)
            }
            defer { git_tree_free(headTree) }
            git_diff_tree_to_index(&diff, r, headTree, nil, &opts)
        } else {
            // 工作区 vs 暂存区
            git_diff_index_to_workdir(&diff, r, nil, &opts)
        }
        defer { git_diff_free(diff) }
        return try extractFileDiffFromDiff(diff: diff, path: path)
    }

    // MARK: - Private helpers (commit / diff)

    /// 从 git_oid 构造 GitCommit 值
    private func commitFromOid(_ oid: inout git_oid, repo: OpaquePointer) throws -> GitCommit {
        var commit: OpaquePointer?
        let code = git_commit_lookup(&commit, repo, &oid)
        guard code == 0, let c = commit else { throw GitError.fromLibgit2(code) }
        defer { git_commit_free(c) }

        let sha = withUnsafePointer(to: oid) { ptr -> String in
            var buf = [CChar](repeating: 0, count: 41)
            git_oid_tostr(&buf, 41, ptr)
            return String(cString: buf)
        }

        let rawMsg = git_commit_message(c).map { String(cString: $0) } ?? ""
        let firstLine = rawMsg.components(separatedBy: "\n").first ?? rawMsg

        let authorSig = git_commit_author(c)
        let authorName = authorSig?.pointee.name.map { String(cString: $0) } ?? ""
        let time = TimeInterval(git_commit_time(c))
        let date = Date(timeIntervalSince1970: time)

        var parentIds: [String] = []
        let parentCount = git_commit_parentcount(c)
        for i in 0..<parentCount {
            var parentOid = git_commit_parent_id(c, i)?.pointee ?? git_oid()
            var buf = [CChar](repeating: 0, count: 41)
            withUnsafePointer(to: parentOid) { git_oid_tostr(&buf, 41, $0) }
            parentIds.append(String(cString: buf))
        }

        return GitCommit(
            id: sha,
            shortId: String(sha.prefix(7)),
            message: firstLine.trimmingCharacters(in: .whitespacesAndNewlines),
            fullMessage: rawMsg,
            author: authorName,
            date: date,
            parentIds: parentIds
        )
    }

    /// 判断某个 commit 是否修改了指定路径
    private func commitTouchesPath(oid: inout git_oid, path: String, repo: OpaquePointer) -> Bool {
        var commit: OpaquePointer?
        guard git_commit_lookup(&commit, repo, &oid) == 0, let c = commit else { return false }
        defer { git_commit_free(c) }
        // root commit 没有父提交，视为触及所有文件
        guard git_commit_parentcount(c) > 0 else { return true }
        var parent: OpaquePointer?
        guard git_commit_parent(&parent, c, 0) == 0, let p = parent else { return false }
        defer { git_commit_free(p) }

        var tree: OpaquePointer?
        var parentTree: OpaquePointer?
        git_commit_tree(&tree, c)
        git_commit_tree(&parentTree, p)
        defer { git_tree_free(tree); git_tree_free(parentTree) }

        var opts = git_diff_options()
        git_diff_options_init(&opts, UInt32(GIT_DIFF_OPTIONS_VERSION))
        // pathspec 的 CString 生命周期必须覆盖 git_diff_tree_to_tree 调用
        var pathCopy = path
        return pathCopy.withCString { cPath in
            var cStrings: [UnsafePointer<CChar>?] = [cPath]
            opts.pathspec.strings = &cStrings
            opts.pathspec.count = 1
            var diff: OpaquePointer?
            git_diff_tree_to_tree(&diff, repo, parentTree, tree, &opts)
            defer { git_diff_free(diff) }
            return (diff.map { git_diff_num_deltas($0) } ?? 0) > 0
        }
    }

    /// 将 libgit2 delta 状态转换为 GitDelta
    private func deltaFromLibgit2(_ status: git_delta_t) -> GitDelta {
        switch status {
        case GIT_DELTA_ADDED:    return .added
        case GIT_DELTA_MODIFIED: return .modified
        case GIT_DELTA_DELETED:  return .deleted
        case GIT_DELTA_RENAMED:  return .renamed
        case GIT_DELTA_COPIED:   return .copied
        default:                 return .modified
        }
    }

    /// 从 diff 对象中提取指定路径的 GitFileDiff
    private func extractFileDiffFromDiff(diff: OpaquePointer?, path: String) throws -> GitFileDiff {
        guard let d = diff else {
            return GitFileDiff(path: path, oldPath: nil, delta: .modified, patches: [])
        }
        let count = git_diff_num_deltas(d)
        var targetIdx: Int? = nil
        for i in 0..<count {
            if let delta = git_diff_get_delta(d, i) {
                let p = String(cString: delta.pointee.new_file.path)
                if p == path { targetIdx = i; break }
            }
        }
        guard let idx = targetIdx,
              let delta = git_diff_get_delta(d, idx) else {
            return GitFileDiff(path: path, oldPath: nil, delta: .untracked, patches: [])
        }
        let gitDelta = deltaFromLibgit2(delta.pointee.status)
        let oldPath = delta.pointee.old_file.path.map { String(cString: $0) }
            .flatMap { $0 != path ? $0 : nil }
        let patches = try patchesFromDiff(d, deltaIndex: idx)
        return GitFileDiff(path: path, oldPath: oldPath, delta: gitDelta, patches: patches)
    }

    /// 从 diff 对象的指定 delta 索引中提取所有 hunk 和行
    private func patchesFromDiff(_ diff: OpaquePointer, deltaIndex: Int) throws -> [GitPatch] {
        var patch: OpaquePointer?
        git_patch_from_diff(&patch, diff, deltaIndex)
        defer { git_patch_free(patch) }
        guard let p = patch else { return [] }
        let hunkCount = git_patch_num_hunks(p)
        var patches: [GitPatch] = []
        var lineCounter = 0
        for h in 0..<hunkCount {
            var hunk: UnsafePointer<git_diff_hunk>?
            var lineCount = 0
            git_patch_get_hunk(&hunk, &lineCount, p, h)
            let header = hunk.map { String(cString: $0.pointee.header) }?
                .trimmingCharacters(in: .newlines) ?? ""
            var lines: [GitDiffLine] = []
            for l in 0..<lineCount {
                var line: UnsafePointer<git_diff_line>?
                git_patch_get_line_in_hunk(&line, p, h, l)
                guard let ln = line else { continue }
                let content = String(bytes: UnsafeBufferPointer(
                    start: ln.pointee.content, count: ln.pointee.content_len), encoding: .utf8) ?? ""
                let origin: GitDiffLine.Origin
                switch Int32(ln.pointee.origin) {
                case GIT_DIFF_LINE_ADDITION.rawValue: origin = .added
                case GIT_DIFF_LINE_DELETION.rawValue: origin = .removed
                default: origin = .context
                }
                // old_lineno == -1 表示新增行（无旧行号），new_lineno == -1 表示删除行
                let oldNo = ln.pointee.old_lineno > 0 ? Int(ln.pointee.old_lineno) : nil
                let newNo = ln.pointee.new_lineno > 0 ? Int(ln.pointee.new_lineno) : nil
                lines.append(GitDiffLine(id: lineCounter, origin: origin,
                                         oldLineNo: oldNo, newLineNo: newNo,
                                         content: content.trimmingCharacters(in: .newlines)))
                lineCounter += 1
            }
            patches.append(GitPatch(header: header, lines: lines))
        }
        return patches
    }
}
