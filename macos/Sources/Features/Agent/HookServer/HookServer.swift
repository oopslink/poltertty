// macos/Sources/Features/Agent/HookServer/HookServer.swift
import Foundation
import Network
import OSLog

/// 内嵌 HTTP server，接收 Claude Code hook 事件
/// 绑定 localhost 固定端口，多个 Poltertty 实例共享同一 server
final class HookServer {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "HookServer"
    )

    static let defaultPort: UInt16 = 19198
    static let maxPortRetries: Int = 10

    private static let lockFilePath: String = {
        let base = ("~/.config/poltertty" as NSString).expandingTildeInPath
        return (base as NSString).appendingPathComponent("hook-server.json")
    }()

    private struct LockFile: Codable {
        let port: UInt16
        let pid: Int32
    }

    private var listener: NWListener?
    private(set) var port: UInt16 = 0

    private let sessionManager: AgentSessionManager
    private let decoder = JSONDecoder()

    init(sessionManager: AgentSessionManager) {
        self.sessionManager = sessionManager
    }

    // MARK: - 生命周期

    func start() {
        if tryReuseExisting() { return }
        for offset in 0..<Self.maxPortRetries {
            let candidate = Self.defaultPort + UInt16(offset)
            if tryListen(on: candidate) {
                writeLockFile(port: candidate)
                Self.logger.info("HookServer listening on port \(candidate)")
                return
            }
        }
        Self.logger.error("HookServer: failed to bind any port")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        removeLockFile()
    }

    // MARK: - 多实例协调

    private func tryReuseExisting() -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: Self.lockFilePath)),
              let lock = try? JSONDecoder().decode(LockFile.self, from: data) else { return false }
        guard kill(lock.pid, 0) == 0 else {
            try? FileManager.default.removeItem(atPath: Self.lockFilePath)
            return false
        }
        if lock.pid == getpid() { return false }
        self.port = lock.port
        Self.logger.info("HookServer: reusing port \(lock.port) from PID \(lock.pid)")
        return true
    }

    private func tryListen(on port: UInt16) -> Bool {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let portObj = NWEndpoint.Port(rawValue: port),
              let listener = try? NWListener(using: params, on: portObj) else { return false }

        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:   success = true; semaphore.signal()
            case .failed:  semaphore.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in self?.handleConnection(conn) }
        listener.start(queue: .global(qos: .utility))
        semaphore.wait()

        if success { self.listener = listener; self.port = port }
        return success
    }

    // MARK: - HTTP 处理

    private static let headerSeparator = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        accumulateRequest(connection: connection, buffer: Data())
    }

    /// 递归读取数据，直到收齐 HTTP headers + body（按 Content-Length）
    private func accumulateRequest(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 131072) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }

            // 超过 1MB 保护
            guard buf.count < 1_048_576 else {
                self.sendResponse(connection, status: 413, body: #"{"error":"too large"}"#); return
            }

            guard let headerEnd = buf.range(of: Self.headerSeparator) else {
                if isComplete || error != nil {
                    self.sendResponse(connection, status: 400, body: #"{"error":"incomplete headers"}"#)
                } else {
                    self.accumulateRequest(connection: connection, buffer: buf)
                }
                return
            }

            // 解析 Content-Length，判断 body 是否完整
            let headerStr = String(data: buf[..<headerEnd.lowerBound], encoding: .utf8) ?? ""
            let contentLength = headerStr.components(separatedBy: "\r\n")
                .first { $0.lowercased().hasPrefix("content-length:") }
                .flatMap { Int($0.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "") } ?? 0

            let bodyStart = headerEnd.upperBound
            let receivedBody = buf.count - bodyStart
            if receivedBody < contentLength && !isComplete && error == nil {
                self.accumulateRequest(connection: connection, buffer: buf)
                return
            }

            // 完整请求已收齐，处理
            let firstLine = headerStr.components(separatedBy: "\r\n").first ?? ""
            let bodyData = buf[bodyStart...]
            self.processRequest(firstLine: firstLine, bodyData: bodyData, connection: connection)
        }
    }

    private func processRequest(firstLine: String, bodyData: Data.SubSequence, connection: NWConnection) {
        // 匹配 "GET /health" 或 "GET http://localhost:.../health"
        if firstLine.hasPrefix("GET") && firstLine.contains("/health") {
            sendResponse(connection, status: 200, body: "{}"); return
        }
        // 匹配 "POST /hook" 或 "POST http://localhost:.../hook"
        guard firstLine.hasPrefix("POST") && firstLine.contains("/hook") else {
            Self.logger.warning("HookServer: rejected \(firstLine)")
            sendResponse(connection, status: 404, body: #"{"error":"not found"}"#); return
        }

        let rawBodyData = Data(bodyData)
        guard let payload = try? decoder.decode(HookPayload.self, from: rawBodyData) else {
            let bodyPreview = String(data: rawBodyData.prefix(500), encoding: .utf8) ?? "(binary)"
            Self.logger.warning("HookServer: failed to decode hook payload (\(rawBodyData.count) bytes): \(bodyPreview)")
            sendResponse(connection, status: 400, body: #"{"error":"invalid json"}"#); return
        }
        Self.logger.warning("HookServer: event=\(payload.hookEventName.rawValue) sid=\(payload.sessionId ?? "nil") tool=\(payload.toolName ?? "-") toolUseId=\(payload.toolUseId ?? "-")")
        sendResponse(connection, status: 200, body: "{}")
        Task { @MainActor in self.sessionManager.processHookEvent(payload) }
    }

    private func sendResponse(_ connection: NWConnection, status: Int, body: String) {
        let bodyData = body.data(using: .utf8) ?? Data()
        let statusText = status == 200 ? "OK" : "Error"
        let header = "HTTP/1.1 \(status) \(statusText)\r\nContent-Length: \(bodyData.count)\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n"
        var resp = header.data(using: .utf8)!
        resp.append(bodyData)
        connection.send(content: resp, completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: - 锁文件

    private func writeLockFile(port: UInt16) {
        let lock = LockFile(port: port, pid: getpid())
        let dir = ("~/.config/poltertty" as NSString).expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(lock).write(to: URL(fileURLWithPath: Self.lockFilePath))
    }

    private func removeLockFile() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: Self.lockFilePath)),
              let lock = try? JSONDecoder().decode(LockFile.self, from: data),
              lock.pid == getpid() else { return }
        try? FileManager.default.removeItem(atPath: Self.lockFilePath)
    }
}
