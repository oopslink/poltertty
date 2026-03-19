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

// MARK: - Claude .jsonl 解析

struct ClaudeJsonlParserTests {

    @Test func parsesLastUserMessage() {
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"hello"},"timestamp":"2026-03-20T10:00:00.000Z"}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"world"}]},"timestamp":"2026-03-20T10:00:01.000Z"}"#,
            #"{"type":"user","message":{"role":"user","content":"follow up"},"timestamp":"2026-03-20T10:00:02.000Z"}"#,
        ].joined(separator: "\n")
        let result = ClaudeJsonlParser.parseLastMessage(from: lines)
        #expect(result?.role == .user)
        #expect(result?.text == "follow up")
    }

    @Test func parsesLastAssistantMessage() {
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"question"},"timestamp":"2026-03-20T10:00:00.000Z"}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"answer"}]},"timestamp":"2026-03-20T10:00:01.000Z"}"#,
        ].joined(separator: "\n")
        let result = ClaudeJsonlParser.parseLastMessage(from: lines)
        #expect(result?.role == .assistant)
        #expect(result?.text == "answer")
    }

    @Test func ignoresProgressEntries() {
        let lines = [
            #"{"type":"progress","data":{"type":"hook_progress"}}"#,
            #"{"type":"user","message":{"role":"user","content":"real message"},"timestamp":"2026-03-20T10:00:00.000Z"}"#,
        ].joined(separator: "\n")
        let result = ClaudeJsonlParser.parseLastMessage(from: lines)
        #expect(result?.text == "real message")
    }

    @Test func truncatesLongText() {
        let longText = String(repeating: "x", count: 200)
        let line = "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"\(longText)\"},\"timestamp\":\"2026-03-20T10:00:00.000Z\"}"
        let result = ClaudeJsonlParser.parseLastMessage(from: line)
        #expect(result?.text.count == 120)
    }

    @Test func returnsNilForEmptyFile() {
        #expect(ClaudeJsonlParser.parseLastMessage(from: "") == nil)
    }

    @Test func handlesArrayContent() {
        let line = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"array text"},{"type":"thinking","thinking":"..."}]},"timestamp":"2026-03-20T10:00:00.000Z"}"#
        let result = ClaudeJsonlParser.parseLastMessage(from: line)
        #expect(result?.text == "array text")
    }
}

struct ClaudeSessionFileTests {

    @Test func parsesValidSessionFile() throws {
        let json = #"{"pid":12345,"sessionId":"abc-123","cwd":"/tmp/proj","startedAt":1700000000000}"#
        let entry = try ClaudeSessionFileParser.parse(json: json)
        #expect(entry.pid == 12345)
        #expect(entry.sessionId == "abc-123")
        #expect(entry.cwd == "/tmp/proj")
    }

    @Test func throwsOnMalformedJson() {
        #expect(throws: (any Error).self) {
            try ClaudeSessionFileParser.parse(json: "not-json")
        }
    }
}

// MARK: - OpenCode isAlive 时间窗口

struct OpenCodeAliveTests {

    @Test func isAliveIfUpdatedRecently() {
        let recent = Date().addingTimeInterval(-60)
        #expect(OpenCodeSessionProvider.isAliveByTime(lastUpdated: recent) == true)
    }

    @Test func isDeadIfUpdatedLongAgo() {
        let old = Date().addingTimeInterval(-400)
        #expect(OpenCodeSessionProvider.isAliveByTime(lastUpdated: old) == false)
    }

    @Test func isDeadAtBoundary() {
        let boundary = Date().addingTimeInterval(-301)
        #expect(OpenCodeSessionProvider.isAliveByTime(lastUpdated: boundary) == false)
    }
}
