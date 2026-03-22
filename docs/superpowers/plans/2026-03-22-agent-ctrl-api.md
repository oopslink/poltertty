# Agent Ctrl API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Poltertty 内嵌独立的 MCP Server（CtrlServer），让 Claude Code 等 agent 通过 MCP 协议控制 Poltertty（新建 tab 等），支持多实例隔离。

**Architecture:** CtrlServer 独立绑定随机端口，实现 MCP Streamable HTTP 协议（POST /mcp + GET /mcp SSE 长连接）；CtrlToolHandler 持有 CtrlServer 端口副本，分发 ping/new_tab 工具调用到 TerminalController；SettingsMerger 将 MCP URL 写入 session 专属 settings.json 注入给 Claude Code。

**Tech Stack:** Swift 6, NWListener/NWConnection, DispatchSourceTimer, JSONSerialization, MCP Streamable HTTP (JSON-RPC 2.0, protocol version 2025-03-26)

---

## 文件结构

| 操作 | 路径 | 职责 |
|---|---|---|
| 新建 | `macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift` | HTTP server，端口绑定，请求路由，SSE 连接管理（心跳 + 自动清理） |
| 新建 | `macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift` | MCP tools 分发：ping、new_tab（持有 port 副本，不访问 AgentService） |
| 修改 | `macos/Sources/Features/Agent/AgentService.swift` | 启动 CtrlServer |
| 修改 | `macos/Sources/Features/Agent/HookServer/SettingsMerger.swift` | 增加 ctrlPort 参数，写入 mcpServers |

---

## 并发隔离说明

- `CtrlServer` 是普通 class，在 `queue`（utility serial queue）上运行
- `sseConnections` 数组只在 `queue` 上访问，无数据竞争
- `CtrlToolHandler` 接收 `port: UInt16` 值拷贝（非 @MainActor 属性访问），ping 在 background 线程安全返回
- `handleToolsCall` 调用顺序：background queue → `sendRPCResult`（仍在 queue）→ `Task { @MainActor in handler.execute(...) }`
- `HookServer.handlePrepareSession` 已在 `Task { @MainActor in }` 闭包内，读取 `AgentService.shared.ctrlServer?.port` 是安全的（两者均 @MainActor）

---

## Task 1：创建 worktree

- [ ] **Step 1: 创建 worktree**

```bash
git worktree add .worktrees/agent-ctrl-api feat/agent-ctrl-api
```

- [ ] **Step 2: 确认状态**

```bash
cd .worktrees/agent-ctrl-api && git status
```

Expected: `On branch feat/agent-ctrl-api, nothing to commit`

---

## Task 2：CtrlServer — 端口绑定、请求路由、SSE 管理

**Files:**
- Create: `macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift`

- [ ] **Step 1: 创建 CtrlServer.swift**

```swift
// macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift
import Foundation
import Network
import OSLog

/// 内嵌 MCP HTTP server，供 agent 调用 Poltertty 控制接口
/// 每个实例绑定随机端口，通过 SettingsMerger 注入给 Claude Code settings
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

    func handleMCP(bodyData: Data, connection: NWConnection) {
        guard
            let obj = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
            let method = obj["method"] as? String
        else {
            sendRPCError(connection, id: nil, code: -32700, message: "Parse error")
            return
        }
        let id = obj["id"]
        let params = obj["params"] as? [String: Any]

        if method.hasPrefix("notifications/") { return }

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

    func sendJSON(_ connection: NWConnection, status: Int, body: String) {
        let bodyData = body.data(using: .utf8) ?? Data()
        let statusText = status == 200 ? "OK" : "Error"
        let header = "HTTP/1.1 \(status) \(statusText)\r\nContent-Length: \(bodyData.count)\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n"
        var resp = header.data(using: .utf8)!
        resp.append(bodyData)
        connection.send(content: resp, completion: .contentProcessed { _ in connection.cancel() })
    }
}
```

- [ ] **Step 2: 在 Xcode 项目中添加文件**

在 Xcode 中，`Features/Agent/` group 下新建 `CtrlServer` group，添加 `CtrlServer.swift`（Add Files to "Poltertty"，确认 target membership 勾选 Poltertty）。

- [ ] **Step 3: 构建确认**

```bash
xcodebuild -scheme Poltertty -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift
git commit -m "feat(ctrl): add CtrlServer with MCP routing and SSE keep-alive"
```

---

## Task 3：CtrlToolHandler — ping + new_tab

**Files:**
- Create: `macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift`

- [ ] **Step 1: 创建 CtrlToolHandler.swift**

