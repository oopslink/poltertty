import Testing
import Foundation
@testable import Ghostty

@Suite
struct SubagentTranscriptReaderTests {

    // MARK: - sanitizeCwd

    @Test func sanitize_absolutePath() {
        let result = SubagentTranscriptReader.sanitizeCwd("/Users/aaron/myapp")
        #expect(result == "Users-aaron-myapp")
    }

    @Test func sanitize_pathWithSpaces() {
        let result = SubagentTranscriptReader.sanitizeCwd("/Users/aaron/my project/app")
        #expect(result == "Users-aaron-my-project-app")
    }

    @Test func sanitize_trailingSlash() {
        let result = SubagentTranscriptReader.sanitizeCwd("/Users/aaron/app/")
        #expect(result == "Users-aaron-app-")  // trailing - 保留，与 Claude Code 行为一致
    }

    // MARK: - transcriptPath

    @Test func transcriptPath_returnsNilWhenNoClaudeSessionId() {
        var session = makeSession()
        session.claudeSessionId = nil
        var sub = makeSubagent()
        sub.agentId = "agent-abc"
        let path = SubagentTranscriptReader.transcriptPath(session: session, subagent: sub)
        #expect(path == nil)
    }

    @Test func transcriptPath_returnsNilWhenNoAgentId() {
        var session = makeSession()
        session.claudeSessionId = "sess-123"
        var sub = makeSubagent()
        sub.agentId = nil
        let path = SubagentTranscriptReader.transcriptPath(session: session, subagent: sub)
        #expect(path == nil)
    }

    @Test func transcriptPath_correctPath() {
        var session = makeSession()
        session.claudeSessionId = "sess-123"
        var sub = makeSubagent()
        sub.agentId = "agent-abc"
        let path = SubagentTranscriptReader.transcriptPath(session: session, subagent: sub)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let expected = "\(home)/.claude/projects/Users-aaron-myapp/sess-123/subagents/agent-agent-abc.jsonl"
        #expect(path == expected)
    }

    // MARK: - parseLines

    @Test func parse_skipsProgressLines() {
        let lines = [
            #"{"type":"progress","message":{"role":"assistant","content":[]}}"#,
        ]
        let transcript = SubagentTranscriptReader.parseLines(lines)
        #expect(transcript.turns.isEmpty)
    }

    @Test func parse_textBlock() {
        let lines = [
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hello"}],"usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#
        ]
        let transcript = SubagentTranscriptReader.parseLines(lines)
        #expect(transcript.turns.count == 1)
        #expect(transcript.turns[0].role == .assistant)
        if case .text(let t) = transcript.turns[0].blocks[0] {
            #expect(t == "Hello")
        } else {
            Issue.record("Expected text block")
        }
    }

    @Test func parse_toolUseBlock() {
        let lines = [
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu-1","name":"Read","input":{"file_path":"/foo.swift"}}],"usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#
        ]
        let transcript = SubagentTranscriptReader.parseLines(lines)
        #expect(transcript.turns.count == 1)
        if case .toolUse(let id, let name, _) = transcript.turns[0].blocks[0] {
            #expect(id == "tu-1")
            #expect(name == "Read")
        } else {
            Issue.record("Expected toolUse block")
        }
    }

    @Test func parse_toolResultExtractsText() {
        let lines = [
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tu-1","content":[{"type":"text","text":"file content"},{"type":"text","text":"more"}]}]}}"#
        ]
        let transcript = SubagentTranscriptReader.parseLines(lines)
        #expect(transcript.turns.count == 1)
        if case .toolResult(let tuId, let content) = transcript.turns[0].blocks[0] {
            #expect(tuId == "tu-1")
            #expect(content == "file content\nmore")
        } else {
            Issue.record("Expected toolResult block")
        }
    }

    @Test func parse_accumulatesTokenUsage() {
        let lines = [
            #"{"type":"assistant","message":{"role":"assistant","content":[],"usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":20,"cache_creation_input_tokens":5}}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[],"usage":{"input_tokens":200,"output_tokens":30,"cache_read_input_tokens":0,"cache_creation_input_tokens":10}}}"#
        ]
        let transcript = SubagentTranscriptReader.parseLines(lines)
        #expect(transcript.totalUsage.inputTokens == 300)
        #expect(transcript.totalUsage.outputTokens == 80)
        #expect(transcript.totalUsage.cacheReadTokens == 20)
        #expect(transcript.totalUsage.cacheWriteTokens == 15)
    }

    // MARK: - Helpers

    private func makeSession() -> AgentSession {
        AgentSession(
            id: UUID(),
            surfaceId: UUID(),
            definition: AgentDefinition(id: "test", name: "test", command: "claude", icon: "◆", hookCapability: .full),
            workspaceId: UUID(),
            cwd: "/Users/aaron/myapp"
        )
    }

    private func makeSubagent() -> SubagentInfo {
        SubagentInfo(id: "sub-1", name: "tester", agentType: "agent")
    }
}

// MARK: - EventEntry helpers（测试 recentEvents 逻辑，不依赖 SwiftUI）

@Suite
struct EventEntryTests {

    @Test func recentEvents_sortedDescending() {
        // 构造两个 subagent，各含若干 toolCalls
        var sub1 = SubagentInfo(id: "s1", name: "researcher", agentType: "agent")
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 2000)
        sub1.toolCalls = [
            ToolCallRecord(id: "tc1", toolName: "Read",   isDone: true,  startedAt: t1),
            ToolCallRecord(id: "tc2", toolName: "Write",  isDone: false, startedAt: t2),
        ]
        var sub2 = SubagentInfo(id: "s2", name: "coder", agentType: "agent")
        let t3 = Date(timeIntervalSince1970: 1500)
        sub2.toolCalls = [
            ToolCallRecord(id: "tc3", toolName: "Bash", isDone: true, startedAt: t3),
        ]
        let subagents: [String: SubagentInfo] = ["s1": sub1, "s2": sub2]
        let events = makeRecentEvents(subagents: subagents, limit: 50)
        // 降序：t2(2000) > t3(1500) > t1(1000)
        #expect(events.count == 3)
        #expect(events[0].toolName == "Write")
        #expect(events[1].toolName == "Bash")
        #expect(events[2].toolName == "Read")
    }

    @Test func recentEvents_truncatesToLimit() {
        var sub = SubagentInfo(id: "s1", name: "worker", agentType: "agent")
        sub.toolCalls = (0..<60).map { i in
            ToolCallRecord(id: "tc\(i)", toolName: "Tool\(i)", isDone: true,
                           startedAt: Date(timeIntervalSince1970: Double(i)))
        }
        let events = makeRecentEvents(subagents: ["s1": sub], limit: 50)
        #expect(events.count == 50)
        // 降序，最大时间戳（59）应排第一
        #expect(events[0].toolName == "Tool59")
    }

    // 辅助函数（镜像 SessionOverviewContent 中的 recentEvents 逻辑，便于纯函数测试）
    private func makeRecentEvents(subagents: [String: SubagentInfo], limit: Int) -> [RecentEventEntry] {
        subagents.values
            .flatMap { sub in sub.toolCalls.map { call in
                RecentEventEntry(time: call.startedAt,
                                 subagentName: String(sub.name.prefix(10)),
                                 toolName: call.toolName,
                                 isDone: call.isDone)
            }}
            .sorted { $0.time > $1.time }
            .prefix(limit)
            .map { $0 }
    }
}
