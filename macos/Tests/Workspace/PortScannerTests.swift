// macos/Tests/Workspace/PortScannerTests.swift
import Testing
import Foundation
@testable import Ghostty

struct PortScannerTests {

    // MARK: - parseListenOutput

    @Test func parsesListenOutputBasic() {
        let output = """
        p1234
        n*:3000
        p5678
        n127.0.0.1:8080
        """
        let entries = PortScanner.parseListenOutput(output)
        #expect(entries.count == 2)
        #expect(entries[0].port == 3000)
        #expect(entries[0].pid  == 1234)
        #expect(entries[1].port == 8080)
        #expect(entries[1].pid  == 5678)
    }

    @Test func ignoresNonPortLines() {
        let output = "pfoo\nnnotaport\n"
        let entries = PortScanner.parseListenOutput(output)
        #expect(entries.isEmpty)
    }

    // MARK: - parseCwdOutput

    @Test func parsesCwdOutput() {
        let output = """
        p1234
        n/Users/foo/myproject
        p5678
        n/Users/foo/other
        """
        let cwds = PortScanner.parseCwdOutput(output)
        #expect(cwds[1234] == "/Users/foo/myproject")
        #expect(cwds[5678] == "/Users/foo/other")
    }

    // MARK: - assignPorts

    @Test func assignsPortByRootDirPrefix() {
        let entries = [
            PortScanner.ListenEntry(port: 3000, pid: 1),
            PortScanner.ListenEntry(port: 8080, pid: 2),
        ]
        let cwds: [Int: String] = [
            1: "/Users/foo/project-a/server",
            2: "/Users/foo/project-b",
        ]
        let idA = UUID()
        let idB = UUID()
        let workspaces: [(id: UUID, rootDir: String)] = [
            (idA, "/Users/foo/project-a"),
            (idB, "/Users/foo/project-b"),
        ]
        let result = PortScanner.assignPorts(entries, cwds: cwds, workspaces: workspaces)
        #expect(result[idA] == [3000])
        #expect(result[idB] == [8080])
    }

    @Test func dropsPortWithNoCwdMatch() {
        let entries = [PortScanner.ListenEntry(port: 9999, pid: 99)]
        let cwds: [Int: String] = [99: "/tmp/unrelated"]
        let idA = UUID()
        let result = PortScanner.assignPorts(entries, cwds: cwds, workspaces: [(idA, "/Users/foo/project")])
        #expect(result.isEmpty)
    }

    @Test func expandsTildaInRootDir() {
        let entries = [PortScanner.ListenEntry(port: 3000, pid: 1)]
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let cwds: [Int: String] = [1: "\(home)/myproject/src"]
        let idA = UUID()
        let result = PortScanner.assignPorts(entries, cwds: cwds, workspaces: [(idA, "~/myproject")])
        #expect(result[idA] == [3000])
    }
}
