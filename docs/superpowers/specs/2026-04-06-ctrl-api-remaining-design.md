# Ctrl API 2.2 剩余接口设计

**日期**: 2026-04-06  
**范围**: Phase 2.2 未实现的 4 个工具 + 2 个 SSE 事件  
**前提**: `open_workspace` 已作为 `create_workspace` 的等价实现存在，不重复添加

---

## 待实现清单

| 类型 | 名称 | 状态 |
|------|------|------|
| 工具 | `set_agent_label` | 待实现 |
| 工具 | `get_workspace_state` | 待实现 |
| 工具 | `notify` | 待实现 |
| 工具 | `open_in_file_browser` | 待实现 |
| SSE 事件 | `agent_status_changed` | 待实现 |
| SSE 事件 | `workspace_switched` | 待实现 |

---

## 1. `set_agent_label`

### 功能

允许 Agent 通过 claudeSessionId 在调度台中设置自身的自定义标签和状态。

### 参数

```json
{
  "sessionId": "string (required) — Claude session ID，即 CLAUDE_SESSION_ID 环境变量",
  "label":     "string (required) — 自定义显示标签（如 'feat: auth refactor'）",
  "state":     "string (optional) — 枚举：working | idle | done"
}
```

限制：`state` 不接受 `launching` 和 `error`，这两个状态由系统自动管理。

### 返回

```json
{"ok": true}
```

### 实现要点

1. `AgentSession` 新增字段：`var customLabel: String? = nil`
2. `CtrlToolHandler.callSetAgentLabel()` 通过 `AgentSessionManager.session(forClaudeSessionId:)` 找到 session
3. 更新 `customLabel`（和可选的 `state`）
4. 调用 `Task { await EventBus.shared.emit(.agentStatusChanged(...)) }` 推送 SSE

### 错误处理

- `sessionId` 找不到对应 session → `-32603: set_agent_label: session not found`
- `state` 值无效 → `-32602: set_agent_label: invalid state value`

---

## 2. `get_workspace_state`

### 功能

返回指定 Workspace 的完整状态快照，聚合元数据、布局、Agent 列表、端口、PR 状态。

### 参数

```json
{
  "workspaceId": "string (optional) — 省略时取当前活跃 workspace"
}
```

### 返回结构

```json
{
  "workspaceId":   "UUID string",
  "name":          "string",
  "rootDir":       "string",
  "color":         "#RRGGBB",
  "branch":        "string (if git repo)",
  "panes": [
    {
      "id": "UUID",
      "tabId": "UUID",
      "isActive": true,
      "tabIndex": 0,
      "paneIndex": 0,
      "title": "string (optional)",
      "annotation": "string (optional)"
    }
  ],
  "agents": [
    {
      "sessionId":   "claude session ID string",
      "surfaceId":   "UUID string",
      "state":       "working | idle | launching | done | error",
      "customLabel": "string (optional)",
      "model":       "string (optional)",
      "startedAt":   "ISO8601 string"
    }
  ],
  "ports": [":3000", ":8080"],
  "prStatus": {
    "branch":  "string",
    "number":  123,
    "state":   "open | draft | merged | closed",
    "url":     "string"
  }
}
```

`ports`、`prStatus`、`branch` 字段在无数据时省略（不返回 null）。

### 实现要点

- 元数据：`WorkspaceManager.shared.workspace(for:)`
- Panes：复用 `callListPanes()` 的内部逻辑（提取为私有辅助方法，避免重复）
- Agents：`AgentSessionManager.shared.sessions.values.filter { $0.workspaceId == id }`
- 端口/PR：`WorkspaceMetadataStore.shared.metadata[id]`（已有 `WorkspaceMetadata` 类型）
- Git branch：复用 `get_git_status` 的 branch 解析逻辑

---

## 3. `notify`

### 功能

向指定 Workspace 的通知面板发送一条消息，侧边栏角标自动更新。

### 参数

```json
{
  "title":       "string (required)",
  "body":        "string (optional)",
  "workspaceId": "string (optional) — 省略时取当前活跃 workspace"
}
```

### 返回

```json
{"ok": true}
```

### 实现要点

```swift
AgentNotificationStore.shared.insert(AgentNotification(
    id: UUID(), timestamp: Date(),
    workspaceId: resolvedWorkspaceId,
    surfaceId: nil,
    agentDefinitionId: "ctrl-api",
    sessionId: nil,
    type: .info,
    title: title,
    body: body,
    priority: .normal
))
```

