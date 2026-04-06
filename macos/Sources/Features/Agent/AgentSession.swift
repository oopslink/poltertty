// macos/Sources/Features/Agent/AgentSession.swift
import Foundation
import SwiftUI

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

/// Subagent 内部的单次工具调用记录
struct ToolCallRecord: Identifiable {
    let id: String       // toolUseId
    let toolName: String
    var isDone: Bool = false
    var startedAt: Date = Date()
    var toolInput: String? = nil   // raw JSON string of tool_input
}

/// Subagent 信息（由 PreToolUse:Agent + SubagentStart hook 事件填充）
struct SubagentInfo: Identifiable {
    let id: String           // parent 的 toolUseId（Agent 调用时产生）
    var name: String         // description 字段
    var agentType: String
    var prompt: String? = nil        // 发给 subagent 的完整 prompt
    var agentId: String? = nil       // Claude Code 内部 agentId（用于匹配 hook）
    var state: AgentState = .launching
    var startedAt: Date = Date()
    var finishedAt: Date? = nil
    var toolCalls: [ToolCallRecord] = []
    var output: String? = nil       // agent 最终输出文本（PostToolUse tool_response）
    var isHistorical: Bool = false   // 由 PersistedSession.toAgentSession() 设置，标识只读历史记录
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
    var tokenUsage: TokenUsage = TokenUsage()
    var subagents: [String: SubagentInfo] = [:]
    /// 当前使用的模型名称（从 transcript 解析，如 "claude-sonnet-4-6"）
    var model: String? = nil
    /// 顶层工具调用记录（非 subagent 发起的工具调用）
    var topLevelToolCalls: [ToolCallRecord] = []
    /// 上下文压缩事件时间戳（PostCompact hook 触发）
    var compactEvents: [Date] = []
    /// 权限拒绝计数（PermissionDenied notification 触发）
    var deniedToolCount: Int = 0
    /// Agent 通过 set_agent_label 工具设置的自定义标签
    var customLabel: String? = nil

    /// 当前活跃的 subagent 数量
    var activeSubagentCount: Int {
        subagents.values.filter { $0.state.isActive }.count
    }
}

extension AgentState {
    /// Dashboard 状态指示色（统一 source of truth）
    var indicatorColor: Color {
        switch self {
        case .working:   return .green
        case .idle:      return .yellow
        case .launching: return Color(.controlAccentColor)
        case .done:      return .secondary
        case .error:     return .red
        }
    }
}
