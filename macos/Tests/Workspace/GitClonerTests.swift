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

    // MARK: - Precheck

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitClonerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func precheckFailsForEmptyURL() async throws {
        let parent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: parent) }
        let cloner = GitCloner()
        let err = await withCheckedContinuation { (cont: CheckedContinuation<GitCloner.CloneError?, Never>) in
            cloner.start(
                options: .init(url: "", parentDir: parent.path, branch: nil, shallow: false),
                onProgress: { _ in },
                onComplete: { result in
                    if case .failure(let e) = result { cont.resume(returning: e) }
                    else { cont.resume(returning: nil) }
                }
            )
        }
        if case .invalidURL = err { } else { Issue.record("expected .invalidURL, got \(String(describing: err))") }
    }

    @Test func precheckFailsForUnparseableURL() async throws {
        let parent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: parent) }
        let cloner = GitCloner()
        let err = await withCheckedContinuation { (cont: CheckedContinuation<GitCloner.CloneError?, Never>) in
            cloner.start(
                options: .init(url: "   ", parentDir: parent.path, branch: nil, shallow: false),
                onProgress: { _ in },
                onComplete: { result in
                    if case .failure(let e) = result { cont.resume(returning: e) }
                    else { cont.resume(returning: nil) }
                }
            )
        }
        if case .invalidURL = err { } else { Issue.record("expected .invalidURL, got \(String(describing: err))") }
    }

    @Test func precheckFailsWhenParentMissing() async throws {
        let cloner = GitCloner()
        let err = await withCheckedContinuation { (cont: CheckedContinuation<GitCloner.CloneError?, Never>) in
            cloner.start(
                options: .init(
                    url: "https://example.com/foo/bar.git",
                    parentDir: "/definitely/does/not/exist/\(UUID().uuidString)",
                    branch: nil,
                    shallow: false
                ),
                onProgress: { _ in },
                onComplete: { result in
                    if case .failure(let e) = result { cont.resume(returning: e) }
                    else { cont.resume(returning: nil) }
                }
            )
        }
        if case .parentNotWritable = err { } else { Issue.record("expected .parentNotWritable, got \(String(describing: err))") }
    }

    @Test func precheckFailsWhenTargetExists() async throws {
        let parent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: parent) }
        let target = parent.appendingPathComponent("bar")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let cloner = GitCloner()
        let err = await withCheckedContinuation { (cont: CheckedContinuation<GitCloner.CloneError?, Never>) in
            cloner.start(
                options: .init(
                    url: "https://example.com/foo/bar.git",
                    parentDir: parent.path,
                    branch: nil,
                    shallow: false
                ),
                onProgress: { _ in },
                onComplete: { result in
                    if case .failure(let e) = result { cont.resume(returning: e) }
                    else { cont.resume(returning: nil) }
                }
            )
        }
        if case .targetExists = err { } else { Issue.record("expected .targetExists, got \(String(describing: err))") }
    }
}