`AgentNotificationType.info` 已存在，直接使用。

---

## 4. `open_in_file_browser`

### 功能

在文件浏览器（yazi）中定位到指定路径。若文件浏览器当前未打开则自动打开。

### 参数

```json
{
  "path":        "string (required) — 目标目录或文件路径",
  "workspaceId": "string (optional) — 省略时取当前活跃 workspace"
}
```

### 返回

```json
{"ok": true}
```

### 实现要点

1. 若文件浏览器未打开：`NotificationCenter.default.post(name: .toggleFileBrowser, object: nil)`
2. 等待一个 RunLoop tick（给 yazi surface 时间初始化）
3. `YaziSurfaceStore.shared.cdToDirectory(workspaceId, path: resolvedPath)`

路径解析：支持 `~` 展开（`NSString.expandingTildeInPath`）。

---

## 5. SSE 事件：`agent_status_changed`

### EventBus 新增

```swift
case agentStatusChanged(
    sessionId: String,
    state: String,          // "working" | "idle" | "launching" | "done" | "error"
    workspaceId: UUID,
    customLabel: String?
)
```

### SSE 通知格式

```json
{
  "jsonrpc": "2.0",
  "method": "notifications/agent_status_changed",
  "params": {
    "sessionId":   "...",
    "state":       "working",
    "workspaceId": "...",
    "customLabel": "feat: auth refactor"
  }
}
```

`customLabel` 无值时省略该字段。

### 触发点

- `AgentSessionManager.updateState(_:surfaceId:)` — 任意状态变更
- `AgentSessionManager.processHookEvent()` 中 sessionEnd、notification、stop 分支
- `CtrlToolHandler.callSetAgentLabel()` 完成后

**注意**：`AgentSessionManager` 是 `@MainActor`，EventBus 是 `actor`——通过 `Task { await EventBus.shared.emit(...) }` 跨 actor 调用即可，无需额外同步。

---

## 6. SSE 事件：`workspace_switched`

### EventBus 新增

```swift
case workspaceSwitched(
    workspaceId: UUID,
    previousWorkspaceId: UUID?
)
```

### SSE 通知格式

```json
{
  "jsonrpc": "2.0",
  "method": "notifications/workspace_switched",
  "params": {
    "workspaceId":         "...",
    "previousWorkspaceId": "..."
  }
}
```

`previousWorkspaceId` 无值时省略。

### 触发点与实现

在 `CtrlServer` 启动时注册 `NSWindow.didBecomeKeyNotification` 观察者：

```swift
NotificationCenter.default.addObserver(
    forName: NSWindow.didBecomeKeyNotification,
    object: nil,
    queue: .main
) { [weak self] notification in
    guard let window = notification.object as? NSWindow,
          let newId = WorkspaceManager.shared.workspaceId(for: window),
          newId != self?.lastActiveWorkspaceId
    else { return }
    let prev = self?.lastActiveWorkspaceId
    self?.lastActiveWorkspaceId = newId
    Task { await EventBus.shared.emit(.workspaceSwitched(workspaceId: newId, previousWorkspaceId: prev)) }
}
```

`WorkspaceManager.workspaceId(for window: NSWindow) -> UUID?` 已存在（反向查找 `activeWindows` 字典），直接调用。

---

## 修改文件清单

| 文件 | 改动类型 |
|------|---------|
| `AgentSession.swift` | 新增 `customLabel: String?` 字段 |
| `AgentSessionManager.swift` | `updateState()` 和 hook 分支中 emit SSE |
| `WorkspaceManager.swift` | 无需改动（`workspaceId(for:)` 已存在） |
| `EventBus.swift` | 新增两个 Event case |
| `CtrlServer.swift` | 注册 workspace 切换观察者；格式化新 SSE 事件 |
| `CtrlToolHandler.swift` | 新增 4 个工具实现 + callTool switch 分支 |
| `CtrlServer.handleToolsList()` | 注册 4 个工具的 schema |
| `docs/rules/ctrl-api-rules.md` | SSE 事件表新增两行 |

---

## 工具新增 Checklist（每个工具）

- [ ] `CtrlToolHandler.callTool()` — 添加 `case "tool_name":` 分支
- [ ] `CtrlToolHandler` — 实现 `private func callToolName()` 方法
- [ ] `CtrlServer.handleToolsList()` — 添加工具 schema
- [ ] `docs/rules/ctrl-api-rules.md` — SSE 事件表更新
