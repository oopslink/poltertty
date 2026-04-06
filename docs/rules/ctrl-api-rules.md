# Ctrl API 设计规范

本文档规定 Poltertty Ctrl API（MCP HTTP Server）的命名、路由、参数、响应和错误处理约定。
所有新工具和新路由必须严格遵循这些规范。

---

## 1. HTTP 路由（REST 层）

### 路由风格

- 所有路由使用 `/v1/` 前缀（版本前缀便于未来不破坏兼容地升级）
- 路由使用**名词复数**或**动词短语**，小写 kebab-case
- 不允许动词路由（如 ~~`/v1/doSomething`~~）

| 路由 | 方法 | 语义 |
|------|------|------|
| `/v1/health` | GET | 健康检查 |
| `/v1/sessions` | POST | 创建/初始化 session |
| `/v1/hooks/events` | POST | 接收 hook 事件（异步） |
| `/v1/mcp` | GET | 建立 SSE 事件流 |
| `/v1/mcp` | POST | JSON-RPC 2.0 工具调用 |
| `/v1/mcp` | DELETE | 关闭 SSE 连接 |

### HTTP 状态码

| 场景 | 状态码 |
|------|--------|
| 成功（有响应体） | 200 OK |
| 成功（创建资源） | 201 Created |
| 成功（异步处理，无响应体） | 202 Accepted |
| 成功（无响应体） | 204 No Content |
| 请求格式错误 | 400 Bad Request |
| 未授权 | 401 Unauthorized |
| 路由不存在 | 404 Not Found |
| 请求体超限（>1MB） | 413 Payload Too Large |
| 服务器内部错误 | 500 Internal Server Error |

---

## 2. MCP 工具（JSON-RPC 2.0 层）

### 协议

- 所有工具通过 `POST /v1/mcp` 的 JSON-RPC 2.0 协议访问
- Method: `tools/call`，Params: `{name, arguments}`
- 协议版本：`2025-03-26`

### 工具命名

- **格式**：`动词_名词`，snake_case
- 动词规范：

| 动词 | 适用场景 | 示例 |
|------|---------|------|
| `get_` | 读取单个资源 | `get_instance_info`, `get_pane_annotation` |
| `list_` | 读取列表 | `list_panes`, `list_worktrees` |
| `create_` | 创建资源 | `create_tab`, `create_worktree` |
| `set_` | 修改/设置属性 | `set_pane_annotation` |
| `delete_` | 删除资源（未来扩展） | `delete_worktree` |
| 语义动词 | 执行动作 | `send_text`, `focus_pane`, `split_pane`, `capture_screenshot` |

- **禁止**：camelCase、PascalCase、泛化动词（~~`do_`~~、~~`run_`~~、~~`execute_`~~）

### 参数命名

- 所有参数使用 **camelCase**
- 资源引用统一命名：`paneId`、`workspaceId`、`tabId`（UUID 字符串）
- 可选参数不写入 `required` 数组，实现层提供合理默认值
- 布尔参数不使用 `is` 前缀（参数已足够表意：`force: true` 而非 `isForce: true`）

### 响应格式

- 所有工具响应都是 **JSON 对象或数组**，由工具实现序列化为字符串，外层由 CtrlServer 封装为：
  ```json
  {"content": [{"type": "text", "text": "...JSON 字符串..."}]}
  ```
- 单资源操作：返回该资源的 JSON 对象
- 列表操作：返回 JSON 数组
- 纯状态确认：返回 `{"ok": true}`
- **禁止**返回裸字符串（非 JSON）

#### 响应字段命名

- 字段使用 **camelCase**
- 省略 `null` 值的字段（使用条件插入代替 `"field": null`）
- UUID 一律序列化为字符串
- 布尔字段不使用 `is` 前缀（`active: true` 而非 `isActive: true`）——**例外**：已有字段 `isActive`、`isMain` 等保持向后兼容，不改名

### 错误码

使用标准 JSON-RPC 2.0 错误码：

| 错误码 | 含义 | 使用场景 |
|--------|------|---------|
| `-32700` | Parse error | JSON 解析失败 |
| `-32601` | Method not found | 未知工具名 |
| `-32602` | Invalid params | 缺少必需参数、参数类型错误、枚举值无效 |
| `-32603` | Internal error | 工具执行失败（资源不存在、git 命令失败等） |

