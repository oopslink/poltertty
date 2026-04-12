// macos/Tests/Workspace/GitClonerTests.swift
import Testing
import Foundation
@testable import Ghostty

struct GitClonerTests {

    // MARK: - extractRepoName

    @Test func extractsRepoNameFromHttpsWithDotGit() {
        #expect(GitCloner.extractRepoName(from: "https://github.com/foo/bar.git") == "bar")
    }

    @Test func extractsRepoNameFromHttpsWithoutDotGit() {
        #expect(GitCloner.extractRepoName(from: "https://github.com/foo/bar") == "bar")
    }

    @Test func extractsRepoNameFromScpStyleSsh() {
        #expect(GitCloner.extractRepoName(from: "git@github.com:foo/bar.git") == "bar")
    }

    @Test func extractsRepoNameFromSshUrl() {
        #expect(GitCloner.extractRepoName(from: "ssh://git@host:22/foo/bar.git") == "bar")
    }

    @Test func extractsRepoNameWithTrailingSlash() {
        #expect(GitCloner.extractRepoName(from: "https://host/foo/bar/") == "bar")
    }

    @Test func extractsRepoNameWithMultipleDotGitSegments() {
        #expect(GitCloner.extractRepoName(from: "https://host/foo/bar.git/") == "bar")
    }

    @Test func returnsNilForEmpty() {
        #expect(GitCloner.extractRepoName(from: "") == nil)
    }

    @Test func returnsNilForWhitespace() {
        #expect(GitCloner.extractRepoName(from: "   ") == nil)
    }
}
