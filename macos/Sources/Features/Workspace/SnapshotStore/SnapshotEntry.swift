// macos/Sources/Features/Workspace/SnapshotStore/SnapshotEntry.swift
import Foundation

/// 单条 Workspace 布局快照，不含 WorkspaceModel（通过 workspaceId 关联）
struct SnapshotEntry: Codable, Identifiable {
    let id: UUID
    let savedAt: Date
    var windowFrame: WindowFrame?
    var sidebarWidth: CGFloat
    var sidebarVisible: Bool
    var tabs: [PersistedTab]?
    var activeTabIndex: Int?

    struct WindowFrame: Codable, Equatable {
        var x, y, width, height: CGFloat

        init(_ rect: CGRect) {
            x = rect.origin.x
            y = rect.origin.y
            width = rect.size.width
            height = rect.size.height
        }

        var cgRect: CGRect {
            CGRect(x: x, y: y, width: width, height: height)
        }
    }

    struct PersistedTab: Codable, Equatable {
        let title: String
        let titleLocked: Bool
    }
}
