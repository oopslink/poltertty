// macos/Sources/Features/Agent/Monitor/SubagentTranscriptReader.swift
import Foundation

// MARK: - Data Models

enum TranscriptBlock {
    case text(String)
    case toolUse(id: String, name: String, inputJSON: String)
    case toolResult(toolUseId: String, content: String)
}

struct TurnUsage {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int

    static let zero = TurnUsage(inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0)

    func adding(_ other: TurnUsage) -> TurnUsage {
        TurnUsage(
            inputTokens: inputTokens + other.inputTokens,
            outputTokens: outputTokens + other.outputTokens,
            cacheReadTokens: cacheReadTokens + other.cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens + other.cacheWriteTokens
        )
    }
}

struct TranscriptTurn: Identifiable {
    let id: UUID
    let role: Role
    let blocks: [TranscriptBlock]
    let usage: TurnUsage?
    let timestamp: Date

    enum Role { case user, assistant }
}

struct SubagentTranscript {
    let turns: [TranscriptTurn]
    let totalUsage: TurnUsage
}

// MARK: - Reader

final class SubagentTranscriptReader {

    /// 将 cwd 转换为 Claude Code 使用的目录名：将 / 和空格替换为 -，去掉开头的 -
    /// 将 cwd 转换为 Claude Code 使用的项目目录名
    /// Claude Code 只保留 ASCII 字母数字和 ._-，其余字符替换为 -
    /// 注意：不能用 CharacterSet.alphanumerics（它包含 Unicode 字母如中文）
    static func sanitizeCwd(_ cwd: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return String(cwd.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }

    /// 派生 JSONL 文件路径，任意必要字段为 nil 时返回 nil
    static func transcriptPath(session: AgentSession, subagent: SubagentInfo) -> String? {
        guard let claudeSessionId = session.claudeSessionId,
              let agentId = subagent.agentId else { return nil }
        let sanitized = sanitizeCwd(session.cwd)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/projects/\(sanitized)/\(claudeSessionId)/subagents/agent-\(agentId).jsonl"
    }

    /// 从磁盘读取并解析 JSONL，文件不存在时返回 nil
    static func read(session: AgentSession, subagent: SubagentInfo) async -> SubagentTranscript? {
        guard let path = transcriptPath(session: session, subagent: subagent) else { return nil }
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        return parseLines(lines)
    }

    /// 解析 JSONL 行数组（供测试直接调用）
    static func parseLines(_ lines: [String]) -> SubagentTranscript {
        var turns: [TranscriptTurn] = []
        var total = TurnUsage.zero
        let isoFormatter = ISO8601DateFormatter()

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type_ = obj["type"] as? String,
                  type_ != "progress",
                  let message = obj["message"] as? [String: Any],
                  let role = message["role"] as? String else { continue }

            let contentArr = message["content"] as? [[String: Any]] ?? []
            let blocks = contentArr.compactMap { parseBlock($0) }

            let usageObj = message["usage"] as? [String: Any]
            let usage = usageObj.map {
                TurnUsage(
                    inputTokens: $0["input_tokens"] as? Int ?? 0,
                    outputTokens: $0["output_tokens"] as? Int ?? 0,
                    cacheReadTokens: $0["cache_read_input_tokens"] as? Int ?? 0,
                    cacheWriteTokens: $0["cache_creation_input_tokens"] as? Int ?? 0
                )
            }

            let tsStr = obj["timestamp"] as? String ?? ""
            let timestamp = isoFormatter.date(from: tsStr) ?? Date()

            let turnRole: TranscriptTurn.Role = role == "assistant" ? .assistant : .user
            turns.append(TranscriptTurn(id: UUID(), role: turnRole, blocks: blocks, usage: usage, timestamp: timestamp))

            if turnRole == .assistant, let u = usage {
                total = total.adding(u)
            }
        }

        return SubagentTranscript(turns: turns, totalUsage: total)
    }

    // MARK: - Private

    private static func parseBlock(_ block: [String: Any]) -> TranscriptBlock? {
        guard let type_ = block["type"] as? String else { return nil }
        switch type_ {
        case "text":
            guard let text = block["text"] as? String else { return nil }
            return .text(text)
        case "tool_use":
            guard let id = block["id"] as? String,
                  let name = block["name"] as? String else { return nil }
            let inputObj = block["input"] ?? [:]
            let inputData = (try? JSONSerialization.data(withJSONObject: inputObj, options: [.sortedKeys])) ?? Data()
            let inputJSON = String(data: inputData, encoding: .utf8) ?? "{}"
            return .toolUse(id: id, name: name, inputJSON: inputJSON)
        case "tool_result":
            guard let tuId = block["tool_use_id"] as? String else { return nil }
            let contentBlocks = block["content"] as? [[String: Any]] ?? []
            let text = contentBlocks
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
            return .toolResult(toolUseId: tuId, content: text)
        default:
            return nil
        }
    }
}
