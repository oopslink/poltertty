// macos/Sources/Features/Agent/Monitor/SessionStore.swift
import Foundation
import OSLog

// MARK: - Data Models

struct PersistedSession: Codable, Identifiable {
    let id: UUID
    let workspaceId: UUID
    let definitionId: String      // 用于 UI 标识
    let agentName: String
    let agentCommand: String      // 保留 command 避免 AgentRegistry 查找失败时信息丢失
    let agentIcon: String         // 保留 icon
    let cwd: String
    let claudeSessionId: String?
    let startedAt: Date
    let finishedAt: Date
    var tokenUsage: TokenUsage
    let subagents: [PersistedSubagent]
}

struct PersistedSubagent: Codable, Identifiable {
    let id: String
    let name: String
    let agentType: String
    let agentId: String?
    let startedAt: Date
    let finishedAt: Date?
    let exitCode: Int32?
    let toolCallCount: Int
    let output: String?
}

// MARK: - AgentSession → PersistedSession 转换

extension AgentSession {
    func toPersistedSession() -> PersistedSession? {
        // 只持久化已完成的 session
        guard case .done = state else { return nil }
        let finishedAt = subagents.values.compactMap({ $0.finishedAt }).max() ?? lastEventAt
        let persistedSubs = subagents.values.map { sub -> PersistedSubagent in
            let exitCode: Int32? = {
                if case .done(let code) = sub.state { return code }
                return nil
            }()
            return PersistedSubagent(
                id: sub.id, name: sub.name, agentType: sub.agentType,
                agentId: sub.agentId,
                startedAt: sub.startedAt, finishedAt: sub.finishedAt,
                exitCode: exitCode,
                toolCallCount: sub.toolCalls.count,
                output: sub.output
            )
        }.sorted { $0.startedAt < $1.startedAt }

        return PersistedSession(
            id: id, workspaceId: workspaceId,
            definitionId: definition.id, agentName: definition.name,
            agentCommand: definition.command, agentIcon: definition.icon,
            cwd: cwd, claudeSessionId: claudeSessionId,
            startedAt: startedAt, finishedAt: finishedAt,
            tokenUsage: tokenUsage, subagents: persistedSubs
        )
    }
}

// MARK: - PersistedSession → AgentSession 转換（只读 Overview）

extension PersistedSession {
    /// 注意：此方法直接用保存的 command/icon 构建 AgentDefinition，无需访问 @MainActor AgentRegistry
    func toAgentSession() -> AgentSession {
        let def = AgentDefinition(id: definitionId, name: agentName,
                                  command: agentCommand, icon: agentIcon, hookCapability: .full)
        var s = AgentSession(
            id: id, surfaceId: UUID(),
            definition: def, workspaceId: workspaceId, cwd: cwd
        )
        s.state = .done(exitCode: 0)
        s.claudeSessionId = claudeSessionId
        s.startedAt = startedAt
        s.lastEventAt = finishedAt
        s.tokenUsage = tokenUsage
        s.subagents = Dictionary(uniqueKeysWithValues: subagents.map { ps in
            var sub = SubagentInfo(id: ps.id, name: ps.name, agentType: ps.agentType)
            sub.agentId = ps.agentId
            sub.startedAt = ps.startedAt
            sub.finishedAt = ps.finishedAt
            sub.state = ps.exitCode != nil ? .done(exitCode: ps.exitCode!) : .done(exitCode: 0)
            sub.output = ps.output
            sub.isHistorical = true    // 标记为只读历史记录，供 TraceContent 检测
            return (ps.id, sub)
        })
        return s
    }
}

// MARK: - SessionStore

final class SessionStore {
    static let shared = SessionStore()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "poltertty",
                                category: "SessionStore")
    private let baseDir: String

    /// 生产环境使用 WorkspaceManager 路径；测试时可注入临时目录
    init(baseDir: String = PolterttyConfig.shared.workspaceDir) {
        self.baseDir = baseDir
    }

    // MARK: - Public API

    func save(_ session: AgentSession) {
        guard let ps = session.toPersistedSession() else { return }
        save(ps)
    }

    func save(_ ps: PersistedSession) {
        let dir = sessionsDir(for: ps.workspaceId)
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let path = sessionPath(dir: dir, id: ps.id)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(ps)
            let tmp = path + ".tmp"
            try data.write(to: URL(fileURLWithPath: tmp), options: .atomic)
            try FileManager.default.moveItem(atPath: tmp, toPath: path)
        } catch {
            logger.error("SessionStore.save failed: \(error)")
        }
    }

    /// 读取最近 20 条，按 finishedAt 降序
    func load(for workspaceId: UUID) -> [PersistedSession] {
        let dir = sessionsDir(for: workspaceId)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return files
            .filter { $0.hasSuffix(".json") }
            .compactMap { name -> PersistedSession? in
                let path = (dir as NSString).appendingPathComponent(name)
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
                return try? decoder.decode(PersistedSession.self, from: data)
            }
            .sorted { $0.finishedAt > $1.finishedAt }
            .prefix(20)
            .map { $0 }
    }

    // MARK: - Private

    private func sessionsDir(for workspaceId: UUID) -> String {
        let wsDir = (baseDir as NSString).appendingPathComponent(workspaceId.uuidString)
        return (wsDir as NSString).appendingPathComponent("sessions")
    }

    private func sessionPath(dir: String, id: UUID) -> String {
        (dir as NSString).appendingPathComponent("\(id.uuidString).json")
    }
}
