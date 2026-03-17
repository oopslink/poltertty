// macos/Sources/Features/Agent/HookServer/HookInjector.swift
import Foundation
import OSLog

/// 向项目目录注入 Claude Code hook 配置（项目级 .local.json，不修改全局配置）
final class HookInjector {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "HookInjector"
    )

    private static let marker = "_poltertty"

    private static let hookEventNames = [
        "SessionStart", "SessionEnd", "Notification",
        "PreToolUse", "PostToolUse", "Stop",
        "SubagentStart", "SubagentStop", "PreCompact", "PostCompact"
    ]

    static func inject(cwd: String, port: UInt16) {
        let path = settingsPath(cwd: cwd)
        let url = "http://localhost:\(port)/hook"
        modifySettings(at: path) { settings in
            var hooks = settings["hooks"] as? [String: Any] ?? [:]
            let entry: [String: Any] = ["type": "http", "url": url, marker: true]
            let wrapper: [String: Any] = ["hooks": [entry]]
            for event in hookEventNames {
                var list = hooks[event] as? [[String: Any]] ?? []
                list.removeAll { ($0[marker] as? Bool) == true }
                list.append(wrapper)
                hooks[event] = list
            }
            settings["hooks"] = hooks
        }
    }

    static func cleanup(cwd: String) {
        let path = settingsPath(cwd: cwd)
        guard FileManager.default.fileExists(atPath: path) else { return }
        modifySettings(at: path) { settings in
            guard var hooks = settings["hooks"] as? [String: Any] else { return }
            for event in hookEventNames {
                if var list = hooks[event] as? [[String: Any]] {
                    list.removeAll { entry in
                        (entry[marker] as? Bool) == true ||
                        ((entry["hooks"] as? [[String: Any]])?.contains { ($0[marker] as? Bool) == true } ?? false)
                    }
                    hooks[event] = list.isEmpty ? nil : list
                }
            }
            settings["hooks"] = hooks.isEmpty ? nil : hooks
        }
    }

    // MARK: - Private

    private static func settingsPath(cwd: String) -> String {
        let claudeDir = (cwd as NSString).appendingPathComponent(".claude")
        return (claudeDir as NSString).appendingPathComponent("settings.local.json")
    }

    private static func modifySettings(at path: String, modify: (inout [String: Any]) -> Void) {
        let fileURL = URL(fileURLWithPath: path)
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordError) { writeURL in
            var settings: [String: Any] = [:]
            if let data = try? Data(contentsOf: writeURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                settings = json
            }
            let claudeDir = (path as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)
            modify(&settings)
            guard let newData = try? JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted) else { return }
            let tmpURL = writeURL.appendingPathExtension("tmp")
            try? newData.write(to: tmpURL)
            try? FileManager.default.moveItem(at: tmpURL, to: writeURL)
        }
        if let err = coordError { logger.error("HookInjector coordinator error: \(err)") }
    }
}
