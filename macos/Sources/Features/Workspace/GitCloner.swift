// macos/Sources/Features/Workspace/GitCloner.swift
import Foundation

final class GitCloner {

    // MARK: - Repo name extraction

    /// 从 git URL 中提取仓库名（去掉 .git 后缀和尾部斜杠）。
    /// 支持 https://, git@host:path, ssh://, 以及尾部带 / 的形式。
    /// - Returns: 仓库名；输入为空、空白或无法解析时返回 nil。
    static func extractRepoName(from url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var s = trimmed
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix(".git") { s.removeLast(4) }
        while s.hasSuffix("/") { s.removeLast() }

        let lastSlash = s.lastIndex(of: "/")
        let lastColon = s.lastIndex(of: ":")
        let cutIndex: String.Index?
        switch (lastSlash, lastColon) {
        case let (l?, c?): cutIndex = l > c ? l : c
        case let (l?, nil): cutIndex = l
        case let (nil, c?): cutIndex = c
        case (nil, nil): cutIndex = nil
        }

        let name: String
        if let idx = cutIndex {
            name = String(s[s.index(after: idx)...])
        } else {
            name = s
        }

        return name.isEmpty ? nil : name
    }
}
