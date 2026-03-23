// macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift
import Foundation
import Network
import OSLog

/// 统一 HTTP server，处理 hook 事件接收和 MCP 控制接口
/// 每个实例绑定随机端口，通过 POLTERTTY_CTRL_PORT 环境变量和 SettingsMerger 注入给终端/Claude Code
final class CtrlServer {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "CtrlServer"
    )

    private var listener: NWListener?
    private(set) var port: UInt16 = 0

    /// 活跃 SSE 连接及其心跳 timer。所有访问均在 queue 上。
    private var sseConnections: [ObjectIdentifier: (conn: NWConnection, timer: DispatchSourceTimer)] = [:]
    private let queue = DispatchQueue(label: "com.poltertty.CtrlServer", qos: .utility)
    private let sessionManager: AgentSessionManager
    private let decoder = JSONDecoder()

    init(sessionManager: AgentSessionManager) {
        self.sessionManager = sessionManager
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

    // MARK: - 生命周期

    func start() {
        guard let listener = try? NWListener(using: .tcp, on: .any) else {
            Self.logger.error("CtrlServer: failed to create listener")
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
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in self?.handleConnection(conn) }
        listener.start(queue: queue)

        let result = semaphore.wait(timeout: .now() + 5.0)
        guard result != .timedOut, assignedPort > 0 else {
            Self.logger.error("CtrlServer: failed to bind")
            listener.cancel()
            return
        }

        self.listener = listener
        self.port = assignedPort
        Self.logger.info("CtrlServer listening on port \(assignedPort)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        queue.async { [weak self] in
            guard let self else { return }
            self.sseConnections.values.forEach { $0.timer.cancel(); $0.conn.cancel() }
            self.sseConnections.removeAll()
        }
    }

    // MARK: - 请求积累（与 HookServer 相同模式）

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        accumulateRequest(connection: connection, buffer: Data())
    }

    private static let headerSeparator = Data([0x0D, 0x0A, 0x0D, 0x0A])

    private func accumulateRequest(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 131072) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }

            guard buf.count < 1_048_576 else {
                self.sendJSON(connection, status: 413, body: #"{"error":"too large"}"#)
                return
            }

            guard let headerEnd = buf.range(of: Self.headerSeparator) else {
                if isComplete || error != nil {
                    self.sendJSON(connection, status: 400, body: #"{"error":"incomplete"}"#)
                } else {
                    self.accumulateRequest(connection: connection, buffer: buf)
                }
                return
            }

            let headerStr = String(data: buf[..<headerEnd.lowerBound], encoding: .utf8) ?? ""
            let contentLength = headerStr.components(separatedBy: "\r\n")
                .first { $0.lowercased().hasPrefix("content-length:") }
                .flatMap { Int($0.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "") } ?? 0

            let bodyStart = headerEnd.upperBound
            if buf.count - bodyStart < contentLength && !isComplete && error == nil {
                self.accumulateRequest(connection: connection, buffer: buf)
                return
            }

            let firstLine = headerStr.components(separatedBy: "\r\n").first ?? ""
            let bodyData = Data(buf[bodyStart...])
            self.processRequest(firstLine: firstLine, bodyData: bodyData, connection: connection)
        }
    }

    // MARK: - 路由

    private func processRequest(firstLine: String, bodyData: Data, connection: NWConnection) {
        Self.logger.info("CtrlServer: \(firstLine)")

        // --- health ---
        if firstLine.hasPrefix("GET") && firstLine.contains("/health") {
            sendJSON(connection, status: 200, body: "{}"); return
        }
        // --- hook routes（prepare-session 必须在 /hook 之前匹配） ---
        if firstLine.hasPrefix("POST") && firstLine.contains("/hooks/prepare-session") {
            handlePrepareSession(bodyData: bodyData, connection: connection); return
        }
        if firstLine.hasPrefix("POST") && firstLine.contains("/hook") {
            handleHook(bodyData: bodyData, connection: connection); return
        }
        // --- MCP routes ---
        if firstLine.hasPrefix("GET") && firstLine.contains("/mcp") {
            handleSSE(connection: connection); return
        }
        if firstLine.hasPrefix("DELETE") && firstLine.contains("/mcp") {
            sendJSON(connection, status: 200, body: "{}"); return
        }
        if firstLine.hasPrefix("POST") && firstLine.contains("/mcp") {
            handleMCP(bodyData: bodyData, connection: connection); return
        }
        sendJSON(connection, status: 404, body: #"{"error":"not found"}"#)
    }

    // MARK: - Hook handlers

    private func handlePrepareSession(bodyData: Data, connection: NWConnection) {
        guard let req = try? decoder.decode(PrepareRequest.self, from: bodyData) else {
            Self.logger.warning("CtrlServer: failed to decode prepare-session request")
            sendJSON(connection, status: 400, body: #"{"error":"invalid json"}"#)
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

            Self.logger.info("prepare-session: agent=\(req.agent) agentSessionId=\(req.agentSessionId) surfaceId=\(req.surfaceId) workspaceId=\(req.workspaceId)")
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
                Self.logger.info("prepare-session: registered AgentSession surfaceId=\(surfaceUUID) agentSessionId=\(req.agentSessionId)")
                if req.agentSessionId != "unknown" {
                    self.sessionManager.bindClaudeSession(
                        surfaceId: surfaceUUID,
                        claudeSessionId: req.agentSessionId
                    )
                }
            } else {
                Self.logger.info("prepare-session: skipped registration (surface already has session or invalid UUIDs)")
            }

            let sessionDir = "\(NSHomeDirectory())/.poltertty/sessions/\(req.sessionId)"
            let cliPath = "\(NSHomeDirectory())/.poltertty/bin/poltertty-cli"

            SettingsMerger.mergeAndWrite(
                sessionId: req.sessionId,
                sessionDir: sessionDir,
                cwd: req.cwd,
                cliPath: cliPath,
                userSettingsPath: req.userSettings,
                ctrlPort: serverPort
            )

            let responseBody = #"{"sessionDir":"\#(sessionDir)","token":"\#(session.token)"}"#
            self.sendJSON(connection, status: 200, body: responseBody)
        }
    }

    private func handleHook(bodyData: Data, connection: NWConnection) {
        guard var payload = try? decoder.decode(HookPayload.self, from: bodyData) else {
            let bodyPreview = String(data: bodyData.prefix(500), encoding: .utf8) ?? "(binary)"
            Self.logger.warning("CtrlServer: failed to decode hook payload (\(bodyData.count) bytes): \(bodyPreview)")
            sendJSON(connection, status: 400, body: #"{"error":"invalid json"}"#)
            return
        }
        // 注入 tool_input 原始 JSON（用于 Trace 显示参数）
        if let jsonObj = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
           let toolInput = jsonObj["tool_input"],
           let inputData = try? JSONSerialization.data(withJSONObject: toolInput, options: [.sortedKeys]),
           let inputStr = String(data: inputData, encoding: .utf8) {
            payload.toolInputRaw = inputStr
        }
        Self.logger.info("CtrlServer: event=\(payload.hookEventName.rawValue) sid=\(payload.sessionId ?? "nil") tool=\(payload.toolName ?? "-") toolUseId=\(payload.toolUseId ?? "-")")
        sendJSON(connection, status: 200, body: "{}")
        Task { @MainActor in self.sessionManager.processHookEvent(payload) }
    }

    // MARK: - SSE 长连接（GET /mcp）

    private func handleSSE(connection: NWConnection) {
        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n"
        connection.send(content: header.data(using: .utf8)!, completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else { connection.cancel(); return }

            // 断线自动清理
            let key = ObjectIdentifier(connection)
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed, .cancelled:
                    self?.queue.async { [weak self] in
                        self?.sseConnections[key]?.timer.cancel()
                        self?.sseConnections.removeValue(forKey: key)
                    }
                default: break
                }
            }

            // 每 30 秒发送 SSE 注释行，防止代理超时断开
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 30, repeating: 30)
            timer.setEventHandler { [weak connection] in
                connection?.send(content: ": ping\n\n".data(using: .utf8)!, completion: .idempotent)
            }
            timer.resume()

            self.queue.async { self.sseConnections[key] = (conn: connection, timer: timer) }
        })
    }

    // MARK: - JSON-RPC（POST /mcp）

    private func handleMCP(bodyData: Data, connection: NWConnection) {
        guard
            let obj = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
            let method = obj["method"] as? String
        else {
            sendRPCError(connection, id: nil, code: -32700, message: "Parse error")
            return
        }
        let id = obj["id"]
        let params = obj["params"] as? [String: Any]

        // notifications 为单向消息，按 MCP Streamable HTTP 规范返回 202 Accepted（无 body）
        if method.hasPrefix("notifications/") {
            sendEmpty(connection, status: 202)
            return
        }

        switch method {
        case "initialize":   handleInitialize(connection: connection, id: id)
        case "tools/list":   handleToolsList(connection: connection, id: id)
        case "tools/call":   handleToolsCall(connection: connection, id: id, params: params)
        default:             sendRPCError(connection, id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func handleInitialize(connection: NWConnection, id: Any?) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let result: [String: Any] = [
            "protocolVersion": "2025-03-26",
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": ["name": "poltertty", "version": version]
        ]
        sendRPCResult(connection, id: id, result: result)
    }

    private func handleToolsList(connection: NWConnection, id: Any?) {
        let tools: [[String: Any]] = [
            [
                "name": "ping",
                "description": "Ping the Poltertty instance to verify connectivity",
                "inputSchema": ["type": "object", "properties": [String: Any]()]
            ],
            [
                "name": "new_tab",
                "description": "Open a new tab in the specified or current workspace",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "workspaceId": [
                            "type": "string",
                            "description": "UUID of the target workspace (optional)"
                        ]
                    ]
                ]
            ]
        ]
        sendRPCResult(connection, id: id, result: ["tools": tools])
    }

    private func handleToolsCall(connection: NWConnection, id: Any?, params: [String: Any]?) {
        guard let name = params?["name"] as? String else {
            sendRPCError(connection, id: id, code: -32602, message: "Invalid params: missing name")
            return
        }
        let arguments = params?["arguments"] as? [String: Any] ?? [:]

        // CtrlToolHandler 持有 port 值拷贝，不访问 @MainActor 属性
        let handler = CtrlToolHandler(port: self.port)
        let (resultText, rpcError) = handler.prepareResult(tool: name, arguments: arguments)

        if let err = rpcError {
            sendRPCError(connection, id: id, code: err.code, message: err.message)
        } else {
            let content: [[String: Any]] = [["type": "text", "text": resultText ?? ""]]
            sendRPCResult(connection, id: id, result: ["content": content])
        }

        // 先 respond 再执行 UI 副作用（与 HookServer 一致）
        Task { @MainActor in
            handler.execute(tool: name, arguments: arguments)
        }
    }

    // MARK: - Response helpers

    private func sendRPCResult(_ connection: NWConnection, id: Any?, result: [String: Any]) {
        var obj: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id { obj["id"] = id }
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        sendJSON(connection, status: 200, body: String(data: data, encoding: .utf8) ?? "{}")
    }

    private func sendRPCError(_ connection: NWConnection, id: Any?, code: Int, message: String) {
        var obj: [String: Any] = [
            "jsonrpc": "2.0",
            "error": ["code": code, "message": message]
        ]
        if let id { obj["id"] = id }
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        sendJSON(connection, status: 200, body: String(data: data, encoding: .utf8) ?? "{}")
    }

    /// 发送无 body 的 HTTP 响应（用于 notifications/ 的 202 Accepted）
    private func sendEmpty(_ connection: NWConnection, status: Int) {
        let statusText: String
        switch status {
        case 202: statusText = "Accepted"
        default:  statusText = "No Content"
        }
        let header = "HTTP/1.1 \(status) \(statusText)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        let data = header.data(using: .utf8)!
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func sendJSON(_ connection: NWConnection, status: Int, body: String) {
        let bodyData = body.data(using: .utf8) ?? Data()
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 413: statusText = "Content Too Large"
        default:  statusText = "Error"
        }
        let header = "HTTP/1.1 \(status) \(statusText)\r\nContent-Length: \(bodyData.count)\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n"
        var resp = header.data(using: .utf8)!
        resp.append(bodyData)
        connection.send(content: resp, completion: .contentProcessed { _ in connection.cancel() })
    }
}
