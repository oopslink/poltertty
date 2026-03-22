// macos/Sources/PolterttyCLI/Commands/PingCommand.swift
import Foundation

enum PingCommand {
    static func run(_ args: [String]) {
        guard let portStr = extractArg("--port", from: args),
              let port = UInt16(portStr) else {
            fputs("Error: --port is required\n", stderr)
            exit(1)
        }

        let timeoutMs = Double(extractArg("--timeout", from: args) ?? "750") ?? 750
        let timeoutSec = timeoutMs / 1000.0

        let url = URL(string: "http://localhost:\(port)/health")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (_, response) = syncRequest(request, timeout: timeoutSec)

        if let status = response?.statusCode, (200..<300).contains(status) {
            exit(0)
        } else {
            exit(1)
        }
    }
}
