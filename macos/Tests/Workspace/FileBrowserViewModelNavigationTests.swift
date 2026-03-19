// macos/Tests/Workspace/FileBrowserViewModelNavigationTests.swift
import Testing
import Foundation
@testable import Ghostty

struct FileBrowserViewModelNavigationTests {

    // 创建临时目录：rootDir/a.txt, rootDir/b.txt, rootDir/c.txt
    private func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        for name in ["a.txt", "b.txt", "c.txt"] {
            FileManager.default.createFile(atPath: tmp.appendingPathComponent(name).path, contents: nil)
        }
        return tmp
    }

    @Test func testSelectNextMovesSelectionDown() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer {
            vm.stop()
            try? FileManager.default.removeItem(at: dir)
        }
        try await Task.sleep(nanoseconds: 200_000_000)  // wait for async reload

        let nodes = vm.visibleNodes
        guard nodes.count >= 2 else { Issue.record("Expected at least 2 nodes, got \(nodes.count)"); return }

        vm.selectNode(id: nodes[0].node.id)
        vm.selectNext()
        #expect(vm.lastSelectedId == nodes[1].node.id)
    }

    @Test func testSelectPreviousMovesSelectionUp() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer {
            vm.stop()
            try? FileManager.default.removeItem(at: dir)
        }
        try await Task.sleep(nanoseconds: 200_000_000)  // wait for async reload

        let nodes = vm.visibleNodes
        guard nodes.count >= 2 else { Issue.record("Expected at least 2 nodes, got \(nodes.count)"); return }

        vm.selectNode(id: nodes[1].node.id)
        vm.selectPrevious()
        #expect(vm.lastSelectedId == nodes[0].node.id)
    }

    @Test func testSelectNextClampsAtBottom() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer {
            vm.stop()
            try? FileManager.default.removeItem(at: dir)
        }
        try await Task.sleep(nanoseconds: 200_000_000)  // wait for async reload

        let nodes = vm.visibleNodes
        guard let last = nodes.last else { Issue.record("Expected at least 1 node, got 0"); return }

        vm.selectNode(id: last.node.id)
        vm.selectNext()
        #expect(vm.lastSelectedId == last.node.id)
    }

    @Test func testSelectPreviousClampsAtTop() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer {
            vm.stop()
            try? FileManager.default.removeItem(at: dir)
        }
        try await Task.sleep(nanoseconds: 200_000_000)  // wait for async reload

        let nodes = vm.visibleNodes
        guard let first = nodes.first else { Issue.record("Expected at least 1 node, got 0"); return }

        vm.selectNode(id: first.node.id)
        vm.selectPrevious()
        #expect(vm.lastSelectedId == first.node.id)
    }

    @Test func testSelectNextWithNoSelectionSelectsFirst() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer {
            vm.stop()
            try? FileManager.default.removeItem(at: dir)
        }
        try await Task.sleep(nanoseconds: 200_000_000)  // wait for async reload

        let nodes = vm.visibleNodes
        guard let first = nodes.first else { Issue.record("Expected at least 1 node, got 0"); return }

        vm.clearSelection()
        vm.selectNext()
        #expect(vm.lastSelectedId == first.node.id)
    }

    @Test func testSelectPreviousWithNoSelectionSelectsFirst() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer {
            vm.stop()
            try? FileManager.default.removeItem(at: dir)
        }
        try await Task.sleep(nanoseconds: 200_000_000)  // wait for async reload

        let nodes = vm.visibleNodes
        guard let first = nodes.first else { Issue.record("Expected at least 1 node, got 0"); return }

        vm.clearSelection()
        vm.selectPrevious()
        #expect(vm.lastSelectedId == first.node.id)
    }

    // MARK: - 批量选择测试

    @Test func testToggleSelectionAddsAndRemoves() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer {
            vm.stop()
            try? FileManager.default.removeItem(at: dir)
        }
        try await Task.sleep(nanoseconds: 200_000_000)  // wait for async reload

        let nodes = vm.visibleNodes
        guard nodes.count >= 2 else { Issue.record("Expected at least 2 nodes, got \(nodes.count)"); return }

        let id0 = nodes[0].node.id
        let id1 = nodes[1].node.id

        vm.selectNode(id: id0)
        #expect(vm.selectedNodeIds.count == 1)

        vm.toggleSelection(id: id1)
        #expect(vm.selectedNodeIds.count == 2)
        #expect(vm.selectedNodeIds.contains(id0))
        #expect(vm.selectedNodeIds.contains(id1))
        #expect(vm.lastSelectedId == id1)

        vm.toggleSelection(id: id0)
        #expect(vm.selectedNodeIds.count == 1)
        #expect(!vm.selectedNodeIds.contains(id0))
    }

    @Test func testExtendSelectionSelectsRange() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer {
            vm.stop()
            try? FileManager.default.removeItem(at: dir)
        }
        try await Task.sleep(nanoseconds: 200_000_000)  // wait for async reload

        let nodes = vm.visibleNodes
        guard nodes.count >= 3 else { Issue.record("Expected at least 3 nodes, got \(nodes.count)"); return }

        vm.selectNode(id: nodes[0].node.id)
        vm.extendSelection(to: nodes[2].node.id)
        #expect(vm.selectedNodeIds.count == 3)
        #expect(vm.lastSelectedId == nodes[2].node.id)
    }

    @Test func testSelectAllSelectsAllVisibleNodes() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer {
            vm.stop()
            try? FileManager.default.removeItem(at: dir)
        }
        try await Task.sleep(nanoseconds: 200_000_000)  // wait for async reload

        let nodes = vm.visibleNodes
        guard !nodes.isEmpty else { Issue.record("Expected at least 1 node, got 0"); return }

        vm.selectAll()
        #expect(vm.selectedNodeIds.count == nodes.count)
    }

    @Test func testClearSelectionClearsAll() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer {
            vm.stop()
            try? FileManager.default.removeItem(at: dir)
        }
        try await Task.sleep(nanoseconds: 200_000_000)  // wait for async reload

        let nodes = vm.visibleNodes
        guard !nodes.isEmpty else { Issue.record("Expected at least 1 node, got 0"); return }

        vm.selectAll()
        vm.clearSelection()
        #expect(vm.selectedNodeIds.isEmpty)
        #expect(vm.lastSelectedId == nil)
    }

    @Test func testSelectNextClearsMultiSelection() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer {
            vm.stop()
            try? FileManager.default.removeItem(at: dir)
        }
        try await Task.sleep(nanoseconds: 200_000_000)  // wait for async reload

        let nodes = vm.visibleNodes
        guard nodes.count >= 2 else { Issue.record("Expected at least 2 nodes, got \(nodes.count)"); return }

        vm.selectAll()
        #expect(vm.selectedNodeIds.count > 1)

        // 直接调用 selectNext()，验证方向键本身会清空多选
        vm.selectNext()
        // 方向键后应清空多选，只剩一个（从 lastSelectedId 位置移动一步）
        #expect(vm.selectedNodeIds.count == 1)
    }
}
