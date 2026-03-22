# Agent Ctrl API 后续

> 基础已在 #54 落地（CtrlServer + MCP ping/new_tab）。以下为后续迭代方向，按优先级排列。

- [ ] **合并 HookServer 到 CtrlServer** — 统一为单一 HTTP server 处理 `/hook`、`/hooks/prepare-session`、`/mcp`，消除两个 NWListener 实例，简化 AgentService 生命周期管理
- [ ] **new_tab 反馈实际结果** — 当前立即返回 `{"status":"accepted"}` 不等待 UI；改为等待主线程执行结果，成功返回 tab ID，失败返回 JSON-RPC `-32603`
- [ ] **更多控制工具** — `send_text`（向 PTY 写入文本）、`list_panes`（列出当前 workspace 的 surface/tab）、`focus_pane`（切换焦点到指定 surface）、`split_pane`（水平/垂直分屏）
- [ ] **MCP session 管理** — 支持 server-initiated messages（SSE events），实现 agent 订阅终端事件（如 hook 事件推送到已连接的 SSE stream）
- [ ] **workspaceId 发现** — 在 ping 响应中附带当前所有 workspace 的 UUID，方便 agent 调用 new_tab 时无需手动指定
