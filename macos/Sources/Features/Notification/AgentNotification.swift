// macos/Sources/Features/Notification/AgentNotification.swift
import Foundation

enum AgentNotificationType: String, Codable {
    case waiting    // Agent 等待用户操作（idle_prompt）
    case error      // 出错
    case done       // 任务/会话结束
    case info       // 纯信息
}

enum AgentNotificationPriority: Int, Codable, Comparable {
    case low = 0
    case normal = 1
    case high = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct AgentNotification: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let workspaceId: UUID?   // nil = 未关联工作区，显示在所有工作区
    let surfaceId: UUID?

    // 来源
    let agentDefinitionId: String     // 对应 AgentDefinition.id
    let sessionId: String?            // claudeSessionId 或 ExternalSessionRecord.id

    // 内容
    let type: AgentNotificationType
    let title: String
    let body: String?
    let priority: AgentNotificationPriority

    // 状态
    var isRead: Bool = false
}
