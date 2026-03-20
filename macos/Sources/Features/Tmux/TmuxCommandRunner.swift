// macos/Sources/Features/Tmux/TmuxCommandRunner.swift
import Foundation

/// 封装 Process 执行 tmux 子命令。async/await，不阻塞主线程。
/// PATH 扩展覆盖 Homebrew 常见安装位置。
enum TmuxCommandRunner {

    private static let tmuxPath = "/usr/bin/tmux"  // 系统自带路径；Homebrew 路径通过 PATH 查找

    /// 执行 tmux 命令，返回 stdout 字符串，超时 3s 自动取消
    static func run(args: [String]) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await execute(args: args) }
            group.addTask {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                throw TmuxError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// 执行 tmux 命令，忽略输出（用于写操作：new-window、kill-session 等）
    static func runSilent(args: [String]) async throws {
        _ = try await run(args: args)
    }

    private static func execute(args: [String]) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()

            // 扩展 PATH 覆盖 Homebrew 安装位置
            var env = ProcessInfo.processInfo.environment
            let extraPaths = "/usr/local/bin:/opt/homebrew/bin:/opt/local/bin"
            if let existing = env["PATH"] {
                env["PATH"] = "\(extraPaths):\(existing)"
            } else {
                env["PATH"] = extraPaths
            }

            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["tmux"] + args
            process.standardOutput = stdout
            process.standardError = stderr
            process.environment = env

            process.terminationHandler = { p in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let outStr = String(data: outData, encoding: .utf8) ?? ""
                let errStr = String(data: errData, encoding: .utf8) ?? ""

                if p.terminationStatus == 0 {
                    continuation.resume(returning: outStr)
                } else {
                    let lower = errStr.lowercased()
                    if lower.contains("no server running") || lower.contains("no sessions") {
                        continuation.resume(throwing: TmuxError.serverNotRunning(stderr: errStr))
                    } else {
                        // Non-zero exit with unrecognized stderr — treat as serverNotRunning
                        // with the actual stderr for diagnostics. This covers cases like
                        // kill-pane on an already-gone target.
                        continuation.resume(throwing: TmuxError.serverNotRunning(stderr: errStr))
                    }
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: TmuxError.notInstalled)
            }
        }
    }
}
