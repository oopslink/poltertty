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

    static let empty = GitRepoStatus(branch: nil, added: 0, modified: 0, isGitRepo: false)
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
