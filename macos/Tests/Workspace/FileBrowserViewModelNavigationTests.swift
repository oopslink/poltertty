// macos/Tests/Workspace/FileBrowserViewModelNavigationTests.swift
import Testing
import Foundation
@testable import Ghostty

struct FileBrowserViewModelNavigationTests {

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
        defer { vm.stop(); try? FileManager.default.removeItem(at: dir) }
        try await Task.sleep(nanoseconds: 200_000_000)

        let nodes = vm.visibleNodes
        guard nodes.count >= 2 else { Issue.record("Expected at least 2 nodes"); return }

        vm.selectNode(id: nodes[0].node.id)
        vm.selectNext()
        #expect(vm.lastSelectedId == nodes[1].node.id)
    }

    @Test func testSelectPreviousMovesSelectionUp() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer { vm.stop(); try? FileManager.default.removeItem(at: dir) }
        try await Task.sleep(nanoseconds: 200_000_000)

        let nodes = vm.visibleNodes
        guard nodes.count >= 2 else { Issue.record("Expected at least 2 nodes"); return }

        vm.selectNode(id: nodes[1].node.id)
        vm.selectPrevious()
        #expect(vm.lastSelectedId == nodes[0].node.id)
    }

    @Test func testSelectNextClampsAtBottom() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer { vm.stop(); try? FileManager.default.removeItem(at: dir) }
        try await Task.sleep(nanoseconds: 200_000_000)

        let nodes = vm.visibleNodes
        guard let last = nodes.last else { Issue.record("Expected at least 1 node"); return }

        vm.selectNode(id: last.node.id)
        vm.selectNext()
        #expect(vm.lastSelectedId == last.node.id)
    }

    @Test func testSelectPreviousClampsAtTop() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer { vm.stop(); try? FileManager.default.removeItem(at: dir) }
        try await Task.sleep(nanoseconds: 200_000_000)

        let nodes = vm.visibleNodes
        guard let first = nodes.first else { Issue.record("Expected at least 1 node"); return }

        vm.selectNode(id: first.node.id)
        vm.selectPrevious()
        #expect(vm.lastSelectedId == first.node.id)
    }

    @Test func testSelectNextWithNoSelectionSelectsFirst() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer { vm.stop(); try? FileManager.default.removeItem(at: dir) }
        try await Task.sleep(nanoseconds: 200_000_000)

        let nodes = vm.visibleNodes
        guard let first = nodes.first else { Issue.record("Expected at least 1 node"); return }

        vm.clearSelection()
        vm.selectNext()
        #expect(vm.lastSelectedId == first.node.id)
    }

    @Test func testSelectPreviousWithNoSelectionSelectsFirst() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer { vm.stop(); try? FileManager.default.removeItem(at: dir) }
        try await Task.sleep(nanoseconds: 200_000_000)

        let nodes = vm.visibleNodes
        guard let first = nodes.first else { Issue.record("Expected at least 1 node"); return }

        vm.clearSelection()
        vm.selectPrevious()
        #expect(vm.lastSelectedId == first.node.id)
    }
}
