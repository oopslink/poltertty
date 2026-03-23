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
                isCurrent: normalizedPath == normalizedCurrent
            ))
            isFirst = false
        }

        return worktrees
    }
}
