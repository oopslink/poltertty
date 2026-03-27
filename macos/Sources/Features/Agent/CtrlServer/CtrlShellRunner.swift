// macos/Sources/Features/Agent/CtrlServer/CtrlShellRunner.swift
import Foundation

/// Ctrl API 工具层的轻量 shell 执行助手。
/// 与 GitWorktreeMonitor.runGit() 保持一致的模式，但作为独立 enum 供 CtrlToolHandler 调用。
/// 所有调用均为同步阻塞——应在后台 Task 或非 MainActor 上下文中调用。
enum CtrlShellRunner {
    struct Result {
        let exitCode: Int32
        let stdout: String
        let stderr: String

        var succeeded: Bool { exitCode == 0 }
        var trimmedStdout: String { stdout.trimmingCharacters(in: .whitespacesAndNewlines) }
        var trimmedStderr: String { stderr.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// 运行任意可执行文件。
    static func run(_ executablePath: String, args: [String]) -> Result {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.arguments = args
        // 最小化环境，保留 HOME（git 需要读取 ~/.gitconfig）
        proc.environment = [
            "HOME": NSHomeDirectory(),
            "PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
        ]
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return Result(exitCode: proc.terminationStatus, stdout: stdout, stderr: stderr)
        } catch {
            return Result(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }
    }

    /// 运行 git 命令。
    static func git(_ args: [String]) -> Result {
        run("/usr/bin/git", args: args)
    }
}
