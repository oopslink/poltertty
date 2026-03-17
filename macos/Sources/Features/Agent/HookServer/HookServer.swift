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

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self, let data, !data.isEmpty else { return }
            self.processRequest(data: data, connection: connection)
        }
    }

    private func processRequest(data: Data, connection: NWConnection) {
        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A])
        guard let range = data.range(of: separator) else {
            sendResponse(connection, status: 400, body: "Bad Request"); return
        }
        let headerStr = String(data: data[..<range.lowerBound], encoding: .utf8) ?? ""
        let firstLine = headerStr.components(separatedBy: "\r\n").first ?? ""

        if firstLine.hasPrefix("GET /health") {
            sendResponse(connection, status: 200, body: "ok"); return
        }
        guard firstLine.hasPrefix("POST /hook") else {
            sendResponse(connection, status: 404, body: "Not Found"); return
        }

        let bodyData = data[range.upperBound...]
        guard let payload = try? decoder.decode(HookPayload.self, from: bodyData) else {
            Self.logger.warning("HookServer: failed to decode hook payload")
            sendResponse(connection, status: 400, body: "Invalid JSON"); return
        }
        sendResponse(connection, status: 200, body: "ok")
        Task { @MainActor in self.sessionManager.processHookEvent(payload) }
    }

    private func sendResponse(_ connection: NWConnection, status: Int, body: String) {
        let bodyData = (body.data(using: .utf8)) ?? Data()
        let header = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\nContent-Length: \(bodyData.count)\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n"
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
