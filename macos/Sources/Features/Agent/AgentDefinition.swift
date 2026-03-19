// macos/Sources/Features/Agent/AgentDefinition.swift
import Foundation

/// Agent 支持的 hook 能力等级
enum HookCapability: String, Codable {
    case full        // HTTP hook（Claude Code）
    case commandOnly // command hook + 桥接脚本（Gemini CLI）
    case none        // 无 hook，仅进程监控
}

/// 单个 Agent 类型定义
struct AgentDefinition: Identifiable, Codable {
    let id: String
    var name: String
    var command: String
    var icon: String
    /// 图标背景色，十六进制字符串（如 "#D97757"）。JSON 中缺省时使用灰色。
    var iconColor: String?
    var hookCapability: HookCapability

    static let claudeCode = AgentDefinition(
        id: "claude-code", name: "Claude Code",
        command: "claude", icon: "◆", iconColor: "#CC785C", hookCapability: .full
    )
    static let geminiCLI = AgentDefinition(
        id: "gemini-cli", name: "Gemini CLI",
        command: "gemini", icon: "✦", iconColor: "#4285F4", hookCapability: .commandOnly
    )
    static let openCode = AgentDefinition(
        id: "opencode", name: "OpenCode",
        command: "opencode", icon: "⬡", iconColor: "#7C3AED", hookCapability: .none
    )
}

/// 所有可用 agent 的注册表（内置 + 用户自定义）
@MainActor
final class AgentRegistry: ObservableObject {
    static let shared = AgentRegistry()

    @Published private(set) var definitions: [AgentDefinition] = []

    private let builtins: [AgentDefinition] = [.claudeCode, .geminiCLI, .openCode]

    private static let customConfigPath: String = {
        let base = ("~/.config/poltertty" as NSString).expandingTildeInPath
        return (base as NSString).appendingPathComponent("agents.json")
    }()

    private struct CustomAgentsFile: Codable { var agents: [AgentDefinition] }

    private init() { reload() }

    func reload() {
        var all = builtins
        if let data = try? Data(contentsOf: URL(fileURLWithPath: Self.customConfigPath)),
           let custom = try? JSONDecoder().decode(CustomAgentsFile.self, from: data) {
            for agent in custom.agents {
                if let idx = all.firstIndex(where: { $0.id == agent.id }) {
                    all[idx] = agent
                } else {
                    all.append(agent)
                }
            }
        }
        definitions = all
    }
}
