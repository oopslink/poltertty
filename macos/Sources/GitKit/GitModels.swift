// macos/Sources/GitKit/GitModels.swift
import Foundation

struct GitCommit: Identifiable, Equatable {
    let id: String          // full SHA
    let shortId: String     // 前7位
    let message: String     // 第一行 summary
    let fullMessage: String // 完整提交信息（含 body）
    let author: String
    let date: Date
    let parentIds: [String]
}

struct GitCommitFile: Identifiable {
    let id: String          // path（rename 后的新路径）
    let path: String
    let delta: GitDelta
    let oldPath: String?    // renamed/copied 时的旧路径
}

enum GitDelta: Equatable, Comparable {
    case added, modified, deleted, renamed, copied, untracked
    // untracked 仅用于 GitChange 和 workingDiff 场景
    // commit diff（GitCommitFile/GitFileDiff）中不会出现 untracked

    var symbol: String {
        switch self {
        case .added:     return "A"
        case .modified:  return "M"
        case .deleted:   return "D"
        case .renamed:   return "R"
        case .copied:    return "C"
        case .untracked: return "?"
        }
    }

    var colorHex: String {
        switch self {
        case .added:     return "#4ade80"
        case .modified:  return "#facc15"
        case .deleted:   return "#f87171"
        case .renamed:   return "#60a5fa"
        case .copied:    return "#a78bfa"
        case .untracked: return "#9ca3af"
        }
    }

    // 优先级（用于目录聚合：取子文件中最高优先级的状态）
    var priority: Int {
        switch self {
        case .deleted:   return 5
        case .modified:  return 4
        case .added:     return 3
        case .renamed:   return 2
        case .copied:    return 1
        case .untracked: return 0
        }
    }

    static func < (lhs: GitDelta, rhs: GitDelta) -> Bool {
        lhs.priority < rhs.priority
    }
}

struct GitFileDiff {
    let path: String
    let oldPath: String?
    let delta: GitDelta
    let patches: [GitPatch]
    // untracked 文件：patch header 为 @@ -0,0 +1,N @@，oldLineNo 全部 nil
}

struct GitPatch {
    let header: String      // @@ -a,b +c,d @@
    let lines: [GitDiffLine]
}

struct GitDiffLine: Identifiable {
    enum Origin { case added, removed, context }
    let id: Int             // 全局行序号，用于 ForEach
    let origin: Origin
    let oldLineNo: Int?
    let newLineNo: Int?
    let content: String
}

// staged 和 unstaged 各自独立列表
// 同一文件可同时出现在两个列表，delta 可能不同
struct GitChange: Identifiable {
    // id 格式："s:<path>" 或 "u:<path>"，保证唯一
    let id: String
    let path: String
    let delta: GitDelta
    let isStaged: Bool

    init(path: String, delta: GitDelta, isStaged: Bool) {
        self.id = "\(isStaged ? "s" : "u"):\(path)"
        self.path = path
        self.delta = delta
        self.isStaged = isStaged
    }
}
