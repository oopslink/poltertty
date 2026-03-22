// macos/Sources/Features/Agent/HookServer/HookEvent.swift
import Foundation

enum HookEventType: String, Decodable {
    case sessionStart   = "SessionStart"
    case sessionEnd     = "SessionEnd"
    case notification       = "Notification"
    case userPromptSubmit   = "UserPromptSubmit"
    case preToolUse         = "PreToolUse"
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
    let toolResponse: String?       // PostToolUse 的 tool_response（agent 输出文本，可能为对象）
    var toolInputRaw: String? = nil // 由 HookServer 注入的 tool_input 原始 JSON（不参与 Decodable）

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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hookEventName   = try c.decode(HookEventType.self, forKey: .hookEventName)
        sessionId       = try? c.decodeIfPresent(String.self, forKey: .sessionId)
        cwd             = try? c.decodeIfPresent(String.self, forKey: .cwd)
        notificationType = try? c.decodeIfPresent(String.self, forKey: .notificationType)
        transcriptPath  = try? c.decodeIfPresent(String.self, forKey: .transcriptPath)
        toolName        = try? c.decodeIfPresent(String.self, forKey: .toolName)
        toolUseId       = try? c.decodeIfPresent(String.self, forKey: .toolUseId)
        toolInput       = try? c.decodeIfPresent(AgentToolInput.self, forKey: .toolInput)
        agentId         = try? c.decodeIfPresent(String.self, forKey: .agentId)
        agentName       = try? c.decodeIfPresent(String.self, forKey: .agentName)
        agentType       = try? c.decodeIfPresent(String.self, forKey: .agentType)
        // tool_response 可能是字符串或对象，类型不匹配时忽略
        toolResponse    = try? c.decodeIfPresent(String.self, forKey: .toolResponse)
    }
}