```swift
// macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift
import Foundation
import AppKit
import OSLog

/// MCP tool 实现。
/// prepareResult() 在 background queue 调用，只做纯数据处理，不访问 @MainActor 属性。
/// execute() 标注 @MainActor，执行所有 UI 副作用。
final class CtrlToolHandler {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "CtrlToolHandler"
    )

    struct RPCError {
        let code: Int
        let message: String
    }

    /// port 由 CtrlServer 在初始化时以值拷贝形式传入，
    /// 避免在 background 线程访问 @MainActor 的 AgentService 属性
    private let port: UInt16

    init(port: UInt16) {
        self.port = port
    }

    // MARK: - prepareResult（background queue 安全）

    func prepareResult(tool: String, arguments: [String: Any]) -> (String?, RPCError?) {
        switch tool {
        case "ping":    return (pingResult(), nil)
        case "new_tab": return (#"{"status":"accepted"}"#, nil)
        default:        return (nil, RPCError(code: -32601, message: "Unknown tool: \(tool)"))
        }
    }

    // MARK: - execute（@MainActor）

    @MainActor
    func execute(tool: String, arguments: [String: Any]) {
        switch tool {
        case "new_tab": executeNewTab(arguments: arguments)
        default: break
        }
    }

    // MARK: - ping

    private func pingResult() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let instanceId = Bundle.main.bundleIdentifier ?? "unknown"
        let obj: [String: Any] = [
            "instanceId": instanceId,
            "version": version,
            "port": Int(port)   // JSON number，避免 UInt16 序列化歧义
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let str = String(data: data, encoding: .utf8) else {
            return #"{"error":"serialization failed"}"#
        }
        return str
    }

    // MARK: - new_tab

    @MainActor
    private func executeNewTab(arguments: [String: Any]) {
        let tc: TerminalController?

        if let wsIdStr = arguments["workspaceId"] as? String {
            guard let wsId = UUID(uuidString: wsIdStr) else {
                Self.logger.warning("new_tab: invalid workspaceId UUID: \(wsIdStr)")
                return
            }
            let window = WorkspaceManager.shared.windowForWorkspace(wsId)
            tc = (window as? TerminalWindow)?.terminalController
        } else {
            // keyWindow 为 nil（app 在后台）时，遍历 windows 找第一个 TerminalWindow
            let target = NSApp.keyWindow ?? NSApp.windows.first { $0 is TerminalWindow }
            tc = (target as? TerminalWindow)?.terminalController
        }

        guard let tc else {
            Self.logger.warning("new_tab: no TerminalController found")
            return
        }

        tc.addNewTab()
        Self.logger.info("new_tab: executed successfully")
    }
}
```

- [ ] **Step 2: 在 Xcode 中添加文件**

在 `Features/Agent/CtrlServer` group 添加 `CtrlToolHandler.swift`，确认 target membership。

- [ ] **Step 3: 构建确认**

```bash
xcodebuild -scheme Poltertty -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift
git commit -m "feat(ctrl): add CtrlToolHandler with ping and new_tab"
```

---

## Task 4：AgentService 集成

**Files:**
- Modify: `macos/Sources/Features/Agent/AgentService.swift`

- [ ] **Step 1: 添加 ctrlServer 属性**

在 `hookServer` 声明旁边添加：

```swift
var ctrlServer: CtrlServer? = nil
```

- [ ] **Step 2: 在 start() 中启动 CtrlServer**

在 `hookServer?.start()` 之后添加（顺序重要：CtrlServer 须在 HookServer 之后启动，确保 handlePrepareSession 触发时端口已就绪）：

```swift
ctrlServer = CtrlServer()
ctrlServer?.start()
```

- [ ] **Step 3: 在 shutdown() 中停止 CtrlServer**

在 `hookServer?.stop()` 之后添加：

```swift
ctrlServer?.stop()
```

- [ ] **Step 4: 构建确认**

```bash
xcodebuild -scheme Poltertty -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Agent/AgentService.swift
git commit -m "feat(ctrl): start CtrlServer in AgentService"
```

---

## Task 5：SettingsMerger 扩展 — 注入 mcpServers

**Files:**
- Modify: `macos/Sources/Features/Agent/HookServer/SettingsMerger.swift`
- Modify: `macos/Sources/Features/Agent/HookServer/HookServer.swift`

- [ ] **Step 1: 修改 SettingsMerger.mergeAndWrite 签名**

将函数签名改为（默认值 0 保持向后兼容，现有 HookServer 调用点不需要修改）：

```swift
static func mergeAndWrite(
    sessionId: String,
    sessionDir: String,
    cwd: String,
    cliPath: String,
    userSettingsPath: String?,
    ctrlPort: UInt16 = 0
) {
```

- [ ] **Step 2: 写入 settings.json 时追加 mcpServers**

将：
```swift
// 4. 写 settings.json（仅 hooks 字段）
let settings: [String: Any] = ["hooks": mergedHooks]
```

替换为：

```swift
// 4. 写 settings.json（hooks + mcpServers）
var settings: [String: Any] = ["hooks": mergedHooks]
if ctrlPort > 0 {
    settings["mcpServers"] = [
        "poltertty": [
            "type": "http",
            "url": "http://localhost:\(ctrlPort)/mcp"
        ]
    ]
}
```

- [ ] **Step 3: 在 HookServer.handlePrepareSession 中传入 ctrlPort**

