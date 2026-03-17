// macos/Sources/Features/Agent/AgentSession.swift
import Foundation

/// Agent 运行状态机
enum AgentState: Equatable {
    case launching
    case working
    case idle
    case done(exitCode: Int32)
    case error(String)

    var isActive: Bool {
        switch self {
        case .launching, .working, .idle: return true
        case .done, .error: return false
        }
    }

    /// 用于 tab 聚合显示的优先级（越高越重要）
    var priority: Int {
        switch self {
        case .launching: return 4
        case .error:     return 3
        case .working:   return 2
        case .idle:      return 1
        case .done:      return 0
        }
    }
}

/// Respawn 预设模式（完整配置见 RespawnMode.swift，Phase 5 填充）
enum RespawnMode: String, CaseIterable, Codable {
    case soloWork  = "solo-work"
    case teamLead  = "team-lead"
    case overnight = "overnight"
    case manual    = "manual"

    var displayName: String {
        switch self {
        case .soloWork:  return "Solo"
        case .teamLead:  return "Team"
        case .overnight: return "Night"
        case .manual:    return "Manual"
        }
    }
}

/// Token 用量（完整实现见 TokenUsage.swift，Phase 6 替换）
struct TokenUsage: Codable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cost: Decimal = 0
    var contextUtilization: Float = 0
    var compactCount: Int = 0
}

/// Subagent 信息（由 SubagentStart/Stop hook 事件填充）
struct SubagentInfo: Identifiable {
    let id: String
    var name: String
    var agentType: String
    var state: AgentState = .launching
    var startedAt: Date = Date()
    var finishedAt: Date? = nil
}

/// 一个活跃 agent 的运行时状态
struct AgentSession: Identifiable {
    let id: UUID
    let surfaceId: UUID
    let definition: AgentDefinition
    let workspaceId: UUID
    let cwd: String
    var state: AgentState = .launching
    var claudeSessionId: String? = nil
    var shellPid: Int32 = 0
    var startedAt: Date = Date()
    var lastEventAt: Date = Date()
    var respawnMode: RespawnMode = .manual
    var tokenUsage: TokenUsage = TokenUsage()
    var subagents: [String: SubagentInfo] = [:]
}
