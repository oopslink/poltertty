// macos/Sources/Features/Workspace/WorkspaceGroup.swift
import AppKit
import Foundation
import SwiftUI
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

/// Lightweight Transferable proxy for dragging a workspace by ID.
/// Uses ProxyRepresentation → String (UTType.plainText) which is
/// a system-registered type and works reliably on macOS 13+.
struct WorkspaceDragItem: Transferable {
    let workspaceId: UUID

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(
            exporting: { item in item.workspaceId.uuidString },
            importing: { str -> WorkspaceDragItem in
                guard let id = UUID(uuidString: str) else {
                    throw NSError(domain: "WorkspaceDrag", code: 0,
                                  userInfo: [NSLocalizedDescriptionKey: "Invalid UUID"])
                }
                return WorkspaceDragItem(workspaceId: id)
            }
        )
    }
}