`handlePrepareSession` 已在 `Task { @MainActor in }` 闭包内，读取 `AgentService.shared.ctrlServer?.port` 是 MainActor 安全的。在 `SettingsMerger.mergeAndWrite(...)` 调用处追加参数：

```swift
// 在 Task { @MainActor in } 闭包内，AgentService 访问安全
let ctrlPort = AgentService.shared.ctrlServer?.port ?? 0
SettingsMerger.mergeAndWrite(
    sessionId: req.sessionId,
    sessionDir: sessionDir,
    cwd: req.cwd,
    cliPath: cliPath,
    userSettingsPath: req.userSettings,
    ctrlPort: ctrlPort
)
```

- [ ] **Step 4: 构建确认**

```bash
xcodebuild -scheme Poltertty -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Agent/HookServer/SettingsMerger.swift
git add macos/Sources/Features/Agent/HookServer/HookServer.swift
git commit -m "feat(ctrl): inject MCP URL into Claude Code settings via SettingsMerger"
```

---

## Task 6：端到端验证

**Files:** 无代码变更

- [ ] **Step 1: 启动 Poltertty，找到端口**

启动 app，Console.app 过滤 `CtrlServer`：
```
CtrlServer listening on port 54321
```
后续步骤将 `54321` 替换为实际端口。

- [ ] **Step 2: 测试 initialize**

```bash
curl -s -X POST http://localhost:54321/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | python3 -m json.tool
```

Expected:
```json
{
  "jsonrpc": "2.0", "id": 1,
  "result": {
    "protocolVersion": "2025-03-26",
    "capabilities": {"tools": {}},
    "serverInfo": {"name": "poltertty", "version": "0.1.x"}
  }
}
```

- [ ] **Step 3: 测试 tools/list**

```bash
curl -s -X POST http://localhost:54321/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | python3 -m json.tool
```

Expected: `tools` 数组包含 `ping` 和 `new_tab`。

- [ ] **Step 4: 测试 ping**

```bash
curl -s -X POST http://localhost:54321/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"ping","arguments":{}}}' | python3 -m json.tool
```

Expected: `content[0].text` 包含 `instanceId`、`version`、`port`。

- [ ] **Step 5: 测试 new_tab**

```bash
curl -s -X POST http://localhost:54321/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"new_tab","arguments":{}}}' | python3 -m json.tool
```

Expected: 返回 `{"status":"accepted"}`，Poltertty 窗口新增一个 Tab。

- [ ] **Step 6: 测试 SSE 长连接**

```bash
curl -v -N -H "Accept: text/event-stream" http://localhost:54321/mcp
```

Expected: 连接建立后保持存活，响应头包含 `Content-Type: text/event-stream`，30 秒后收到 `: ping` 心跳行。

- [ ] **Step 7: 验证 settings.json 注入**

通过 Agent Launcher 启动一个 Claude Code 会话，检查生成的 settings 文件：

```bash
cat ~/.poltertty/sessions/*/settings.json | python3 -m json.tool
```

Expected: 包含 `mcpServers.poltertty.url` 指向正确端口。

---

## Task 7：开 PR

- [ ] **Step 1: Push 分支**

```bash
git push -u origin feat/agent-ctrl-api
```

- [ ] **Step 2: 创建 PR**

```bash
gh pr create \
  --title "feat: agent ctrl api — embedded MCP server for agent-driven terminal control" \
  --body "$(cat <<'EOF'
## Summary
- 新增 CtrlServer：内嵌 MCP Streamable HTTP server，独立随机端口，多实例隔离，SSE 长连接含心跳
- 新增 CtrlToolHandler：实现 ping、new_tab 工具，port 以值拷贝传入避免 @MainActor 跨线程访问
- SettingsMerger 扩展：ctrlPort 默认参数向后兼容，ctrlPort > 0 时写入 mcpServers
- AgentService 集成：并列 HookServer 启动 CtrlServer

## Test plan
- [ ] curl initialize 返回正确 protocolVersion 和 serverInfo（version 从 Bundle 读取）
- [ ] curl tools/list 返回 ping 和 new_tab
- [ ] curl ping 返回 instanceId/version/port
- [ ] curl new_tab 触发 Poltertty 新建 Tab
- [ ] curl GET /mcp SSE 连接保持存活，30 秒后收到心跳
- [ ] ~/.poltertty/sessions/*/settings.json 包含 mcpServers.poltertty.url

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## 注意事项

1. **Xcode 文件注册**：新建 `.swift` 必须在 Xcode 中手动 Add Files 并确认 target membership，否则不编译
2. **CtrlServer 启动顺序**：必须在 HookServer 之后启动（`AgentService.start()` 中已保证），确保 `handlePrepareSession` 触发时 `ctrlPort` 已就绪
3. **SSE timer 清理**：`stop()` 和 `stateUpdateHandler` 均会 cancel timer，DispatchSourceTimer cancel 是幂等操作，无需额外保护
4. **`NSApp.windows` 遍历**：只在 keyWindow 为 nil 时触发（app 在后台），正常使用场景下 keyWindow 必然有值
