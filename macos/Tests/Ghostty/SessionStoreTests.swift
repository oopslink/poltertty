import Testing
import Foundation
@testable import Ghostty

@Suite
struct SessionStoreTests {

    // 使用临时目录隔离测试
    private func makeTempStore() -> (SessionStore, URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("poltertty-test-\(UUID())")
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return (SessionStore(baseDir: tmp.path), tmp)
    }

    @Test func saveAndLoad_roundTrip() throws {
        let (store, tmp) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let wsId = UUID()
        let ps = PersistedSession(
            id: UUID(),
            workspaceId: wsId,
            definitionId: "claude-code",
            agentName: "Claude Code",
            agentCommand: "claude",
            agentIcon: "◆",
            cwd: "/Users/test/project",
            claudeSessionId: "sess-abc",
            startedAt: Date(timeIntervalSince1970: 1000),
            finishedAt: Date(timeIntervalSince1970: 2000),
            tokenUsage: TokenUsage(),
            subagents: []
        )
        store.save(ps)

        let loaded = store.load(for: wsId)
        #expect(loaded.count == 1)
        #expect(loaded[0].id == ps.id)
        #expect(loaded[0].claudeSessionId == "sess-abc")
        #expect(loaded[0].cwd == "/Users/test/project")
    }

    @Test func load_returnsDescendingByFinishedAt() throws {
        let (store, tmp) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let wsId = UUID()
        let older = makeSession(wsId: wsId, finishedAt: Date(timeIntervalSince1970: 1000))
        let newer = makeSession(wsId: wsId, finishedAt: Date(timeIntervalSince1970: 2000))
        store.save(older)
        store.save(newer)

        let loaded = store.load(for: wsId)
        #expect(loaded.count == 2)
        #expect(loaded[0].finishedAt > loaded[1].finishedAt)  // newer first
    }

    @Test func load_limitsTo20() throws {
        let (store, tmp) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let wsId = UUID()
        for i in 0..<25 {
            store.save(makeSession(wsId: wsId, finishedAt: Date(timeIntervalSince1970: Double(i * 100))))
        }
        let loaded = store.load(for: wsId)
        #expect(loaded.count == 20)
    }

    @Test func toAgentSession_mapsFieldsCorrectly() {
        let wsId = UUID()
        let sub = PersistedSubagent(
            id: "sub-1", name: "researcher", agentType: "agent", agentId: "aid-1",
            startedAt: Date(timeIntervalSince1970: 100),
            finishedAt: Date(timeIntervalSince1970: 200),
            exitCode: 0, toolCallCount: 5, output: "done"
        )
        let ps = PersistedSession(
            id: UUID(), workspaceId: wsId, definitionId: "claude-code",
            agentName: "Claude Code", agentCommand: "claude", agentIcon: "◆",
            cwd: "/tmp", claudeSessionId: "sess-xyz",
            startedAt: Date(timeIntervalSince1970: 0),
            finishedAt: Date(timeIntervalSince1970: 300),
            tokenUsage: TokenUsage(), subagents: [sub]
        )
        let session = ps.toAgentSession()
        #expect(session.cwd == "/tmp")
        #expect(session.claudeSessionId == "sess-xyz")
        if case .done(let code) = session.state { #expect(code == 0) }
        else { Issue.record("Expected .done state") }
        #expect(session.subagents.count == 1)
        let restoredSub = session.subagents["sub-1"]!
        #expect(restoredSub.name == "researcher")
        #expect(restoredSub.output == "done")
    }

    // MARK: - Helpers
    private func makeSession(wsId: UUID, finishedAt: Date) -> PersistedSession {
        PersistedSession(
            id: UUID(), workspaceId: wsId, definitionId: "claude-code",
            agentName: "Claude Code", agentCommand: "claude", agentIcon: "◆",
            cwd: "/tmp", claudeSessionId: nil,
            startedAt: finishedAt.addingTimeInterval(-60),
            finishedAt: finishedAt,
            tokenUsage: TokenUsage(), subagents: []
        )
    }
}
