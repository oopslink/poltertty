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
└── SettingsMerger          (注入 MCP URL 到 .mcp.json)
```

### 实例隔离

每个 Poltertty 实例独立绑定随机端口（与 HookServer 策略一致）。`SettingsMerger` 在生成 session settings 时将 MCP URL 写入该 session 专属的 `.mcp.json`，通过已有的 `--settings` 参数传给 Claude Code。不同 Poltertty 实例之间无端口交叉。

---

## 组件设计

### CtrlServer

- 独立 HTTP server，随机端口，`AgentService.start()` 中并列 HookServer 启动
- 端点：
  - `POST /mcp` — 处理所有 JSON-RPC 请求（initialize、tools/list、tools/call）
  - `GET /mcp` — SSE 流（第一版返回空流，仅满足协议握手）
  - `DELETE /mcp` — 关闭 session（返回 200，暂不做实际处理）
- 所有 UI 操作通过 `Task { @MainActor in ... }` 回到主线程执行

### CtrlToolHandler

分发 MCP tools/call 请求到具体实现：

| Tool | 参数 | 说明 |
|---|---|---|
| `ping` | 无 | 验证连通性，返回实例信息 |
| `new_tab` | `workspaceId?: String` | 在当前/指定 workspace 新建 tab |

`ping` 返回：
```json
{
  "instanceId": "<process UUID>",
  "version": "0.1.8",
  "port": 12345
}
```

### SettingsMerger 扩展

在生成的 `.mcp.json` 中写入：
```json
{
  "mcpServers": {
    "poltertty": {
      "type": "http",
      "url": "http://localhost:{ctrlPort}/mcp"
    }
  }
}
```

---

## 数据流

```
Claude Code
  → POST http://localhost:{ctrlPort}/mcp  (tools/call: new_tab)
  → CtrlServer.handleMCP()
  → CtrlToolHandler.handle(tool: "new_tab", args: {...})
  → DispatchQueue.main: TerminalController.addNewTab()
  → 返回 JSON-RPC result
```

---

## 错误处理

| 场景 | JSON-RPC Error Code |
|---|---|
| 工具不存在 | `-32601` Method not found |
| 参数格式错误 | `-32602` Invalid params |
| UI 操作失败 | `-32603` Internal error（附描述） |

---

## MCP 协议握手

Claude Code 连接时序：
1. `initialize` — 握手，返回 server capabilities
2. `tools/list` — 返回工具列表
3. `tools/call` — 按需调用

第一版无状态处理，每次请求独立。

---

## 不在范围内（第一版）

- `send_text`、`list_panes`、`focus_pane`、`split_pane` 等工具
- MCP session 管理（server-initiated messages）
- HookServer 合并到 CtrlServer

---

## TODO

- [ ] 后续将 HookServer 合并到 CtrlServer，统一为单一 HTTP server 处理所有端点（`/hook`、`/hooks/prepare-session`、`/mcp`）

---

## 文件位置

新增文件：
- `macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift`
- `macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift`

修改文件：
- `macos/Sources/Features/Agent/AgentService.swift` — 启动 CtrlServer
- `macos/Sources/Features/Agent/HookServer/SettingsMerger.swift` — 注入 MCP URL
