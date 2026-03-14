// macos/Sources/Features/Workspace/PolterttyConfig.swift
import Foundation

struct PolterttyConfig {
    static let shared = PolterttyConfig()

    let workspaceDir: String
    let restoreOnLaunch: Bool
    let sidebarVisible: Bool
    let sidebarWidth: Int

    private init() {
        let values = Self.parse()
        self.workspaceDir = values["workspace-dir"]
            ?? ("~/.config/poltertty/workspaces" as NSString).expandingTildeInPath
        self.restoreOnLaunch = (values["workspace-restore-on-launch"] ?? "true") == "true"
        self.sidebarVisible = (values["workspace-sidebar-visible"] ?? "true") == "true"
        self.sidebarWidth = Int(values["workspace-sidebar-width"] ?? "200") ?? 200
    }

    private static func parse() -> [String: String] {
        let path = ("~/.config/poltertty/config" as NSString).expandingTildeInPath
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            result[key] = value
        }
        return result
    }
}