错误消息格式：`"<toolName>: <描述>"`，例如：
```
"split_pane: missing or invalid paneId"
"create_worktree: git error: branch 'foo' already exists"
```

---

## 3. SSE 事件流

- 事件格式：`data: {JSON-RPC 2.0 Notification}\n\n`
- 心跳：每 30 秒发送 `: ping\n\n`（防止代理超时）
- 事件方法（`method` 字段）使用 `notifications/` 前缀 + snake_case 事件名

| 事件方法 | 触发时机 | params 字段 |
|----------|---------|------------|
| `notifications/hook` | Claude Code hook 事件 | `{event, sessionId}` |
| `notifications/pane_created` | 新 pane 创建 | `{paneId, tabId, workspaceId}` |
| `notifications/pane_closed` | pane 关闭 | `{paneId}` |
| `notifications/pane_focused` | pane 获得焦点 | `{paneId}` |
| `notifications/tab_created` | 新 tab 创建 | `{tabId, workspaceId}` |
| `notifications/tab_closed` | tab 关闭 | `{tabId}` |
| `notifications/agent_status_changed` | Agent 状态变更 | `{sessionId, state, workspaceId, customLabel?}` |
| `notifications/workspace_switched` | 用户切换 Workspace | `{workspaceId, previousWorkspaceId?}` |

---

## 4. 调试工具管理

- 调试工具（仅用于自动化测试/回归）统一通过 `#if DEBUG` 条件编译暴露
- 调试工具命名加 `[DEBUG]` 描述前缀，以便 `tools/list` 响应中可识别
- 生产 Release 构建不暴露调试工具
- 调试工具参考：`click_window`、`test_fullscreen_diff`、`git_panel_state`

---

## 5. 工具实现约定（Swift）

```swift
// 方法签名
private func callToolName(arguments: [String: Any]) async throws -> String

// MainActor 操作：通过 withCheckedThrowingContinuation + Task { @MainActor in } 桥接
let result: ReturnType = try await withCheckedThrowingContinuation { cont in
    Task { @MainActor in
        // UI 操作
        cont.resume(returning: value)
    }
}

// shell 命令：通过 CtrlShellRunner 执行，不直接使用 Process
let r = CtrlShellRunner.git(["-C", dir, "status", "--porcelain"])
guard r.succeeded else {
    throw RPCError(code: -32603, message: "tool_name: \(r.trimmedStderr)")
}

// 序列化失败
throw RPCError(code: -32603, message: "<toolName>: serialization failed")

// 参数校验失败
throw RPCError(code: -32602, message: "<toolName>: missing or invalid <paramName>")
```

### 默认目录解析（directory 参数）

凡接受可选 `directory` 参数的工具，默认值解析顺序：
1. 参数非空时直接使用
2. keyWindow 所属 workspace 的 `rootDirExpanded`
3. 第一个 workspace 的 `rootDirExpanded`
4. 无法解析时抛出 `-32602`

---

## 6. 文档规范

- 规则文档统一放在 `docs/rules/` 目录
- 测试计划和测试结果按日期放在 `docs/tests/YYYY-MM-DD/` 目录
  - `ctrl-api-test-plan.md` — 测试计划
  - `ctrl-api-test-results.md` — 测试执行结果
- 文档中**禁止写入本机绝对路径**（如 `/Users/xxx/...`），统一用 `<repo-root>` 占位或使用相对路径

---

## 7. 工具新增 Checklist

新增工具时需同步更新以下四个位置，缺一不可：

- [ ] `CtrlToolHandler.callTool()` — 添加 `case "tool_name":` 分支
- [ ] `CtrlToolHandler` — 实现 `private func callToolName()` 方法
- [ ] `CtrlServer.handleToolsList()` — 添加工具 schema（name / description / inputSchema）
- [ ] `docs/rules/ctrl-api-rules.md` — 如有新约定，更新本文档
- [ ] `docs/tests/<YYYY-MM-DD>/ctrl-api-test-plan.md` — 添加对应测试用例（可选但推荐）
