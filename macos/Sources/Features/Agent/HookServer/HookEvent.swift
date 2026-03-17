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
}

struct HookPayload: Decodable {
    let hookEventName: HookEventType
    let sessionId: String
    let cwd: String
    let notificationType: String?
    let transcriptPath: String?
    let agentId: String?
    let agentName: String?
    let agentType: String?

    enum CodingKeys: String, CodingKey {
        case hookEventName   = "hook_event_name"
        case sessionId       = "session_id"
        case cwd
        case notificationType = "notification_type"
        case transcriptPath  = "transcript_path"
        case agentId         = "agent_id"
        case agentName       = "agent_name"
        case agentType       = "agent_type"
    }
}
