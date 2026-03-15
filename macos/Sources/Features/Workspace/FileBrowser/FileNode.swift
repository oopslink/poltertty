// macos/Sources/Features/Workspace/FileBrowser/FileNode.swift
import Foundation

enum GitStatus: Int, Comparable {
    case untracked = 0   // ?
    case added = 1       // A
    case modified = 2    // M
    case deleted = 3     // D — 最高优先级

    static func < (lhs: GitStatus, rhs: GitStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var symbol: String {
        switch self {
        case .untracked: return "?"
        case .added:     return "A"
        case .modified:  return "M"
        case .deleted:   return "D"
        }
    }

    var colorHex: String {
        switch self {
        case .untracked: return "#9ca3af"
        case .added:     return "#4ade80"
        case .modified:  return "#facc15"
        case .deleted:   return "#f87171"
        }
    }
}

struct FileNode: Identifiable {
    let id: UUID
    let url: URL
    var isDirectory: Bool
    var isExpanded: Bool = false
    var children: [FileNode]?  // nil = 目录但未加载；[] = 空目录或文件
    var gitStatus: GitStatus?

    init(url: URL) {
        self.id = UUID()
        self.url = url
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue
    }

    var name: String { url.lastPathComponent }
    var isHidden: Bool { name.hasPrefix(".") }
}
