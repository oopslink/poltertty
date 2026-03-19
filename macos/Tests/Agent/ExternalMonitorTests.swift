// macos/Tests/Agent/ExternalMonitorTests.swift
import Testing
import Foundation
@testable import Ghostty

struct ExternalToolTypeTests {

    @Test func claudeCodeBadge() {
        #expect(ExternalToolType.claudeCode.badge == "[CC]")
    }

    @Test func openCodeBadge() {
        #expect(ExternalToolType.openCode.badge == "[OC]")
    }

    @Test func geminiCliBadge() {
        #expect(ExternalToolType.geminiCli.badge == "[GM]")
    }

    @Test func rawValues() {
        #expect(ExternalToolType.claudeCode.rawValue == "claude-code")
        #expect(ExternalToolType.openCode.rawValue   == "opencode")
        #expect(ExternalToolType.geminiCli.rawValue  == "gemini-cli")
    }
}

struct ExternalSessionRecordTests {

    @Test func isIdentifiableById() {
        let r = ExternalSessionRecord(
            id: "test-id", toolType: .claudeCode, pid: 123,
            cwd: "/tmp/proj", startedAt: Date(), isAlive: true
        )
        #expect(r.id == "test-id")
    }

    @Test func lastMessageTextCanBeTruncated() {
        let longText = String(repeating: "a", count: 200)
        let msg = ExternalSessionRecord.LastMessage(
            role: .user, text: String(longText.prefix(120)), timestamp: Date()
        )
        #expect(msg.text.count <= 120)
    }
}
