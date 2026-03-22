// macos/Sources/PolterttyCLI/Commands/HookCommand.swift
import Foundation

enum HookCommand {
    /// meta.json 中需要读取的字段（与 WrapperSession 一致）
    private struct SessionMeta: Decodable {
        let token: String
        let port: UInt16
    }

    static func run(_ args: [String]) {
        guard let event = args.first else {
            fputs("Error: event name is required as the first argument\n", stderr)
            exit(0) // 不阻塞 agent
        }

        guard let sessionId = extractArg("--session", from: args) else {
            fputs("Error: --session is required\n", stderr)
            exit(0)
        }

        // 读取 meta.json
        let metaPath = "\(NSHomeDirectory())/.poltertty/sessions/\(sessionId)/meta.json"
        guard let metaData = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
              let meta = try? JSONDecoder().decode(SessionMeta.self, from: metaData) else {
            // meta.json 不存在或解析失败，静默退出
            exit(0)
        }

        // 从 stdin 读取 payload
        let stdinData = FileHandle.standardInput.readDataToEndOfFile()

        // 构建请求 body
        var body: [String: Any] = [
            "event": event,
            "sessionId": sessionId,
        ]

        if !stdinData.isEmpty,
           let payload = try? JSONSerialization.jsonObject(with: stdinData) {
            body["payload"] = payload
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            exit(0)
        }

        let url = URL(string: "http://localhost:\(meta.port)/hook")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(meta.token)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData

        // 发送请求，忽略结果
        _ = syncRequest(request)
        exit(0)
    }
}
