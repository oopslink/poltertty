// macos/Sources/Features/Workspace/GitCloner.swift
import Foundation

final class GitCloner {

    // MARK: - Repo name extraction

    /// 从 git URL 中提取仓库名（去掉 .git 后缀和尾部斜杠）。
    /// 支持 https://, git@host:path, ssh://, 以及尾部带 / 的形式。
    static func extractRepoName(from url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var s = trimmed
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix(".git") { s.removeLast(4) }
        while s.hasSuffix("/") { s.removeLast() }

        let lastSlash = s.lastIndex(of: "/")
        let lastColon = s.lastIndex(of: ":")
        let cutIndex: String.Index?
        switch (lastSlash, lastColon) {
        case let (l?, c?): cutIndex = l > c ? l : c
        case let (l?, nil): cutIndex = l
        case let (nil, c?): cutIndex = c
        case (nil, nil): cutIndex = nil
        }

        let name: String
        if let idx = cutIndex {
            name = String(s[s.index(after: idx)...])
        } else {
            name = s
        }

        return name.isEmpty ? nil : name
    }

    // MARK: - Types

    enum CloneError: LocalizedError {
        case invalidURL
        case parentNotWritable(path: String)
        case targetExists(path: String)
        case gitFailed(exitCode: Int32, stderr: String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid or empty Git URL"
            case .parentNotWritable(let p):
                return "Parent directory is not writable: \(p)"
            case .targetExists(let p):
                return "Target already exists: \(p)"
            case .gitFailed(_, let stderr):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "git clone failed" : trimmed
            case .cancelled:
                return "Clone cancelled"
            }
        }
    }

    struct Options {
        let url: String
        let parentDir: String
        let branch: String?
        let shallow: Bool
    }

    // MARK: - State

    private var process: Process?
    private var targetPath: String?
    private var cancelRequested: Bool = false
    private(set) var isRunning: Bool = false

    // MARK: - Start

    /// 启动 clone。回调统一在主线程触发。
    func start(
        options: Options,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, CloneError>) -> Void
    ) {
        // 预检 1：URL 有效
        let trimmedURL = options.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty,
              let repoName = Self.extractRepoName(from: trimmedURL) else {
            DispatchQueue.main.async { onComplete(.failure(.invalidURL)) }
            return
        }

        // 预检 2：父目录存在且可写
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: options.parentDir, isDirectory: &isDir),
              isDir.boolValue,
              fm.isWritableFile(atPath: options.parentDir) else {
            DispatchQueue.main.async { onComplete(.failure(.parentNotWritable(path: options.parentDir))) }
            return
        }

        // 预检 3：目标子目录不存在
        let target = (options.parentDir as NSString).appendingPathComponent(repoName)
        if fm.fileExists(atPath: target) {
            DispatchQueue.main.async { onComplete(.failure(.targetExists(path: target))) }
            return
        }

        // 启动子进程
        self.targetPath = target
        self.cancelRequested = false
        self.isRunning = true

        var args = ["clone", "--progress", trimmedURL, target]
        if let branch = options.branch, !branch.isEmpty {
            args.append(contentsOf: ["-b", branch])
        }
        if options.shallow {
            args.append(contentsOf: ["--depth", "1"])
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = args
        proc.environment = [
            "HOME": NSHomeDirectory(),
            "PATH": "/usr/bin:/bin:/usr/local/bin",
            "GIT_TERMINAL_PROMPT": "0",
        ]

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        let stderrBuffer = StderrBuffer()

        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stderrBuffer.append(data)
            if let line = stderrBuffer.lastLine() {
                DispatchQueue.main.async { onProgress(line) }
            }
        }

        proc.terminationHandler = { [weak self] p in
            errPipe.fileHandleForReading.readabilityHandler = nil
            // 排空 stdout 防止僵尸管道
            _ = outPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = stderrBuffer.snapshot()
            let exitCode = p.terminationStatus

            DispatchQueue.main.async {
                guard let self else { return }
                self.isRunning = false
                self.process = nil
                let cancelled = self.cancelRequested
                self.cancelRequested = false

                if exitCode == 0 && !cancelled {
                    onComplete(.success(target))
                } else {
                    self.cleanupTargetIfPresent()
                    if cancelled {
                        onComplete(.failure(.cancelled))
                    } else {
                        onComplete(.failure(.gitFailed(exitCode: exitCode, stderr: stderrText)))
                    }
                }
                self.targetPath = nil
            }
        }

        do {
            try proc.run()
            self.process = proc
        } catch {
            self.isRunning = false
            self.process = nil
            self.cleanupTargetIfPresent()
            self.targetPath = nil
            DispatchQueue.main.async {
                onComplete(.failure(.gitFailed(exitCode: -1, stderr: error.localizedDescription)))
            }
        }
    }

    // MARK: - Cancel

    /// 中止当前 clone：SIGTERM → 250ms 宽限 → SIGKILL。
    /// terminationHandler 负责清理目标目录并以 .cancelled 触发 onComplete。
    func cancel() {
        guard let proc = process, proc.isRunning else { return }
        cancelRequested = true
        proc.terminate()
        let pid = proc.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
            if proc.isRunning {
                kill(pid, SIGKILL)
            }
        }
    }

    // MARK: - Cleanup

    /// 只删 target 自身，不递归动 parentDir。
    private func cleanupTargetIfPresent() {
        guard let path = targetPath else { return }
        try? FileManager.default.removeItem(atPath: path)
    }
}

private final class StderrBuffer {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
    }

    func lastLine() -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
        return lines.last.map(String.init)
    }

    func snapshot() -> String {
        lock.lock(); defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
