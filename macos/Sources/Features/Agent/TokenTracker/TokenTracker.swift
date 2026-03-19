// macos/Sources/Features/Agent/TokenTracker/TokenTracker.swift
import Foundation
import OSLog

@MainActor
final class TokenTracker {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "TokenTracker"
    )

    private let sessionManager: AgentSessionManager
    private var lastPollDates: [UUID: Date] = [:]
    private static let pollInterval: TimeInterval = 5

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .prettyPrinted
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(sessionManager: AgentSessionManager) {
        self.sessionManager = sessionManager
    }

    /// 收到 Stop hook 时调用，解析 transcript 更新 token 用量
    func processStopEvent(surfaceId: UUID, transcriptPath: String, model: String) {
        Task.detached(priority: .utility) { [weak self] in
            let usage = await self?.parseTranscript(at: transcriptPath, model: model) ?? TokenUsage()
            await MainActor.run {
                self?.sessionManager.updateTokenUsage(surfaceId: surfaceId, usage: usage)
                // 持久化
                if let wsId = self?.sessionManager.session(for: surfaceId)?.workspaceId {
                    self?.persist(usage: usage, workspaceId: wsId)
                }
            }
        }
    }

    private func liveTranscriptPath(for session: AgentSession) -> String? {
        guard let claudeSessionId = session.claudeSessionId else { return nil }
        let sanitized = SubagentTranscriptReader.sanitizeCwd(session.cwd)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/projects/\(sanitized)/\(claudeSessionId).jsonl"
    }

    /// 节流轮询主 session transcript，在 postToolUse 和 Overview timer 时调用
    func pollLiveTokens(surfaceId: UUID) {
        let now = Date()
        if let last = lastPollDates[surfaceId],
           now.timeIntervalSince(last) < Self.pollInterval { return }
        lastPollDates[surfaceId] = now

        guard let session = sessionManager.session(for: surfaceId),
              let path = liveTranscriptPath(for: session) else { return }
        // TODO: 从 AgentDefinition 读取实际 model 名；暂时硬编码
        let model = "claude-sonnet-4"

        Task.detached(priority: .utility) { [weak self] in
            let usage = await self?.parseTranscript(at: path, model: model) ?? TokenUsage()
            guard usage.totalTokens > 0 else { return }
            await MainActor.run {
                self?.sessionManager.updateTokenUsage(surfaceId: surfaceId, usage: usage)
            }
        }
    }

    func clearThrottle(surfaceId: UUID) {
        lastPollDates.removeValue(forKey: surfaceId)
    }

    private func parseTranscript(at path: String, model: String) async -> TokenUsage {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return TokenUsage() }
        var usage = TokenUsage()
        var totalInput = 0, totalOutput = 0
        for line in content.components(separatedBy: .newlines) {
            guard let data = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            // usage 字段在 message.usage 中（Claude Code transcript 格式）
            let u = (event["message"] as? [String: Any])?["usage"] as? [String: Any]
                 ?? event["usage"] as? [String: Any]
            guard let u else { continue }
            totalInput  = (u["input_tokens"]  as? Int) ?? totalInput
            totalOutput = (u["output_tokens"] as? Int) ?? totalOutput
        }
        if totalInput > 0 || totalOutput > 0 {
            usage.add(input: totalInput, output: totalOutput, model: model)
        }
        return usage
    }

    func persist(usage: TokenUsage, workspaceId: UUID) {
        let dir = WorkspaceManager.shared.workspaceDir(for: workspaceId)
        let path = (dir as NSString).appendingPathComponent("llm_token_metering.json")
        guard let data = try? encoder.encode(usage) else { return }
        let tmp = path + ".tmp"
        try? data.write(to: URL(fileURLWithPath: tmp))
        try? FileManager.default.moveItem(atPath: tmp, toPath: path)
    }

    func load(for workspaceId: UUID) -> TokenUsage? {
        let dir = WorkspaceManager.shared.workspaceDir(for: workspaceId)
        let path = (dir as NSString).appendingPathComponent("llm_token_metering.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? decoder.decode(TokenUsage.self, from: data)
    }
}
