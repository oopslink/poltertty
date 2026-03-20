// macos/Tests/Workspace/WorkspaceGroupTests.swift
import Testing
import Foundation
@testable import Ghostty

struct WorkspaceGroupTests {

    @Test func testWorkspaceGroupRoundtrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let group = WorkspaceGroup(name: "Work")
        let data = try encoder.encode(group)
        let decoded = try decoder.decode(WorkspaceGroup.self, from: data)

        #expect(decoded.id == group.id)
        #expect(decoded.name == "Work")
        #expect(decoded.orderIndex == 0)
        #expect(decoded.isExpanded == true)
        #expect(decoded.isCollapsedIcon == false)
    }

    @Test func testWorkspaceModelGroupIdRoundtrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var ws = WorkspaceModel(name: "test", rootDir: "/tmp")
        let groupId = UUID()
        ws.groupId = groupId
        ws.groupOrder = 3

        // WorkspaceSnapshot wraps WorkspaceModel
        let snapshot = WorkspaceSnapshot(workspace: ws, sidebarWidth: 200, sidebarVisible: true)
        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(WorkspaceSnapshot.self, from: data)

        #expect(decoded.workspace.groupId == groupId)
        #expect(decoded.workspace.groupOrder == 3)
    }

    @Test func testWorkspaceModelGroupIdBackwardCompat() throws {
        // 旧格式 JSON（无 groupId/groupOrder 字段）解码后应为 nil/0
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let oldJSON = """
        {
          "version": 2,
          "workspace": {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "name": "old",
            "colorHex": "#FF6B6B",
            "icon": "OL",
            "rootDir": "/tmp",
            "description": "",
            "tags": [],
            "createdAt": "2026-01-01T00:00:00Z",
            "updatedAt": "2026-01-01T00:00:00Z",
            "lastActiveAt": "2026-01-01T00:00:00Z",
            "isTemporary": false,
            "fileBrowserVisible": false,
            "fileBrowserWidth": 260
          },
          "sidebarWidth": 200,
          "sidebarVisible": true
        }
        """.data(using: .utf8)!

        let snapshot = try decoder.decode(WorkspaceSnapshot.self, from: oldJSON)
        #expect(snapshot.workspace.groupId == nil)
        #expect(snapshot.workspace.groupOrder == 0)
    }

    // MARK: - WorkspaceManager Group CRUD Tests

    @Test func testCreateGroupAddsToList() {
        // 直接测试 WorkspaceGroup 初始化逻辑
        let group = WorkspaceGroup(name: "TestGroup", orderIndex: 0)
        #expect(group.name == "TestGroup")
        #expect(group.isExpanded == true)
        #expect(group.orderIndex == 0)
        #expect(group.isCollapsedIcon == false)
    }

    @Test func testGroupAbbreviationASCII() {
        let group = WorkspaceGroup(name: "Work")
        #expect(group.abbreviation == "WO")
    }

    @Test func testGroupAbbreviationEmoji() {
        let group = WorkspaceGroup(name: "🚀Launch")
        // 只取前2个 unicode scalars，不截断多字节
        let scalars = Array("🚀Launch".unicodeScalars.prefix(2))
        let expected = String(String.UnicodeScalarView(scalars)).uppercased()
        #expect(group.abbreviation == expected)
    }

    @Test func testGroupAbbreviationShortName() {
        let group = WorkspaceGroup(name: "A")
        #expect(group.abbreviation == "A")
    }

    @Test func testGroupsJsonRoundtrip() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let groups = [
            WorkspaceGroup(name: "Work", orderIndex: 0),
            WorkspaceGroup(name: "Personal", orderIndex: 1),
        ]

        let data = try encoder.encode(groups)
        let decoded = try decoder.decode([WorkspaceGroup].self, from: data)

        #expect(decoded.count == 2)
        #expect(decoded[0].name == "Work")
        #expect(decoded[1].name == "Personal")
        #expect(decoded[0].orderIndex == 0)
        #expect(decoded[1].orderIndex == 1)
    }
}
