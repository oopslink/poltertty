// macos/Sources/Features/Workspace/Metadata/PRStatusFetcher.swift
import Foundation

enum PRStatusFetcher {
    private struct Response: Decodable {
        let number: Int
        let state: String
        let isDraft: Bool
    }

    /// 解析 `gh pr view --json number,state,isDraft` 的输出
    static func parseJSON(_ data: Data) -> PRStatus? {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        if response.isDraft { return .draft(number: response.number) }
        switch response.state.uppercased() {
        case "OPEN":   return .open(number: response.number)
        case "MERGED": return .merged(number: response.number)
        default:       return nil
        }
    }

    /// 实际调用 gh CLI，在后台线程执行
    static func fetch(rootDir: String) async -> PRStatus? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["gh", "pr", "view", "--json", "number,state,isDraft"]
            process.currentDirectoryURL = URL(fileURLWithPath: (rootDir as NSString).expandingTildeInPath)
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: parseJSON(data))
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
