// macos/Sources/Features/Workspace/WorkspaceModel.swift
import AppKit
import Foundation
import SwiftUI

struct WorkspaceModel: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var colorHex: String
    var icon: String
    var rootDir: String
    var description: String
    var tags: [String]
    let createdAt: Date
    var updatedAt: Date
    var lastActiveAt: Date
    var isTemporary: Bool
    var fileBrowserVisible: Bool = false
    var fileBrowserWidth: CGFloat = 260
    var groupId: UUID?    // nil = 未分组
    var groupOrder: Int   // workspace 在所属区域内的排列顺序

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case colorHex
        case icon
        case rootDir
        case description
        case tags
        case createdAt
        case updatedAt
        case lastActiveAt
        case isTemporary
        case fileBrowserVisible
        case fileBrowserWidth
        case groupId
        case groupOrder
    }

    init(name: String, rootDir: String, colorHex: String = "#FF6B6B", icon: String? = nil, isTemporary: Bool = false) {
        self.id = UUID()
        self.name = name
        self.rootDir = rootDir
        self.colorHex = colorHex
        self.icon = icon ?? String(name.prefix(2).uppercased())
        self.description = ""
        self.tags = []
        self.createdAt = Date()
        self.updatedAt = Date()
        self.lastActiveAt = Date()
        self.isTemporary = isTemporary
        self.groupId = nil
        self.groupOrder = 0
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        icon = try container.decode(String.self, forKey: .icon)
        rootDir = try container.decode(String.self, forKey: .rootDir)
        description = try container.decode(String.self, forKey: .description)
        tags = try container.decode([String].self, forKey: .tags)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        lastActiveAt = try container.decode(Date.self, forKey: .lastActiveAt)
        isTemporary = try container.decodeIfPresent(Bool.self, forKey: .isTemporary) ?? false
        fileBrowserVisible = try container.decodeIfPresent(Bool.self, forKey: .fileBrowserVisible) ?? false
        fileBrowserWidth   = try container.decodeIfPresent(CGFloat.self, forKey: .fileBrowserWidth) ?? 260
        groupId    = try container.decodeIfPresent(UUID.self, forKey: .groupId)
        groupOrder = try container.decodeIfPresent(Int.self, forKey: .groupOrder) ?? 0
    }

    var color: Color {
        Color(hex: colorHex) ?? .red
    }

    var nsColor: NSColor {
        NSColor(hex: colorHex) ?? .systemRed
    }

    var rootDirExpanded: String {
        (rootDir as NSString).expandingTildeInPath
    }

    var rootDirExists: Bool {
        FileManager.default.fileExists(atPath: rootDirExpanded)
    }

    // Use synthesized Equatable (all properties) so SwiftUI detects property changes
}

// MARK: - Snapshot

struct WorkspaceSnapshot: Codable {
    var version: Int = 2
    var workspace: WorkspaceModel
    var windowFrame: WindowFrame?
    var sidebarWidth: CGFloat
    var sidebarVisible: Bool

    // Tab state (added in version 2)
    var tabs: [PersistedTab]?
    var activeTabIndex: Int?

    struct PersistedTab: Codable {
        let title: String
        let titleLocked: Bool
    }

    struct WindowFrame: Codable {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat

        init(from frame: NSRect) {
            self.x = frame.origin.x
            self.y = frame.origin.y
            self.width = frame.size.width
            self.height = frame.size.height
        }

        var nsRect: NSRect {
            NSRect(x: x, y: y, width: width, height: height)
        }
    }
}

// MARK: - Color Helpers

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let int = UInt64(hex, radix: 16) else { return nil }
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

