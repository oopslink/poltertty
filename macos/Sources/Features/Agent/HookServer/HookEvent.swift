// macos/Sources/Features/Agent/HookServer/HookEvent.swift
import Foundation

enum HookEventType: String, Decodable {
    case sessionStart   = "SessionStart"
    case sessionEnd     = "SessionEnd"
    case notification   = "Notification"
    case preToolUse     = "PreToolUse"
    case postToolUse    = "PostToolUse"
    case stop           = "Stop"
    case subagentStart  = "SubagentStart"
    case subagentStop   = "SubagentStop"
    case preCompact     = "PreCompact"
    case postCompact    = "PostCompact"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = HookEventType(rawValue: raw) ?? .unknown
    }
}

/// Agent tool 的 tool_input（只解析需要的字段，忽略其余）
struct AgentToolInput: Decodable {
    let description: String?
    let prompt: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        description = try? container.decode(String.self, forKey: .description)
        prompt = try? container.decode(String.self, forKey: .prompt)
    }

    enum CodingKeys: String, CodingKey {
        case description, prompt
    }
}

struct HookPayload: Decodable {
    let hookEventName: HookEventType
    let sessionId: String?
    let cwd: String?
    let notificationType: String?
    let transcriptPath: String?
    let toolName: String?
    let toolUseId: String?
    let toolInput: AgentToolInput?  // Agent tool 的输入（含 description）
    let agentId: String?
    let agentName: String?
    let agentType: String?
    let toolResponse: String?       // PostToolUse 的 tool_response（agent 输出文本）

    enum CodingKeys: String, CodingKey {
        case hookEventName   = "hook_event_name"
        case sessionId       = "session_id"
        case cwd
        case notificationType = "notification_type"
        case transcriptPath  = "transcript_path"
        case toolName        = "tool_name"
        case toolUseId       = "tool_use_id"
        case toolInput       = "tool_input"
        case agentId         = "agent_id"
        case agentName       = "agent_name"
        case agentType       = "agent_type"
        case toolResponse    = "tool_response"
    }
}
