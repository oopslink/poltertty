// macos/Sources/Features/Agent/AgentSessionManager.swift
import Foundation
import Combine


@MainActor
final class AgentSessionManager: ObservableObject {
    @Published private(set) var sessions: [UUID: AgentSession] = [:]  // surfaceId → session
    private var claudeSessionIndex: [String: UUID] = [:]              // claudeSessionId → surfaceId

    // MARK: - 生命周期

    func register(_ session: AgentSession) {
        sessions[session.surfaceId] = session
    }

    func remove(surfaceId: UUID) {
        if let sid = sessions[surfaceId]?.claudeSessionId {
            claudeSessionIndex.removeValue(forKey: sid)
        }
        sessions.removeValue(forKey: surfaceId)
    }

    func removeAll(for workspaceId: UUID) {
        sessions.filter { $0.value.workspaceId == workspaceId }
               .map(\.key)
               .forEach { remove(surfaceId: $0) }
    }

    // MARK: - 状态更新

    func updateState(_ state: AgentState, surfaceId: UUID) {
        sessions[surfaceId]?.state = state
        sessions[surfaceId]?.lastEventAt = Date()
    }

    func bindClaudeSession(surfaceId: UUID, claudeSessionId: String) {
        sessions[surfaceId]?.claudeSessionId = claudeSessionId
        claudeSessionIndex[claudeSessionId] = surfaceId
    }

    func updateTokenUsage(surfaceId: UUID, usage: TokenUsage) {
        sessions[surfaceId]?.tokenUsage = usage
        sessions[surfaceId]?.lastEventAt = Date()
    }

    func updateFromClaudeSession(_ claudeSessionId: String, _ update: (inout AgentSession) -> Void) {
        guard let surfaceId = claudeSessionIndex[claudeSessionId],
              sessions[surfaceId] != nil else { return }
        update(&sessions[surfaceId]!)
        sessions[surfaceId]?.lastEventAt = Date()
    }

    // MARK: - 查询

    func session(for surfaceId: UUID) -> AgentSession? { sessions[surfaceId] }

    func session(forClaudeSessionId id: String) -> AgentSession? {
        guard let surfaceId = claudeSessionIndex[id] else { return nil }
        return sessions[surfaceId]
    }

    /// cwd 匹配、尚未绑定 claudeSessionId 的候选 surface（用于 SessionStart 关联）
    func candidateSurfaces(for cwd: String) -> [UUID] {
        sessions.filter { $0.value.cwd == cwd && $0.value.claudeSessionId == nil }.map(\.key)
    }

    /// 给定 workspaceId 的聚合状态（最高优先级）
    func aggregateState(for workspaceId: UUID) -> AgentState? {
        sessions.values
                .filter { $0.workspaceId == workspaceId }
                .max(by: { $0.state.priority < $1.state.priority })?.state
    }

    // MARK: - Hook 事件处理

    func processHookEvent(_ payload: HookPayload) {
        switch payload.hookEventName {
        case .sessionStart:
            bindOrCreateSession(payload: payload)
        case .sessionEnd:
            if let surfaceId = claudeSessionIndex[payload.sessionId] {
                let cwd = sessions[surfaceId]?.cwd
                updateFromClaudeSession(payload.sessionId) { $0.state = .done(exitCode: 0) }
                if let cwd = cwd {
                    AgentService.shared.cleanupHooks(for: cwd)
                }
            } else {
                updateFromClaudeSession(payload.sessionId) { $0.state = .done(exitCode: 0) }
            }
        case .preToolUse, .postToolUse:
            updateFromClaudeSession(payload.sessionId) { $0.state = .working }
            if let sid = claudeSessionIndex[payload.sessionId] {
                AgentService.shared.respawnController?.recordToolUse(surfaceId: sid)
            }
        case .notification:
            if payload.notificationType == "idle_prompt" {
                updateFromClaudeSession(payload.sessionId) { $0.state = .idle }
                if let sid = claudeSessionIndex[payload.sessionId] {
                    AgentService.shared.respawnController?.handleIdle(surfaceId: sid)
                }
            }
        case .stop:
            updateFromClaudeSession(payload.sessionId) { $0.state = .idle }
            if let sid = claudeSessionIndex[payload.sessionId],
               let path = payload.transcriptPath {
                AgentService.shared.tokenTracker?.processStopEvent(
                    surfaceId: sid,
                    transcriptPath: path,
                    model: "claude-sonnet-4"  // TODO: 从 AgentDefinition 读取
                )
            }
        case .subagentStart:
            if let agentId = payload.agentId, let name = payload.agentName {
                updateFromClaudeSession(payload.sessionId) {
                    $0.subagents[agentId] = SubagentInfo(
                        id: agentId, name: name,
                        agentType: payload.agentType ?? "subagent"
                    )
                }
            }
        case .subagentStop:
            if let agentId = payload.agentId {
                updateFromClaudeSession(payload.sessionId) {
                    $0.subagents[agentId]?.state = .done(exitCode: 0)
                    $0.subagents[agentId]?.finishedAt = Date()
                }
            }
        default:
            break
        }
    }

    private func bindOrCreateSession(payload: HookPayload) {
        if let surfaceId = candidateSurfaces(for: payload.cwd).first {
            bindClaudeSession(surfaceId: surfaceId, claudeSessionId: payload.sessionId)
            updateState(.working, surfaceId: surfaceId)
        }
    }
}
