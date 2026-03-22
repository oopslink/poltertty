# Poltertty Agent Ctrl API 设计文档

**日期**：2026-03-22
**状态**：已批准
**特性**：poltertty agent 可达性改造

---

## 背景与目标

允许 agent（如 Claude Code）通过标准 MCP 协议主动控制 Poltertty 的行为（打开窗口、新建 Tab 等），用于自动化测试和 agent 驱动的工作流。

第一版专注于**机制建立**：MCP Server 嵌入 Poltertty、协议握手、工具发现、工具调用链路打通。

---

## 架构

```
Poltertty App
├── AgentService
│   ├── HookServer          (现有，不动，过渡期保留)
│   └── CtrlServer          (新建，MCP over Streamable HTTP)
│       └── CtrlToolHandler (工具分发，调用 TerminalController)
└── SettingsMerger          (注入 MCP URL 到 settings.json)
```

### 实例隔离

每个 Poltertty 实例独立绑定随机端口（与 HookServer 策略一致）。`SettingsMerger` 在生成 session settings 时将 `mcpServers` 写入该 session 专属的 `settings.json`，通过已有的 `--settings` 参数传给 Claude Code。不同 Poltertty 实例之间无端口交叉。

---

## 组件设计

### CtrlServer

独立 HTTP server，随机端口，`AgentService.start()` 中并列 HookServer 启动。

**端点：**

- `POST /mcp` — 处理所有 JSON-RPC 请求（`initialize`、`tools/list`、`tools/call`）
- `GET /mcp` — SSE 长连接。必须保持 keep-alive，发送 `Content-Type: text/event-stream` + `Cache-Control: no-cache` headers 后持有 NWConnection 不 cancel，直到服务端 stop 或客户端断开时才关闭。第一版不发送任何 SSE event，但连接必须存活。
- `DELETE /mcp` — 返回 200，无副作用（仅为协议兼容，第一版不做 session 清理）

**线程模型：**

CtrlServer 在 background 线程（NWListener queue）接收请求。所有 UI 操作通过 `Task { @MainActor in ... }` 回到主线程执行。

**HTTP response 时机（new_tab）：**

采用"先 respond、后异步执行 UI"策略（与 HookServer `/hook` 一致）：立即返回 200 + JSON-RPC result，主线程 UI 操作在 response 发送后异步执行。第一版不向 agent 反馈 UI 操作的成败，保持简单。

### CtrlToolHandler

分发 MCP `tools/call` 请求到具体实现：

| Tool | 参数 | 说明 |
|---|---|---|
| `ping` | 无 | 验证连通性，返回实例信息 |
| `new_tab` | `workspaceId?: String` | 在当前/指定 workspace 新建 tab |

**`ping` 返回：**
```json
{
  "instanceId": "<process UUID>",
  "version": "<Bundle.main CFBundleShortVersionString>",
  "port": 12345
}
```

`version` 从 `Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"` 读取，不硬编码。

**`new_tab` 的 TerminalController 查找链路：**

1. `workspaceId` 有值时：`UUID(uuidString: workspaceId)` → `WorkspaceManager.shared.windowForWorkspace(id:)` → `window.windowController as? TerminalController`
2. `workspaceId` 为 nil 或对应 workspace 不存在时：fallback 到 `NSApp.keyWindow?.windowController as? TerminalController`
3. 两者均无法得到有效 controller 时：返回 JSON-RPC error `-32603`，描述 "No active terminal window"

### SettingsMerger 扩展

`SettingsMerger.mergeAndWrite` 增加 `ctrlPort: UInt16 = 0` 参数（默认值 0 表示不注入 mcpServers，向后兼容 HookServer 现有调用点，无需修改 HookServer.swift）。`ctrlPort > 0` 时，在同一 `settings.json` 中追加 `mcpServers`（Claude Code 0.2+ 支持在 settings.json 中配置 mcpServers）：

```json
{
  "hooks": { ... },
  "mcpServers": {
    "poltertty": {
      "type": "http",
      "url": "http://localhost:{ctrlPort}/mcp"
    }
  }
}
```

`AgentService.start()` 在 CtrlServer 启动后将 `ctrlPort` 传入 `mergeAndWrite`（通过 `HookServer.handlePrepareSession` 的调用链）。`workspaceId` 为 String 时，`CtrlToolHandler` 先调用 `UUID(uuidString:)` 转换，失败则返回 `-32602`。

---

## MCP 协议实现

### initialize 握手

request：
```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26",...}}
```

response：
```json
{
  "jsonrpc": "2.0", "id": 1,
  "result": {
    "protocolVersion": "2025-03-26",
    "capabilities": { "tools": {} },
    "serverInfo": { "name": "poltertty", "version": "<CFBundleShortVersionString>" }
  }
}
```

`protocolVersion` 固定返回 `"2025-03-26"`（当前 MCP 规范版本）。`serverInfo.version` 同样从 Bundle 读取，不硬编码。

### tools/list response

```json
{
  "jsonrpc": "2.0", "id": 2,
  "result": {
    "tools": [
      {
        "name": "ping",
        "description": "Ping the Poltertty instance to verify connectivity",
        "inputSchema": { "type": "object", "properties": {} }
      },
      {
        "name": "new_tab",
        "description": "Open a new tab in the specified or current workspace",
        "inputSchema": {
          "type": "object",
          "properties": {
            "workspaceId": { "type": "string", "description": "UUID of the target workspace (optional)" }
          }
        }
      }
    ]
  }
}
```

---

## 数据流

```
Claude Code
  → POST http://localhost:{ctrlPort}/mcp  (tools/call: new_tab)
  → CtrlServer.handleMCP()
  → 立即 sendResponse(200, JSON-RPC result)
  → Task { @MainActor in CtrlToolHandler.handle("new_tab", args) }
      → WorkspaceManager / NSApp.keyWindow → TerminalController
      → TerminalController.addNewTab()
```

---

## 错误处理

| 场景 | JSON-RPC Error Code |
|---|---|
| 工具不存在 | `-32601` Method not found |
| 参数格式错误 | `-32602` Invalid params |
| UI 操作失败（无可用窗口等） | `-32603` Internal error（附描述） |

**Content-Type 验证**：第一版不做请求头校验（已知协议简化点，后续合并 HookServer 时统一处理）。

---

## 不在范围内（第一版）

- `send_text`、`list_panes`、`focus_pane`、`split_pane` 等工具
- MCP session 管理（server-initiated messages / SSE events）
- HookServer 合并到 CtrlServer
- HTTP response 中反馈 UI 操作的实际结果

---

## TODO

- [ ] 后续将 HookServer 合并到 CtrlServer，统一为单一 HTTP server 处理所有端点（`/hook`、`/hooks/prepare-session`、`/mcp`）

---

## 文件位置

新增：
- `macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift`
- `macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift`

修改：
- `macos/Sources/Features/Agent/AgentService.swift` — 启动 CtrlServer，传 ctrlPort 给 SettingsMerger
- `macos/Sources/Features/Agent/HookServer/SettingsMerger.swift` — 增加 `ctrlPort` 参数，写入 `mcpServers`
