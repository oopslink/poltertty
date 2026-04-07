import Testing
import Foundation
@testable import Ghostty

// GitStatusParser / GitRepoStatus / GitStatusMonitor 尚未实现，测试暂时禁用。
// 实现后移除 disabled trait。
struct GitStatusMonitorTests {

    // MARK: - porcelain 解析

    @Test(.disabled("GitStatusParser pending implementation"))
    func testParseCleanRepo() {
        // let result = GitStatusParser.parse(porcelain: "")
        // #expect(result.added == 0)
        // #expect(result.modified == 0)
    }

    @Test(.disabled("GitStatusParser pending implementation"))
    func testParseUntracked() {
        // let result = GitStatusParser.parse(porcelain: "?? new-file.txt\n")
        // #expect(result.added == 1)
    }

    @Test(.disabled("GitStatusParser pending implementation"))
    func testParseStagedNew() {
        // let result = GitStatusParser.parse(porcelain: "A  staged-new.txt\n")
        // #expect(result.added == 1)
    }

    @Test(.disabled("GitStatusParser pending implementation"))
    func testParseStagedModified() {
        // let result = GitStatusParser.parse(porcelain: "M  staged.txt\n")
        // #expect(result.modified == 1)
    }

    @Test(.disabled("GitStatusParser pending implementation"))
    func testParseUnstagedModified() {
        // let result = GitStatusParser.parse(porcelain: " M unstaged.txt\n")
        // #expect(result.modified == 1)
    }

    @Test(.disabled("GitStatusParser pending implementation"))
    func testParseMixed() {
        // let result = GitStatusParser.parse(porcelain: ...)
        // #expect(result.added == 2)
    }

    @Test(.disabled("GitStatusParser pending implementation"))
    func testParseRenamedNotCountedAsAdded() {
        // let result = GitStatusParser.parse(porcelain: "R  old.txt -> new.txt\n")
        // #expect(result.added == 0)
    }

    @Test(.disabled("GitStatusParser pending implementation"))
    func testParseShortLineTooShortIsIgnored() {
        // let result = GitStatusParser.parse(porcelain: "?\n")
        // #expect(result.added == 0)
    }

    @Test(.disabled("GitRepoStatus pending implementation"))
    func testGitRepoStatusEmpty() {
        // let s = GitRepoStatus.empty
        // #expect(s.isGitRepo == false)
    }

    @Test(.disabled("GitStatusMonitor pending implementation"))
    func testUpdatePwdEmptyDoesNotReset() async throws {
        // let monitor = GitStatusMonitor(pwd: NSHomeDirectory())
        // try await Task.sleep(nanoseconds: 200_000_000)
        // monitor.updatePwd("")
        // ...
    }
}
