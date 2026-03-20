// macos/Sources/Features/Workspace/WorkspaceGroup.swift
import AppKit
import Foundation
import UniformTypeIdentifiers

struct WorkspaceGroup: Codable, Identifiable {
    let id: UUID
    var name: String
    var orderIndex: Int       // 控制分组在 sidebar 中的顺序
    var isExpanded: Bool      // expanded sidebar 中的展开状态（true = 展开）
    var isCollapsedIcon: Bool // collapsed sidebar 中是否收起成单图标
    let createdAt: Date
    var updatedAt: Date

    init(name: String, orderIndex: Int = 0) {
        self.id = UUID()
        self.name = name
        self.orderIndex = orderIndex
        self.isExpanded = true
        self.isCollapsedIcon = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// 分组名前两个 Unicode scalar（大写），正确处理 emoji 和多字节字符
    var abbreviation: String {
        let scalars = Array(name.unicodeScalars.prefix(2))
        return String(String.UnicodeScalarView(scalars)).uppercased()
    }
}

// MARK: - Drag Support

extension WorkspaceGroup {
    static let dragTypeIdentifier = "com.poltertty.workspace-group"
    static let dragType = NSPasteboard.PasteboardType(dragTypeIdentifier)
    static let utType = UTType(exportedAs: dragTypeIdentifier)
}

extension WorkspaceModel {
    static let dragTypeIdentifier = "com.poltertty.workspace"
    static let dragType = NSPasteboard.PasteboardType(dragTypeIdentifier)
    static let utType = UTType(exportedAs: dragTypeIdentifier)
}
