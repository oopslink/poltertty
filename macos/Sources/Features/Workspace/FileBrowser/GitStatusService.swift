// macos/Sources/Features/Workspace/FileBrowser/GitStatusService.swift
import Foundation

struct GitStatusService {
    /// 异步跑 `git -C rootDir status --porcelain`，返回 [absolutePath: GitStatus]
    /// rootDir 不是 git repo 时（exit code ≠ 0）静默返回空字典
    static func fetchStatus(rootDir: String) async -> [String: GitStatus] {
        guard !rootDir.isEmpty else { return [:] }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: fetchStatusSync(rootDir: rootDir))
            }
        }
    }

    private static func fetchStatusSync(rootDir: String) -> [String: GitStatus] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", rootDir, "status", "--porcelain"]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return [:]
        }

        guard process.terminationStatus == 0 else { return [:] }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [:] }

        var result: [String: GitStatus] = [:]
        for line in output.components(separatedBy: "\n") {
            guard line.count >= 3 else { continue }
            let chars = Array(line)
            let x = chars[0]
            let y = chars[1]
            let path = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { continue }

            // Handle rename: "old -> new", take the new path
            let effectivePath: String
            if path.contains(" -> ") {
                effectivePath = String(path.split(separator: " ").last ?? Substring(path))
            } else {
                effectivePath = path
            }

            let fullPath = (rootDir as NSString).appendingPathComponent(effectivePath)

            // Untracked: either column is '?'
            if x == "?" || y == "?" {
                result[fullPath] = .untracked
                continue
            }

            // Working-tree column (Y) takes priority over index (X)
            let effectiveChar: Character
            if y != " " && y != "-" {
                effectiveChar = y
            } else {
                effectiveChar = x
            }

            switch effectiveChar {
            case "M", "m": result[fullPath] = .modified
            case "A":       result[fullPath] = .added
            case "D":       result[fullPath] = .deleted
            default:        break
            }
        }
        return result
    }

    // MARK: - Diff

    /// 获取文件的 git diff 内容
    /// - Parameters:
    ///   - staged: true 时使用 `git diff --cached`（已暂存），false 时使用 `git diff HEAD`
    static func fetchDiff(rootDir: String, fileURL: URL, staged: Bool) async -> String {
        guard !rootDir.isEmpty else { return "" }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                if staged {
                    process.arguments = ["-C", rootDir, "diff", "--cached", "--", fileURL.path]
                } else {
                    process.arguments = ["-C", rootDir, "diff", "HEAD", "--", fileURL.path]
                }
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    continuation.resume(returning: "")
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output)
            }
        }
    }

    // MARK: - Stage / Unstage

    /// 暂存文件（git add）
    static func stage(rootDir: String, urls: [URL]) async throws {
        try await runGitCommand(rootDir: rootDir, args: ["add", "--"] + urls.map(\.path))
    }

    /// 取消暂存（git restore --staged）
    static func unstage(rootDir: String, urls: [URL]) async throws {
        try await runGitCommand(rootDir: rootDir, args: ["restore", "--staged", "--"] + urls.map(\.path))
    }

    private static func runGitCommand(rootDir: String, args: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = ["-C", rootDir] + args
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        continuation.resume(
                            throwing: NSError(
                                domain: "GitStatusService",
                                code: Int(process.terminationStatus)
                            )
                        )
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
