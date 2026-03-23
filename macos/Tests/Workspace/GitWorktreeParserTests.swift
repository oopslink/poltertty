import Testing
import Foundation
@testable import Ghostty

struct GitWorktreeParserTests {

    @Test func testParseSingleMainWorktree() {
        let output = """
        worktree /Users/dev/project
        HEAD abc123def456
        branch refs/heads/main

        """
        let result = GitWorktreeParser.parse(porcelain: output, currentPath: "/Users/dev/project")
        #expect(result.count == 1)
        #expect(result[0].path == "/Users/dev/project")
        #expect(result[0].branch == "main")
        #expect(result[0].isMain == true)
        #expect(result[0].isCurrent == true)
    }

    @Test func testParseMultipleWorktrees() {
        let output = """
        worktree /Users/dev/project
        HEAD abc123
        branch refs/heads/main

        worktree /Users/dev/project/.worktrees/feature-auth
        HEAD def456
        branch refs/heads/feature/auth

        worktree /Users/dev/project/.worktrees/detached-work
        HEAD 789abc
        detached

        """
        let result = GitWorktreeParser.parse(porcelain: output, currentPath: "/Users/dev/project/.worktrees/feature-auth")
        #expect(result.count == 3)
        #expect(result[0].isMain == true)
        #expect(result[0].isCurrent == false)
        #expect(result[0].branch == "main")
        #expect(result[1].isMain == false)
        #expect(result[1].isCurrent == true)
        #expect(result[1].branch == "feature/auth")
        #expect(result[2].branch == nil)
        #expect(result[2].isMain == false)
    }

    @Test func testParseEmpty() {
        let result = GitWorktreeParser.parse(porcelain: "", currentPath: "/tmp")
        #expect(result.isEmpty)
    }

    @Test func testParseBareSkipped() {
        let output = """
        worktree /Users/dev/bare-repo
        HEAD abc123
        bare

        worktree /Users/dev/bare-repo/.worktrees/work
        HEAD def456
        branch refs/heads/main

        """
        let result = GitWorktreeParser.parse(porcelain: output, currentPath: "/Users/dev/bare-repo/.worktrees/work")
        #expect(result.count == 1)
        #expect(result[0].branch == "main")
    }

    @Test func testPathNormalization() {
        let output = """
        worktree /Users/dev/project/
        HEAD abc123
        branch refs/heads/main

        """
        let result = GitWorktreeParser.parse(porcelain: output, currentPath: "/Users/dev/project")
        #expect(result[0].isCurrent == true)
    }
}
