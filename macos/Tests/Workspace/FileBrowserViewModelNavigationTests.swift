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
        guard nodes.count >= 2 else {
            Issue.record("Expected at least 2 nodes, got \(nodes.count)")
            return
        }

        vm.selectedNodeId = nodes[0].node.id
        vm.selectNext()
        #expect(vm.selectedNodeId == nodes[1].node.id)
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
        guard nodes.count >= 2 else {
            Issue.record("Expected at least 2 nodes, got \(nodes.count)")
            return
        }

        vm.selectedNodeId = nodes[1].node.id
        vm.selectPrevious()
        #expect(vm.selectedNodeId == nodes[0].node.id)
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
        guard let last = nodes.last else {
            Issue.record("Expected at least 1 node, got 0")
            return
        }

        vm.selectedNodeId = last.node.id
        vm.selectNext()
        #expect(vm.selectedNodeId == last.node.id)
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
        guard let first = nodes.first else {
            Issue.record("Expected at least 1 node, got 0")
            return
        }

        vm.selectedNodeId = first.node.id
        vm.selectPrevious()
        #expect(vm.selectedNodeId == first.node.id)
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
        guard let first = nodes.first else {
            Issue.record("Expected at least 1 node, got 0")
            return
        }

        vm.selectedNodeId = nil
        vm.selectNext()
        #expect(vm.selectedNodeId == first.node.id)
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
        guard let first = nodes.first else {
            Issue.record("Expected at least 1 node, got 0")
            return
        }

        vm.selectedNodeId = nil
        vm.selectPrevious()
        #expect(vm.selectedNodeId == first.node.id)
    }
}
