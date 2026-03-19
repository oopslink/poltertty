// macos/Sources/Features/Agent/HookServer/HookInjector.swift
import Foundation
import OSLog

/// 向项目目录注入 Claude Code hook 配置（项目级 .local.json，不修改全局配置）
final class HookInjector {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "HookInjector"
    )

    /// 用 URL query param 标识我们的 hook（避免在 hook 对象中使用非标准字段导致 Claude Code 报错）
    private static let markerQuery = "src=poltertty"

    private static let hookEventNames = [
        "SessionStart", "SessionEnd", "Notification",
        "PreToolUse", "PostToolUse", "Stop",
        "SubagentStart", "SubagentStop", "PreCompact", "PostCompact"
    ]

    static func inject(cwd: String, port: UInt16) {
        let path = settingsPath(cwd: cwd)
        let url = "http://localhost:\(port)/hook?\(markerQuery)"
        modifySettings(at: path) { settings in
            var hooks = settings["hooks"] as? [String: Any] ?? [:]
            // Claude Code hooks schema: 每个事件数组元素需要 hooks 数组包装
            let entry: [String: Any] = ["hooks": [["type": "http", "url": url]]]
            for event in hookEventNames {
                var list = hooks[event] as? [[String: Any]] ?? []
                // 清理：匹配 URL 中的 marker query 或旧的 _poltertty 字段
                list.removeAll { isOurHook($0) }
                list.append(entry)
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
                    list.removeAll { isOurHook($0) }
                    hooks[event] = list.isEmpty ? nil : list
                }
            }
            settings["hooks"] = hooks.isEmpty ? nil : hooks
        }
    }

    // MARK: - Private

    /// 判断一个 hook 条目是否是我们注入的
    private static func isOurHook(_ item: [String: Any]) -> Bool {
        // 新格式：URL 包含 src=poltertty
        if let url = item["url"] as? String, url.contains(markerQuery) { return true }
        // 旧格式：_poltertty 字段
        if (item["_poltertty"] as? Bool) == true { return true }
        // 旧格式：URL 匹配 localhost:PORT/hook（无 query）
        if let url = item["url"] as? String, isLocalhostHook(url) { return true }
        // 旧嵌套 wrapper 格式
        if let inner = item["hooks"] as? [[String: Any]] {
            return inner.contains { isOurHook($0) }
        }
        return false
    }

    private static func isLocalhostHook(_ url: String) -> Bool {
        url.hasPrefix("http://localhost:") && url.contains("/hook")
    }

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
