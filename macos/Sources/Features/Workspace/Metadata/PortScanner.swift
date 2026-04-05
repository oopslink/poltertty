// macos/Sources/Features/Workspace/Metadata/PortScanner.swift
import Foundation

enum PortScanner {
    struct ListenEntry {
        let port: Int
        let pid: Int
    }

    /// 解析 `lsof -iTCP -sTCP:LISTEN -Pn -F pn` 输出
    static func parseListenOutput(_ output: String) -> [ListenEntry] {
        var results: [ListenEntry] = []
        var currentPid: Int? = nil
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("p"), let pid = Int(line.dropFirst()) {
                currentPid = pid
            } else if line.hasPrefix("n"), let pid = currentPid {
                let name = String(line.dropFirst())  // e.g. "*:3000" or "127.0.0.1:8080"
                if let colonIdx = name.lastIndex(of: ":"),
                   let port = Int(name[name.index(after: colonIdx)...]) {
                    results.append(ListenEntry(port: port, pid: pid))
                }
            }
        }
        return results
    }

    /// 解析 `lsof -p <pids> -d cwd -F pn` 输出，返回 pid → cwd
    static func parseCwdOutput(_ output: String) -> [Int: String] {
        var result: [Int: String] = [:]
        var currentPid: Int? = nil
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("p"), let pid = Int(line.dropFirst()) {
                currentPid = pid
            } else if line.hasPrefix("n"), let pid = currentPid {
                result[pid] = String(line.dropFirst())
            }
        }
        return result
    }

    /// 将 ListenEntry 列表按 rootDir 前缀归属到各 workspace
    static func assignPorts(
        _ entries: [ListenEntry],
        cwds: [Int: String],
        workspaces: [(id: UUID, rootDir: String)]
    ) -> [UUID: [Int]] {
        var portsByWorkspace: [UUID: [Int]] = [:]
        let expandedWorkspaces = workspaces.map { (id: $0.id, rootDir: ($0.rootDir as NSString).expandingTildeInPath) }
        for entry in entries {
            guard let cwd = cwds[entry.pid] else { continue }
            for ws in expandedWorkspaces {
                if cwd == ws.rootDir || cwd.hasPrefix(ws.rootDir + "/") {
                    portsByWorkspace[ws.id, default: []].append(entry.port)
                    break
                }
            }
        }
        return portsByWorkspace
    }

    /// 实际扫描：运行 lsof 并归属端口到各 workspace（在后台线程执行）
    static func scan(workspaces: [(id: UUID, rootDir: String)]) async -> [UUID: [Int]] {
        guard !workspaces.isEmpty else { return [:] }

        // 1. 获取所有监听端口 + PID
        let listenOutput = await runCommand("/usr/sbin/lsof", args: ["-iTCP", "-sTCP:LISTEN", "-Pn", "-F", "pn"])
        let entries = parseListenOutput(listenOutput)
        guard !entries.isEmpty else { return [:] }

        // 2. 批量查询这些 PID 的工作目录
        let pids = Array(Set(entries.map { $0.pid })).map { String($0) }.joined(separator: ",")
        let cwdOutput = await runCommand("/usr/sbin/lsof", args: ["-p", pids, "-d", "cwd", "-F", "pn"])
        let cwds = parseCwdOutput(cwdOutput)

        // 3. 归属
        return assignPorts(entries, cwds: cwds, workspaces: workspaces)
    }

    private static func runCommand(_ path: String, args: [String]) async -> String {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            } catch {
                continuation.resume(returning: "")
            }
        }
    }
}
