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

    // MARK: - Real git subprocess

    /// 创建一个本地 bare repo 作为 clone 源。
    private func makeBareSourceRepo() throws -> (path: String, cleanup: () -> Void) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitClonerSrc-\(UUID().uuidString)")
        let work = root.appendingPathComponent("work")
        let bare = root.appendingPathComponent("bare.git")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        func runGit(_ args: [String], cwd: URL? = nil) throws {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = args
            if let cwd { p.currentDirectoryURL = cwd }
            p.environment = [
                "HOME": NSHomeDirectory(),
                "GIT_AUTHOR_NAME": "test",
                "GIT_AUTHOR_EMAIL": "test@test",
                "GIT_COMMITTER_NAME": "test",
                "GIT_COMMITTER_EMAIL": "test@test",
            ]
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus != 0 {
                throw NSError(domain: "git", code: Int(p.terminationStatus))
            }
        }

        try runGit(["init", "-q", "-b", "main", work.path])
        let readme = work.appendingPathComponent("README.md")
        try "hello".write(to: readme, atomically: true, encoding: .utf8)
        try runGit(["add", "."], cwd: work)
        try runGit(["commit", "-q", "-m", "init"], cwd: work)
        try runGit(["clone", "-q", "--bare", work.path, bare.path])

        return (bare.path, { try? FileManager.default.removeItem(at: root) })
    }

    @Test func clonesLocalBareRepoSuccessfully() async throws {
        let parent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: parent) }
        let src = try makeBareSourceRepo()
        defer { src.cleanup() }

        let cloner = GitCloner()
        let result = await withCheckedContinuation { (cont: CheckedContinuation<Result<String, GitCloner.CloneError>, Never>) in
            cloner.start(
                options: .init(url: src.path, parentDir: parent.path, branch: nil, shallow: false),
                onProgress: { _ in },
                onComplete: { cont.resume(returning: $0) }
            )
        }

        switch result {
        case .success(let path):
            #expect(path == (parent.path as NSString).appendingPathComponent("bare"))
            #expect(FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(".git")))
        case .failure(let e):
            Issue.record("expected success, got \(e)")
        }
    }

    @Test func cleansUpOnGitFailure() async throws {
        let parent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: parent) }

        let bogusURL = parent.appendingPathComponent("nonexistent.git").path
        let cloner = GitCloner()
        let result = await withCheckedContinuation { (cont: CheckedContinuation<Result<String, GitCloner.CloneError>, Never>) in
            cloner.start(
                options: .init(url: bogusURL, parentDir: parent.path, branch: nil, shallow: false),
                onProgress: { _ in },
                onComplete: { cont.resume(returning: $0) }
            )
        }

        if case .failure(.gitFailed) = result { } else {
            Issue.record("expected .gitFailed, got \(result)")
        }
        let target = (parent.path as NSString).appendingPathComponent("nonexistent")
        #expect(!FileManager.default.fileExists(atPath: target))
    }

    @Test func cancelTerminatesAndCleansUp() async throws {
        let parent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: parent) }
        let src = try makeBareSourceRepo()
        defer { src.cleanup() }

        let cloner = GitCloner()
        async let resultFuture: Result<String, GitCloner.CloneError> = withCheckedContinuation { cont in
            cloner.start(
                options: .init(url: src.path, parentDir: parent.path, branch: nil, shallow: false),
                onProgress: { _ in },
                onComplete: { cont.resume(returning: $0) }
            )
        }

        // 让 git 进程有机会启动
        try await Task.sleep(nanoseconds: 50_000_000)
        cloner.cancel()

        let result = await resultFuture
        // 本地 clone 极快，可能在 cancel 前已成功；任一结果都接受
        // 但若 cancelled，则 target 必须已清理
        switch result {
        case .success:
            break
        case .failure(.cancelled):
            let target = (parent.path as NSString).appendingPathComponent("bare")
            #expect(!FileManager.default.fileExists(atPath: target))
        case .failure(let other):
            Issue.record("unexpected failure: \(other)")
        }
    }

    @Test func clonesSpecificBranch() async throws {
        let parent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: parent) }
        let src = try makeBareSourceRepo()
        defer { src.cleanup() }

        let cloner = GitCloner()
        let result = await withCheckedContinuation { (cont: CheckedContinuation<Result<String, GitCloner.CloneError>, Never>) in
            cloner.start(
                options: .init(url: src.path, parentDir: parent.path, branch: "main", shallow: false),
                onProgress: { _ in },
                onComplete: { cont.resume(returning: $0) }
            )
        }

        if case .success(let path) = result {
            // 验证是 main 分支
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = ["-C", path, "rev-parse", "--abbrev-ref", "HEAD"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = Pipe()
            try p.run()
            p.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(out == "main")
        } else {
            Issue.record("expected success, got \(result)")
        }
    }

    @Test func shallowCloneCreatesShallowFile() async throws {
        let parent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: parent) }
        let src = try makeBareSourceRepo()
        defer { src.cleanup() }

        // git 对本地路径默认走 hardlink 优化（不支持 shallow），必须用 file:// URL 触发真克隆
        let fileURL = "file://" + src.path
        let cloner = GitCloner()
        let result = await withCheckedContinuation { (cont: CheckedContinuation<Result<String, GitCloner.CloneError>, Never>) in
            cloner.start(
                options: .init(url: fileURL, parentDir: parent.path, branch: nil, shallow: true),
                onProgress: { _ in },
                onComplete: { cont.resume(returning: $0) }
            )
        }

        if case .success(let path) = result {
            let shallowFile = (path as NSString).appendingPathComponent(".git/shallow")
            #expect(FileManager.default.fileExists(atPath: shallowFile))
        } else {
            Issue.record("expected success, got \(result)")
        }
    }
}
