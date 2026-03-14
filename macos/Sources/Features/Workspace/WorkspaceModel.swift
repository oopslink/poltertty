// macos/Sources/Features/Workspace/WorkspaceModel.swift
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

    init(name: String, rootDir: String, colorHex: String = "#FF6B6B", icon: String? = nil) {
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

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Snapshot

struct WorkspaceSnapshot: Codable {
    var version: Int = 1
    var workspace: WorkspaceModel
    var windowFrame: WindowFrame?
    var sidebarWidth: CGFloat
    var sidebarVisible: Bool

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

extension NSColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let int = UInt64(hex, radix: 16) else { return nil }
        let r = CGFloat((int >> 16) & 0xFF) / 255.0
        let g = CGFloat((int >> 8) & 0xFF) / 255.0
        let b = CGFloat(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
