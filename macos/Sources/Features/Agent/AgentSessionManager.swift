// macos/Sources/Features/Agent/AgentSessionManager.swift
import Foundation
import Combine
import OSLog


@MainActor
final class AgentSessionManager: ObservableObject {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "AgentSessionManager"
    )
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
        AgentService.shared.tokenTracker?.clearThrottle(surfaceId: surfaceId)
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
    /// 解析 symlink（macOS 上 /Users 是 /private/Users 的符号链接），保证路径一致
    func candidateSurfaces(for cwd: String) -> [UUID] {
        let expandedCwd = Self.realPath(cwd)
        return sessions.filter {
            Self.realPath($0.value.cwd) == expandedCwd
            && $0.value.claudeSessionId == nil
        }.map(\.key)
    }

    private static func realPath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).resolvingSymlinksInPath().path
    }

    /// 给定 workspaceId 的聚合状态（最高优先级）
    func aggregateState(for workspaceId: UUID) -> AgentState? {
        sessions.values
                .filter { $0.workspaceId == workspaceId }
                .max(by: { $0.state.priority < $1.state.priority })?.state
    }

    // MARK: - Hook 事件处理

    func processHookEvent(_ payload: HookPayload) {
        let sid = payload.sessionId  // optional String?

        // 在任意事件中尝试绑定：SessionStart 可能在 hooks 加载前就触发了
        if let sid, claudeSessionIndex[sid] == nil, let cwd = payload.cwd {
            bindOrCreateSession(sessionId: sid, cwd: cwd)
        }

        switch payload.hookEventName {
        case .sessionStart:
            // 已在上面处理
            break
        case .sessionEnd:
            guard let sid else { return }
            if let surfaceId = claudeSessionIndex[sid] {
                let cwd = sessions[surfaceId]?.cwd
                updateFromClaudeSession(sid) { $0.state = .done(exitCode: 0) }
                // F5: 持久化到磁盘
                if let session = sessions[surfaceId] {
                    let snap = session  // 值拷贝，避免后续修改竞争
                    Task.detached(priority: .utility) {
                        SessionStore.shared.save(snap)
                    }
                }
                if let cwd = cwd {
                    AgentService.shared.cleanupHooks(for: cwd)
                }
            } else {
                updateFromClaudeSession(sid) { $0.state = .done(exitCode: 0) }
            }
        case .preToolUse:
            guard let sid else { Self.logger.warning("preToolUse: no sessionId"); return }
            let indexed = claudeSessionIndex[sid] != nil
            Self.logger.warning("preToolUse: sid=\(sid) indexed=\(indexed) tool=\(payload.toolName ?? "nil") toolUseId=\(payload.toolUseId ?? "nil") agentId=\(payload.agentId ?? "-")")
            updateFromClaudeSession(sid) { $0.state = .working }
            if payload.toolName == "Agent" {
                // Agent tool → 新建 subagent 记录（去重）
                let toolUseId = payload.toolUseId ?? UUID().uuidString
                let name = payload.toolInput?.description ?? payload.agentName ?? "Subagent"
                let prompt = payload.toolInput?.prompt
                updateFromClaudeSession(sid) {
                    if $0.subagents[toolUseId] == nil {
                        $0.subagents[toolUseId] = SubagentInfo(
                            id: toolUseId, name: name, agentType: "agent", prompt: prompt
                        )
                    }
                }
            } else if let agentId = payload.agentId,
                      let toolUseId = payload.toolUseId,
                      let toolName = payload.toolName {
                // Subagent 内部的工具调用 → 追加到对应 SubagentInfo
                let record = ToolCallRecord(id: toolUseId, toolName: toolName, toolInput: payload.toolInputRaw)
                updateFromClaudeSession(sid) { session in
                    guard let key = session.subagents.values
                        .first(where: { $0.agentId == agentId })?.id else { return }
                    // 去重
                    if session.subagents[key]?.toolCalls.contains(where: { $0.id == toolUseId }) == false {
                        session.subagents[key]?.toolCalls.append(record)
                    }
                }
            }
        case .postToolUse:
            guard let sid else { Self.logger.warning("postToolUse: no sessionId"); return }
            Self.logger.info("postToolUse: sid=\(sid) tool=\(payload.toolName ?? "nil") toolUseId=\(payload.toolUseId ?? "nil") agentId=\(payload.agentId ?? "-")")
            updateFromClaudeSession(sid) { $0.state = .working }
            if let surfaceId = claudeSessionIndex[sid] {
                AgentService.shared.respawnController?.recordToolUse(surfaceId: surfaceId)
            }
            if payload.toolName == "Agent" {
                // Agent tool 完成 → 标记 subagent done，保存输出
                let toolUseId = payload.toolUseId ?? ""
                if !toolUseId.isEmpty {
                    let output = payload.toolResponse
                    updateFromClaudeSession(sid) {
                        $0.subagents[toolUseId]?.state = .done(exitCode: 0)
                        $0.subagents[toolUseId]?.finishedAt = Date()
                        if let output { $0.subagents[toolUseId]?.output = output }
                    }
                }
            } else if let agentId = payload.agentId, let toolUseId = payload.toolUseId {
                // Subagent 的工具调用完成 → 标记 done
                updateFromClaudeSession(sid) { session in
                    guard let key = session.subagents.values
                        .first(where: { $0.agentId == agentId })?.id else { return }
                    if let idx = session.subagents[key]?.toolCalls.firstIndex(where: { $0.id == toolUseId }) {
                        session.subagents[key]?.toolCalls[idx].isDone = true
                    }
                }
            }
            // F1: 实时 token 轮询
            if let surfaceId = claudeSessionIndex[sid] {
                AgentService.shared.tokenTracker?.pollLiveTokens(surfaceId: surfaceId)
            }
        case .notification:
            guard let sid else { return }
            if payload.notificationType == "idle_prompt" {
                updateFromClaudeSession(sid) { $0.state = .idle }
                if let surfaceId = claudeSessionIndex[sid] {
                    AgentService.shared.respawnController?.handleIdle(surfaceId: surfaceId)
                }
            }
        case .stop:
            guard let sid else { return }
            updateFromClaudeSession(sid) { $0.state = .idle }
            if let surfaceId = claudeSessionIndex[sid],
               let path = payload.transcriptPath {
                AgentService.shared.tokenTracker?.processStopEvent(
                    surfaceId: surfaceId,
                    transcriptPath: path,
                    model: "claude-sonnet-4"  // TODO: 从 AgentDefinition 读取
                )
            }
        case .subagentStart:
            // 将 agentId 绑定到对应的 SubagentInfo（通过 toolUseId 匹配）
            guard let sid, let agentId = payload.agentId else { break }
            if let toolUseId = payload.toolUseId {
                updateFromClaudeSession(sid) { $0.subagents[toolUseId]?.agentId = agentId }
            } else {
                // 回退：绑定到最早创建且尚未关联 agentId 的 subagent
                updateFromClaudeSession(sid) { session in
                    guard let key = session.subagents.values
                        .filter({ $0.agentId == nil && $0.state.isActive })
                        .sorted(by: { $0.startedAt < $1.startedAt })
                        .first?.id else { return }
                    session.subagents[key]?.agentId = agentId
                }
            }
        case .subagentStop:
            break
        default:
            break
        }
    }

    private func bindOrCreateSession(sessionId: String, cwd: String) {
        let candidates = candidateSurfaces(for: cwd)
        let indexCount = self.claudeSessionIndex.count
        Self.logger.warning("bindOrCreateSession: sid=\(sessionId) cwd=\(cwd) candidates=\(candidates.count) indexed=\(indexCount)")
        if let surfaceId = candidates.first {
            bindClaudeSession(surfaceId: surfaceId, claudeSessionId: sessionId)
            updateState(.working, surfaceId: surfaceId)
            Self.logger.warning("bindOrCreateSession: BOUND sid=\(sessionId) to surface=\(surfaceId)")
        } else {
            let sessionCount = self.sessions.count
            let cwds = self.sessions.values.map { $0.cwd }
            Self.logger.warning("bindOrCreateSession: no candidate, sessions=\(sessionCount) cwds=\(cwds)")
        }
    }
}
