// macos/Sources/PolterttyCLI/Commands/PrepareSessionCommand.swift
import Foundation

enum PrepareSessionCommand {
    static func run(_ args: [String]) {
        guard let sessionId = extractArg("--session-id", from: args),
              let agent = extractArg("--agent", from: args),
              let agentSessionId = extractArg("--agent-session-id", from: args),
              let cwd = extractArg("--cwd", from: args),
              let workspaceId = extractArg("--workspace-id", from: args),
              let surfaceId = extractArg("--surface-id", from: args),
              let portStr = extractArg("--port", from: args),
              let port = UInt16(portStr),
              let pidStr = extractArg("--pid", from: args),
              let pid = Int32(pidStr) else {
            fputs("Error: missing required arguments\n", stderr)
            fputs("Required: --session-id, --agent, --agent-session-id, --cwd, --workspace-id, --surface-id, --port, --pid\n", stderr)
            exit(1)
        }

        // 构建请求 body
        var body: [String: Any] = [
            "sessionId": sessionId,
            "agent": agent,
            "agentSessionId": agentSessionId,
            "cwd": cwd,
            "workspaceId": workspaceId,
            "surfaceId": surfaceId,
            "port": port,
            "pid": pid,
        ]

        if let userSettings = extractArg("--user-settings", from: args) {
            body["userSettings"] = userSettings
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            fputs("Error: failed to serialize JSON\n", stderr)
            exit(1)
        }

        let url = URL(string: "http://localhost:\(port)/hooks/prepare-session")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (data, response) = syncRequest(request)

        guard let status = response?.statusCode, (200..<300).contains(status),
              let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionDir = json["sessionDir"] as? String else {
            fputs("Error: prepare-session request failed\n", stderr)
            exit(1)
        }

        print(sessionDir)
        exit(0)
    }
}
