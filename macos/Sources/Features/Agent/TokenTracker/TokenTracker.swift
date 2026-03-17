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

    private func parseTranscript(at path: String, model: String) async -> TokenUsage {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return TokenUsage() }
        var usage = TokenUsage()
        var totalInput = 0, totalOutput = 0
        for line in content.components(separatedBy: .newlines) {
            guard let data = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let u = event["usage"] as? [String: Any] else { continue }
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
