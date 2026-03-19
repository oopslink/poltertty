// macos/Sources/Features/Agent/ExternalMonitor/ExternalSessionRecord.swift
import Foundation

enum ExternalToolType: String {
    case claudeCode = "claude-code"
    case openCode   = "opencode"
    case geminiCli  = "gemini-cli"

    var badge: String {
        switch self {
        case .claudeCode: return "[CC]"
        case .openCode:   return "[OC]"
        case .geminiCli:  return "[GM]"
        }
    }
}

struct ExternalSessionRecord: Identifiable {
    let id: String
    let toolType: ExternalToolType
    let pid: Int?
    let cwd: String
    let startedAt: Date
    var isAlive: Bool
    var lastMessage: LastMessage?

    struct LastMessage {
        enum Role { case user, assistant }
        let role: Role
        let text: String
        let timestamp: Date
    }
}
