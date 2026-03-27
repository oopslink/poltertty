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

    // MARK: - 请求积累

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
                self.sendJSON(connection, status: 413, body: #"{"error":{"code":"PAYLOAD_TOO_LARGE","message":"Request body exceeds 1MB limit"}}"#)
                return
            }

            guard let headerEnd = buf.range(of: Self.headerSeparator) else {
                if isComplete || error != nil {
                    self.sendJSON(connection, status: 400, body: #"{"error":{"code":"INCOMPLETE_REQUEST","message":"Incomplete HTTP request"}}"#)
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

        let startTime = Date()
        let parts = firstLine.components(separatedBy: " ")
        let method = parts.count > 0 ? parts[0] : "UNKNOWN"
        let rawPath = parts.count > 1 ? (parts[1].components(separatedBy: "?").first ?? parts[1]) : "/"

        let baseCtx = RequestContext(
            method: method, path: rawPath, startTime: startTime,
            requestBody: bodyData, toolName: nil,
            workspaceId: nil, surfaceId: nil
        )

        switch (method, rawPath) {
        case ("GET", "/v1/health"):
            sendJSON(connection, status: 200, body: "{}", context: baseCtx)
        case ("POST", "/v1/sessions"):
            handlePrepareSession(bodyData: bodyData, connection: connection, context: baseCtx)
        case ("POST", "/v1/hooks/events"):
            handleHook(bodyData: bodyData, connection: connection, context: baseCtx)
        case ("GET", "/v1/mcp"):
            handleSSE(connection: connection, context: baseCtx)
        case ("DELETE", "/v1/mcp"):
            sendEmpty(connection, status: 204, context: baseCtx)
        case ("POST", "/v1/mcp"):
            handleMCP(bodyData: bodyData, connection: connection, context: baseCtx)
        default:
            sendJSON(connection, status: 404, body: #"{"error":{"code":"NOT_FOUND","message":"Unknown endpoint: \#(method) \#(rawPath)"}}"#, context: baseCtx)
        }
    }

    // MARK: - Hook handlers

    private func handlePrepareSession(bodyData: Data, connection: NWConnection, context: RequestContext) {
        guard let req = try? decoder.decode(PrepareRequest.self, from: bodyData) else {
            Self.logger.warning("CtrlServer: failed to decode prepare-session request")
            sendJSON(connection, status: 400, body: #"{"error":{"code":"INVALID_JSON","message":"Failed to decode request body"}}"#, context: context)
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
                    cwd: req.cwd,
                    shellPid: req.pid
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
            // 构造含 workspaceId/surfaceId 的 context
            let ctx = RequestContext(
                method: context.method, path: context.path, startTime: context.startTime,
                requestBody: context.requestBody, toolName: nil,
                workspaceId: UUID(uuidString: req.workspaceId),
                surfaceId: UUID(uuidString: req.surfaceId)
            )
            self.sendJSON(connection, status: 200, body: responseBody, context: ctx)
        }
    }

    private func handleHook(bodyData: Data, connection: NWConnection, context: RequestContext) {
        guard var payload = try? decoder.decode(HookPayload.self, from: bodyData) else {
            let bodyPreview = String(data: bodyData.prefix(500), encoding: .utf8) ?? "(binary)"
            Self.logger.warning("CtrlServer: failed to decode hook payload (\(bodyData.count) bytes): \(bodyPreview)")
            sendJSON(connection, status: 400, body: #"{"error":{"code":"INVALID_JSON","message":"Failed to decode hook payload"}}"#, context: context)
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
        // 先发响应（不含 workspaceId），记录由下方 @MainActor Task 完成
        sendEmpty(connection, status: 202, context: context)
        Task { await EventBus.shared.emit(.hook(payload)) }
        Task { @MainActor in
            self.sessionManager.processHookEvent(payload)
            // 查 HookSessionStore 获取 workspaceId/surfaceId，补录 hook 调用记录
            let wsId: UUID?
            let sfId: UUID?
            if let sid = payload.sessionId, let session = HookSessionStore.shared.get(sid) {
                wsId = UUID(uuidString: session.workspaceId)
                sfId = UUID(uuidString: session.surfaceId)
            } else {
                wsId = nil
                sfId = nil
            }
            let truncReq = context.requestBody.flatMap { data -> String? in
                guard let s = String(data: data, encoding: .utf8) else { return nil }
                return s.count > 4096 ? String(s.prefix(4096)) + " [truncated]" : s
            }
            let record = CtrlAPIRecord(
                id: UUID(),
                timestamp: context.startTime,
                method: context.method,
                path: context.path,
                toolName: nil,
                requestBody: truncReq,
                responseBody: nil,
                statusCode: 202,
                durationMs: Date().timeIntervalSince(context.startTime) * 1000,
                error: nil,
                workspaceId: wsId,
                surfaceId: sfId
            )
            CtrlAPIStore.shared.append(record)
        }
    }

    // MARK: - SSE 长连接（GET /v1/mcp）

    private func handleSSE(connection: NWConnection, context: RequestContext) {
        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n"
        connection.send(content: header.data(using: .utf8)!, completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else { connection.cancel(); return }

            // 记录 SSE 连接建立（仅一次，后续推送不记录）
            let record = CtrlAPIRecord(
                id: UUID(),
                timestamp: context.startTime,
                method: context.method,
                path: "/v1/mcp (SSE)",
                toolName: nil,
                requestBody: nil,
                responseBody: nil,
                statusCode: 200,
                durationMs: Date().timeIntervalSince(context.startTime) * 1000,
                error: nil,
                workspaceId: nil,
                surfaceId: nil
            )
            Task { await MainActor.run { CtrlAPIStore.shared.append(record) } }

            let key = ObjectIdentifier(connection)

            // 每 30 秒发送 SSE 心跳，防止代理超时断开
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 30, repeating: 30)
            timer.setEventHandler { [weak connection] in
                connection?.send(content: ": ping\n\n".data(using: .utf8)!, completion: .idempotent)
            }
            timer.resume()
            self.queue.async { self.sseConnections[key] = (conn: connection, timer: timer) }

            // 订阅 EventBus，启动事件循环 Task
            Task {
                let (subscriberId, stream) = await EventBus.shared.subscribe()

                // 连接断开时：取消订阅（onTermination 作为双重保障）
                connection.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .failed, .cancelled:
                        self?.queue.async { [weak self] in
                            self?.sseConnections[key]?.timer.cancel()
                            self?.sseConnections.removeValue(forKey: key)
                        }
                        Task { await EventBus.shared.unsubscribe(subscriberId) }
                    default: break
                    }
                }

                // 消除竞态：subscribe() 期间可能已断开
                switch connection.state {
                case .failed, .cancelled:
                    Task { await EventBus.shared.unsubscribe(subscriberId) }
                    return
                default: break
                }

                for await event in stream {
                    guard let data = Self.formatSSENotification(event) else { continue }
                    connection.send(content: data, completion: .idempotent)
                }
            }
        })
    }

    /// 将 EventBus.Event 格式化为 SSE data 行（JSON-RPC 2.0 notification）
    private static func formatSSENotification(_ event: EventBus.Event) -> Data? {
        let method: String
        var params: [String: Any] = [:]

        switch event {
        case .hook(let payload):
            method = "notifications/hook"
            params["event"] = payload.hookEventName.rawValue
            params["sessionId"] = payload.sessionId ?? ""
        case .paneCreated(let paneId, let tabId, let workspaceId):
            method = "notifications/pane_created"
            params["paneId"] = paneId.uuidString
            params["tabId"] = tabId.uuidString
            params["workspaceId"] = workspaceId.uuidString
        case .paneClosed(let paneId):
            method = "notifications/pane_closed"
            params["paneId"] = paneId.uuidString
        case .paneFocused(let paneId):
            method = "notifications/pane_focused"
            params["paneId"] = paneId.uuidString
        case .tabCreated(let tabId, let workspaceId):
            method = "notifications/tab_created"
            params["tabId"] = tabId.uuidString
            params["workspaceId"] = workspaceId.uuidString
        case .tabClosed(let tabId):
            method = "notifications/tab_closed"
            params["tabId"] = tabId.uuidString
        }

        let obj: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
        guard let json = try? JSONSerialization.data(withJSONObject: obj),
              let jsonStr = String(data: json, encoding: .utf8) else { return nil }
        return "data: \(jsonStr)\n\n".data(using: .utf8)
    }

    // MARK: - JSON-RPC（POST /mcp）

    private func handleMCP(bodyData: Data, connection: NWConnection, context: RequestContext) {
        guard
            let obj = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
            let method = obj["method"] as? String
        else {
            sendRPCError(connection, id: nil, code: -32700, message: "Parse error", context: context)
            return
        }
        let id = obj["id"]
        let params = obj["params"] as? [String: Any]

        // notifications 为单向消息，按 MCP Streamable HTTP 规范返回 202 Accepted（无 body）
        if method.hasPrefix("notifications/") {
            sendEmpty(connection, status: 202, context: context)
            return
        }

        switch method {
        case "initialize":   handleInitialize(connection: connection, id: id, context: context)
        case "tools/list":   handleToolsList(connection: connection, id: id, context: context)
        case "tools/call":   handleToolsCall(connection: connection, id: id, params: params, context: context)
        default:             sendRPCError(connection, id: id, code: -32601, message: "Method not found: \(method)", context: context)
        }
    }

    private func handleInitialize(connection: NWConnection, id: Any?, context: RequestContext) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let result: [String: Any] = [
            "protocolVersion": "2025-03-26",
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": ["name": "poltertty", "version": version]
        ]
        sendRPCResult(connection, id: id, result: result, context: context)
    }

    private func handleToolsList(connection: NWConnection, id: Any?, context: RequestContext) {
        var tools: [[String: Any]] = [
            [
                "name": "get_instance_info",
                "description": "Get Poltertty instance info including version, port, and all workspace IDs with names and root directories",
                "inputSchema": ["type": "object", "properties": [String: Any]()]
            ],
            [
                "name": "create_tab",
                "description": "Create a new tab in the specified or default workspace; returns the new pane ID",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "workspaceId": ["type": "string", "description": "UUID of the target workspace (optional)"]
                    ]
                ]
            ],
            [
                "name": "list_panes",
                "description": "List all panes in the specified or all workspaces",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "workspaceId": ["type": "string", "description": "UUID of the target workspace (optional)"]
                    ]
                ]
            ],
            [
                "name": "focus_pane",
                "description": "Switch focus to the specified pane",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "paneId": ["type": "string", "description": "UUID of the target pane"]
                    ],
                    "required": ["paneId"]
                ]
            ],
            [
                "name": "send_text",
                "description": "Write text to the specified pane or the currently focused pane",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string", "description": "Text to write to the terminal"],
                        "paneId": ["type": "string", "description": "UUID of the target pane (optional, defaults to focused pane)"]
                    ],
                    "required": ["text"]
                ]
            ],
            [
                "name": "split_pane",
                "description": "Split the specified pane; returns the new pane ID",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "paneId": ["type": "string", "description": "UUID of the pane to split"],
                        "direction": ["type": "string", "enum": ["left", "right", "up", "down"], "description": "Split direction"],
                        "command": ["type": "string", "description": "Optional shell command to execute in the new pane after splitting (newline appended automatically)"]
                    ],
                    "required": ["paneId", "direction"]
                ]
            ],
            [
                "name": "set_pane_annotation",
                "description": "Set or clear annotation (purpose label) for a pane",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "paneId": ["type": "string", "description": "UUID of the target pane"],
                        "annotation": ["type": "string", "description": "Annotation text (empty or null to clear)"]
                    ],
                    "required": ["paneId"]
                ]
            ],
            [
                "name": "get_pane_annotation",
                "description": "Get the annotation of a pane",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "paneId": ["type": "string", "description": "UUID of the target pane"]
                    ],
                    "required": ["paneId"]
                ]
            ],
            [
                "name": "list_worktrees",
                "description": "List all git worktrees for the given directory (defaults to the active workspace root)",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "directory": ["type": "string", "description": "Absolute path to the git repository (optional; defaults to active workspace root)"]
                    ]
                ]
            ],
            [
                "name": "create_worktree",
                "description": "Create a new git worktree at the specified path, optionally creating a new branch",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "directory": ["type": "string", "description": "Absolute path to the git repository"],
                        "path": ["type": "string", "description": "Path for the new worktree (absolute, or relative to 'directory')"],
                        "branch": ["type": "string", "description": "New branch name to create (optional; omit to checkout existing branch named after the path)"],
                        "baseBranch": ["type": "string", "description": "Branch or commit to base the new branch on (optional; defaults to HEAD)"]
                    ],
                    "required": ["directory", "path"]
                ]
            ],
            [
                "name": "get_git_status",
                "description": "Get git status for the given directory: branch name, staged/unstaged/untracked files",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "directory": ["type": "string", "description": "Absolute path to the git repository (optional; defaults to active workspace root)"]
                    ]
                ]
            ]
        ]
        #if DEBUG
        tools.append(contentsOf: [
            [
                "name": "click_window",
                "description": "[DEBUG] Simulate a left mouse click at (x, y) in the window content view (y from top)",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "x": ["type": "number", "description": "X coordinate in window content view"],
                        "y": ["type": "number", "description": "Y coordinate in window content view (0 = top)"]
                    ],
                    "required": ["x", "y"]
                ]
            ],
            [
                "name": "test_fullscreen_diff",
                "description": "[DEBUG] Open Git panel, set a test diff to fullscreen mode, and take a screenshot",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "workspaceId": ["type": "string", "description": "Optional workspace UUID"]
                    ]
                ]
            ],
            [
                "name": "git_panel_state",
                "description": "[DEBUG] Get internal Git panel state for debugging",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "workspaceId": ["type": "string", "description": "Optional workspace UUID"]
                    ]
                ]
            ]
        ])
        #endif
        sendRPCResult(connection, id: id, result: ["tools": tools], context: context)
    }

    private func handleToolsCall(connection: NWConnection, id: Any?, params: [String: Any]?, context: RequestContext) {
        guard let name = params?["name"] as? String else {
            sendRPCError(connection, id: id, code: -32602, message: "Invalid params: missing name", context: context)
            return
        }
        let arguments = params?["arguments"] as? [String: Any] ?? [:]
        // 构造含 toolName 的 context 副本
        let toolCtx = RequestContext(
            method: context.method, path: context.path, startTime: context.startTime,
            requestBody: context.requestBody, toolName: name,
            workspaceId: context.workspaceId, surfaceId: context.surfaceId
        )
        let handler = CtrlToolHandler(port: self.port)
        Task {
            do {
                let resultText = try await handler.callTool(name: name, arguments: arguments)
                let content: [[String: Any]] = [["type": "text", "text": resultText]]
                self.sendRPCResult(connection, id: id, result: ["content": content], context: toolCtx)
            } catch let err as CtrlToolHandler.RPCError {
                self.sendRPCError(connection, id: id, code: err.code, message: err.message, context: toolCtx)
            } catch {
                self.sendRPCError(connection, id: id, code: -32603, message: error.localizedDescription, context: toolCtx)
            }
        }
    }

    // MARK: - Response helpers

    private func sendRPCResult(_ connection: NWConnection, id: Any?, result: [String: Any], context: RequestContext? = nil) {
        var obj: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id { obj["id"] = id }
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        sendJSON(connection, status: 200, body: String(data: data, encoding: .utf8) ?? "{}", context: context)
    }

    private func sendRPCError(_ connection: NWConnection, id: Any?, code: Int, message: String, context: RequestContext? = nil) {
        var obj: [String: Any] = [
            "jsonrpc": "2.0",
            "error": ["code": code, "message": message]
        ]
        if let id { obj["id"] = id }
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        sendJSON(connection, status: 200, body: String(data: data, encoding: .utf8) ?? "{}", context: context)
    }

    /// 发送无 body 的 HTTP 响应（用于 hook 事件的 202 Accepted 和 DELETE 的 204 No Content）
    private func sendEmpty(_ connection: NWConnection, status: Int, context: RequestContext? = nil) {
        let statusText: String
        switch status {
        case 202: statusText = "Accepted"
        case 204: statusText = "No Content"
        default:  statusText = "OK"
        }
        let header = "HTTP/1.1 \(status) \(statusText)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        let data = header.data(using: .utf8)!
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
            if let ctx = context {
                let truncReq = ctx.requestBody.flatMap { d -> String? in
                    guard let s = String(data: d, encoding: .utf8) else { return nil }
                    return s.count > 4096 ? String(s.prefix(4096)) + " [truncated]" : s
                }
                let record = CtrlAPIRecord(
                    id: UUID(),
                    timestamp: ctx.startTime,
                    method: ctx.method,
                    path: ctx.path,
                    toolName: ctx.toolName,
                    requestBody: truncReq,
                    responseBody: nil,
                    statusCode: status,
                    durationMs: Date().timeIntervalSince(ctx.startTime) * 1000,
                    error: nil,
                    workspaceId: ctx.workspaceId,
                    surfaceId: ctx.surfaceId
                )
                Task { await MainActor.run { CtrlAPIStore.shared.append(record) } }
            }
        })
    }

    private func sendJSON(_ connection: NWConnection, status: Int, body: String, context: RequestContext? = nil) {
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
        connection.send(content: resp, completion: .contentProcessed { _ in
            connection.cancel()
            if let ctx = context {
                let truncReq = ctx.requestBody.flatMap { d -> String? in
                    guard let s = String(data: d, encoding: .utf8) else { return nil }
                    return s.count > 4096 ? String(s.prefix(4096)) + " [truncated]" : s
                }
                let truncResp: String? = body.isEmpty ? nil
                    : (body.count > 4096 ? String(body.prefix(4096)) + " [truncated]" : body)
                let record = CtrlAPIRecord(
                    id: UUID(),
                    timestamp: ctx.startTime,
                    method: ctx.method,
                    path: ctx.path,
                    toolName: ctx.toolName,
                    requestBody: truncReq,
                    responseBody: truncResp,
                    statusCode: status,
                    durationMs: Date().timeIntervalSince(ctx.startTime) * 1000,
                    error: Self.extractRPCError(from: body),
                    workspaceId: ctx.workspaceId,
                    surfaceId: ctx.surfaceId
                )
                Task { await MainActor.run { CtrlAPIStore.shared.append(record) } }
            }
        })
    }

    private static func extractRPCError(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = obj["error"] as? [String: Any],
              let msg = error["message"] as? String else { return nil }
        return msg
    }
}
