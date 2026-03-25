// macos/Sources/Features/Workspace/FileBrowser/FileNode.swift
import Foundation

// GitDelta 定义在 GitKit/GitModels.swift，此处直接使用

struct FileNode: Identifiable {
    let id: UUID
    let url: URL
    var isDirectory: Bool
    var isExpanded: Bool = false
    var children: [FileNode]?  // nil = 目录但未加载；[] = 空目录或文件
    var gitDelta: GitDelta?    // 原来是 gitStatus: GitStatus?

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
