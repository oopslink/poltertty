// macos/Sources/Features/Agent/HookServer/HookServer.swift
import Foundation
import Network
import OSLog

/// 内嵌 HTTP server，接收 Claude Code hook 事件
/// 每个 Poltertty 实例绑定随机端口（port 0），通过 POLTERTTY_HTTP_PORT 环境变量传递给终端
final class HookServer {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "HookServer"
    )

    private var listener: NWListener?
    private(set) var port: UInt16 = 0

    private let sessionManager: AgentSessionManager
    private let decoder = JSONDecoder()

    init(sessionManager: AgentSessionManager) {
        self.sessionManager = sessionManager
    }

    // MARK: - 生命周期

    func start() {
        let params = NWParameters.tcp
        guard let listener = try? NWListener(using: params, on: .any) else {
            Self.logger.error("HookServer: failed to create listener")
            return
        }

        let semaphore = DispatchSemaphore(value: 0)
        var assignedPort: UInt16 = 0

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                assignedPort = listener.port?.rawValue ?? 0
                semaphore.signal()
            case .failed:
                semaphore.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in self?.handleConnection(conn) }
        listener.start(queue: .global(qos: .utility))

        let result = semaphore.wait(timeout: .now() + 5.0)
        if result == .timedOut || assignedPort == 0 {
            Self.logger.error("HookServer: failed to bind")
            listener.cancel()
            return
        }

        self.listener = listener
        self.port = assignedPort
        Self.logger.info("HookServer listening on port \(assignedPort)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
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

    // MARK: - prepare-session

    private struct PrepareRequest: Decodable {
        let sessionId: String
        let agent: String
        let agentSessionId: String
        let cwd: String
        let workspaceId: String
        let surfaceId: String
        let port: UInt16
        let pid: Int32
        let userSettings: String?
    }

    private func handlePrepareSession(bodyData: Data.SubSequence, connection: NWConnection) {
        let rawBodyData = Data(bodyData)
        guard let req = try? decoder.decode(PrepareRequest.self, from: rawBodyData) else {
            Self.logger.warning("HookServer: failed to decode prepare-session request")
            sendResponse(connection, status: 400, body: #"{"error":"invalid json"}"#)
            return
        }

        let serverPort = self.port
        Task { @MainActor in
            let session = HookSessionStore.shared.create(
                sessionId: req.sessionId,
                agentSessionId: req.agentSessionId,
                agentType: req.agent,
                workspaceId: req.workspaceId,
                surfaceId: req.surfaceId,
                pid: req.pid,
                cwd: req.cwd,
                port: serverPort
            )

            // wrapper 启动的会话注册为本地 AgentSession（仅当该 surface 尚未有活跃会话时）
            Self.logger.warning("prepare-session: agent=\(req.agent) agentSessionId=\(req.agentSessionId) surfaceId=\(req.surfaceId) workspaceId=\(req.workspaceId)")
            if let surfaceUUID = UUID(uuidString: req.surfaceId),
               let workspaceUUID = UUID(uuidString: req.workspaceId),
               self.sessionManager.session(for: surfaceUUID) == nil {
                let definition = AgentRegistry.shared.definitions
                    .first { $0.command == req.agent } ?? .claudeCode
                let agentSession = AgentSession(
                    id: UUID(),
                    surfaceId: surfaceUUID,
                    definition: definition,
                    workspaceId: workspaceUUID,
                    cwd: req.cwd
                )
                self.sessionManager.register(agentSession)
                Self.logger.warning("prepare-session: registered AgentSession surfaceId=\(surfaceUUID) agentSessionId=\(req.agentSessionId)")
                // 预绑定 claude session ID，使后续 hook 事件能直接命中
                if req.agentSessionId != "unknown" {
                    self.sessionManager.bindClaudeSession(
                        surfaceId: surfaceUUID,
                        claudeSessionId: req.agentSessionId
                    )
                }
            } else {
                Self.logger.warning("prepare-session: skipped registration (surface already has session or invalid UUIDs)")
            }

            let sessionDir = "\(NSHomeDirectory())/.poltertty/sessions/\(req.sessionId)"
            let cliPath = "\(NSHomeDirectory())/.poltertty/bin/poltertty-cli"

            SettingsMerger.mergeAndWrite(
                sessionId: req.sessionId,
                sessionDir: sessionDir,
                cwd: req.cwd,
                cliPath: cliPath,
                userSettingsPath: req.userSettings
            )

            let responseBody = #"{"sessionDir":"\#(sessionDir)","token":"\#(session.token)"}"#
            self.sendResponse(connection, status: 200, body: responseBody)
        }
    }

    private func processRequest(firstLine: String, bodyData: Data.SubSequence, connection: NWConnection) {
        // 匹配 "GET /health" 或 "GET http://localhost:.../health"
        if firstLine.hasPrefix("GET") && firstLine.contains("/health") {
            sendResponse(connection, status: 200, body: "{}"); return
        }
        // 匹配 "POST /hooks/prepare-session"
        if firstLine.hasPrefix("POST") && firstLine.contains("/hooks/prepare-session") {
            handlePrepareSession(bodyData: bodyData, connection: connection); return
        }
        // 匹配 "POST /hook" 或 "POST http://localhost:.../hook"
        guard firstLine.hasPrefix("POST") && firstLine.contains("/hook") else {
            Self.logger.warning("HookServer: rejected \(firstLine)")
            sendResponse(connection, status: 404, body: #"{"error":"not found"}"#); return
        }

        let rawBodyData = Data(bodyData)
        guard var payload = try? decoder.decode(HookPayload.self, from: rawBodyData) else {
            let bodyPreview = String(data: rawBodyData.prefix(500), encoding: .utf8) ?? "(binary)"
            Self.logger.warning("HookServer: failed to decode hook payload (\(rawBodyData.count) bytes): \(bodyPreview)")
            sendResponse(connection, status: 400, body: #"{"error":"invalid json"}"#); return
        }
        // 注入 tool_input 原始 JSON（用于 Trace 显示参数）
        if let jsonObj = try? JSONSerialization.jsonObject(with: rawBodyData) as? [String: Any],
           let toolInput = jsonObj["tool_input"],
           let inputData = try? JSONSerialization.data(withJSONObject: toolInput, options: [.sortedKeys]),
           let inputStr = String(data: inputData, encoding: .utf8) {
            payload.toolInputRaw = inputStr
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

}
