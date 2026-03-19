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

    @Test func testSelectNextMovesSelectionDown() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = FileBrowserViewModel(rootDir: dir.path)
        let nodes = vm.visibleNodes
        guard nodes.count >= 2 else { return }

        vm.selectedNodeId = nodes[0].node.id
        vm.selectNext()
        #expect(vm.selectedNodeId == nodes[1].node.id)
    }

    @Test func testSelectPreviousMovesSelectionUp() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = FileBrowserViewModel(rootDir: dir.path)
        let nodes = vm.visibleNodes
        guard nodes.count >= 2 else { return }

        vm.selectedNodeId = nodes[1].node.id
        vm.selectPrevious()
        #expect(vm.selectedNodeId == nodes[0].node.id)
    }

    @Test func testSelectNextClampsAtBottom() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = FileBrowserViewModel(rootDir: dir.path)
        let nodes = vm.visibleNodes
        guard let last = nodes.last else { return }

        vm.selectedNodeId = last.node.id
        vm.selectNext()
        #expect(vm.selectedNodeId == last.node.id)
    }

    @Test func testSelectPreviousClampsAtTop() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = FileBrowserViewModel(rootDir: dir.path)
        let nodes = vm.visibleNodes
        guard let first = nodes.first else { return }

        vm.selectedNodeId = first.node.id
        vm.selectPrevious()
        #expect(vm.selectedNodeId == first.node.id)
    }

    @Test func testSelectNextWithNoSelectionSelectsFirst() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = FileBrowserViewModel(rootDir: dir.path)
        let nodes = vm.visibleNodes
        guard let first = nodes.first else { return }

        vm.selectedNodeId = nil
        vm.selectNext()
        #expect(vm.selectedNodeId == first.node.id)
    }

    @Test func testSelectPreviousWithNoSelectionSelectsFirst() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = FileBrowserViewModel(rootDir: dir.path)
        let nodes = vm.visibleNodes
        guard let first = nodes.first else { return }

        vm.selectedNodeId = nil
        vm.selectPrevious()
        #expect(vm.selectedNodeId == first.node.id)
    }
}
