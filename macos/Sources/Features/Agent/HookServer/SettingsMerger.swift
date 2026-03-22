// macos/Sources/Features/Agent/HookServer/SettingsMerger.swift
import Foundation
import OSLog

/// 合并四层 Claude Code settings 的 hooks 配置 + 注入 poltertty hooks
final class SettingsMerger {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "SettingsMerger"
    )

    /// 需要注入的 hook 事件列表
    private static let hookEvents: [(event: String, timeout: Int, async: Bool)] = [
        ("SessionStart",     10, false),
        ("Notification",     10, false),
        ("UserPromptSubmit", 10, false),
        ("PreToolUse",        5, true),
        ("PostToolUse",       5, true),
        ("Stop",             10, false),
        ("SubagentStart",     5, true),
        ("SubagentStop",      5, true),
        ("PreCompact",        5, true),
        ("PostCompact",       5, true),
        ("SessionEnd",        3, false),
    ]

    static func mergeAndWrite(
        sessionId: String,
        sessionDir: String,
        cwd: String,
        cliPath: String,
        userSettingsPath: String?
    ) {
        // 1. 四层 settings 文件路径
        let home = NSHomeDirectory()
        let settingsPaths = [
            "\(home)/.claude/settings.json",
            "\(home)/.claude/settings.local.json",
            "\(cwd)/.claude/settings.json",
            "\(cwd)/.claude/settings.local.json",
        ] + (userSettingsPath.map { [$0] } ?? [])

        // 2. 读取并合并所有 hooks
        var mergedHooks: [String: [[String: Any]]] = [:]
        for path in settingsPaths {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hooks = json["hooks"] as? [String: Any] else { continue }
            for (event, entries) in hooks {
                guard let list = entries as? [[String: Any]] else { continue }
                mergedHooks[event, default: []].append(contentsOf: list)
            }
        }

        // 3. 追加 poltertty hooks
        for spec in hookEvents {
            let eventName = eventNameToHookArg(spec.event)
            var hookObj: [String: Any] = [
                "type": "command",
                "command": "\(cliPath) hook \(eventName) --session \(sessionId)",
                "timeout": spec.timeout,
            ]
            if spec.async { hookObj["async"] = true }
            let entry: [String: Any] = [
                "matcher": "",
                "hooks": [hookObj],
            ]
            mergedHooks[spec.event, default: []].append(entry)
        }

        // 4. 写 settings.json（仅 hooks 字段）
        let settings: [String: Any] = ["hooks": mergedHooks]
        let settingsURL = URL(fileURLWithPath: sessionDir).appendingPathComponent("settings.json")
        if let data = try? JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted) {
            try? data.write(to: settingsURL, options: .atomic)
        }
    }

    /// 将 HookEventType 名转为 CLI arg 格式（SessionStart → session-start）
    private static func eventNameToHookArg(_ event: String) -> String {
        // 简单的 PascalCase → kebab-case 转换
        var result = ""
        for (i, char) in event.enumerated() {
            if char.isUppercase && i > 0 {
                result += "-"
            }
            result += String(char).lowercased()
        }
        return result
    }
}
