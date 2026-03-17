import Testing
import Foundation
@testable import Ghostty

struct GitStatusMonitorTests {

    // MARK: - porcelain 解析

    @Test func testParseCleanRepo() {
        let result = GitStatusParser.parse(porcelain: "")
        #expect(result.added == 0)
        #expect(result.modified == 0)
    }

    @Test func testParseUntracked() {
        let result = GitStatusParser.parse(porcelain: "?? new-file.txt\n")
        #expect(result.added == 1)
        #expect(result.modified == 0)
    }

    @Test func testParseStagedNew() {
        let result = GitStatusParser.parse(porcelain: "A  staged-new.txt\n")
        #expect(result.added == 1)
        #expect(result.modified == 0)
    }

    @Test func testParseStagedModified() {
        let result = GitStatusParser.parse(porcelain: "M  staged.txt\n")
        #expect(result.modified == 1)
        #expect(result.added == 0)
    }

    @Test func testParseUnstagedModified() {
        let result = GitStatusParser.parse(porcelain: " M unstaged.txt\n")
        #expect(result.modified == 1)
        #expect(result.added == 0)
    }

    @Test func testParseMixed() {
        let porcelain = """
        ?? untracked.txt
        A  staged-new.txt
        M  staged-mod.txt
         M unstaged-mod.txt
        """
        let result = GitStatusParser.parse(porcelain: porcelain)
        #expect(result.added == 2)    // ?? + A
        #expect(result.modified == 2) // M(index) + M(worktree)
    }

    @Test func testParseRenamedNotCountedAsAdded() {
        // R 不计入 added（有意设计，只统计严格 A 状态）
        let result = GitStatusParser.parse(porcelain: "R  old.txt -> new.txt\n")
        #expect(result.added == 0)
        #expect(result.modified == 0)
    }

    @Test func testParseShortLineTooShortIsIgnored() {
        // 少于2字符的行不处理，不应崩溃
        let result = GitStatusParser.parse(porcelain: "?\n")
        #expect(result.added == 0)
        #expect(result.modified == 0)
    }

    // MARK: - GitRepoStatus.empty
    // 注意：模块内已有 FileBrowser.GitStatus enum，故使用 GitRepoStatus 作为仓库级状态模型

    @Test func testGitStatusEmpty() {
        let s = GitRepoStatus.empty
        #expect(s.isGitRepo == false)
        #expect(s.branch == nil)
        #expect(s.added == 0)
        #expect(s.modified == 0)
    }

    // MARK: - updatePwd 空路径不重置状态
    // TODO: Task 2 实现后取消注释 GitStatusMonitor

    @Test func testUpdatePwdEmptyDoesNotReset() async throws {
        let monitor = GitStatusMonitor(pwd: NSHomeDirectory())
        // 等待初始化完成
        try await Task.sleep(nanoseconds: 200_000_000)
        let statusBefore = monitor.status
        monitor.updatePwd("")
        try await Task.sleep(nanoseconds: 200_000_000)
        // 状态应保持不变
        #expect(monitor.status == statusBefore)
    }
}
