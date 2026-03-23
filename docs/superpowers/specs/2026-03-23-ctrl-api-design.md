# Ctrl API 完善设计

**日期**: 2026-03-23
**分支**: feature/ctrl-api
**关联 TODO**: todos/agent-ctrl-api.md

## 背景

`CtrlServer` 的基础已在 #54 落地（HTTP server + MCP ping/new_tab）。本文档描述后续四项功能的设计：

1. `new_tab` 反馈实际结果
2. 更多控制工具（`send_text`、`list_panes`、`focus_pane`、`split_pane`）
3. MCP session 管理（SSE server-initiated messages）
4. `workspaceId` 发现（ping 附带所有 workspace UUID）

## 方案选择

采用 **方案 A：`CheckedContinuation` + `AsyncStream` 事件总线**。

- `new_tab` 及所有新工具：用 `withCheckedThrowingContinuation` 桥接 CtrlServer 线程与 `@MainActor`，等待执行结果后再发送 HTTP 响应
- SSE 推送：引入 `EventBus` actor，hook 事件和 pane 状态变更统一流经此总线；SSE 连接订阅 `AsyncStream<Event>`
- Pane 标识：直接使用现有 `SurfaceView.id: UUID`

## 数据模型

### PaneInfo

```swift
struct PaneInfo {
    let id: UUID          // SurfaceView.id
    let tabId: UUID       // 所属 tab UUID（来自 TabBarViewModel）
    let workspaceId: UUID // 所属 workspace
    let isActive: Bool    // 是否为当前激活 pane
    let title: String?    // tab 标题（可选）
}
```

`TerminalController` 新增 `listPanes() -> [PaneInfo]`，遍历 `tabSurfaceTrees` 组装结果。
`addNewTab()` 改造为返回新 surface 的 `UUID`。

## EventBus

新建 `EventBus.swift`：

```swift
actor EventBus {
    static let shared = EventBus()

    enum Event {
        case hook(HookPayload)
        case paneCreated(paneId: UUID, tabId: UUID, workspaceId: UUID)
        case paneClosed(paneId: UUID)
        case paneFocused(paneId: UUID)
        case tabCreated(tabId: UUID, workspaceId: UUID)
        case tabClosed(tabId: UUID)
    }

    func subscribe() -> (subscriberId: UUID, AsyncStream<Event>)
    func unsubscribe(_ id: UUID)
    func emit(_ event: Event)
}
```

**接入点：**
- `CtrlServer.handleHook()` → `EventBus.shared.emit(.hook(payload))`
- `TerminalController.addNewTab()` → `EventBus.shared.emit(.tabCreated(...))`
- `TerminalController.newSplit()` → `EventBus.shared.emit(.paneCreated(...))`
- tab/pane 关闭、焦点切换时 → 对应 emit

## SSE 改造

`CtrlServer.handleSSE()` 建立连接后：

1. 调用 `await EventBus.shared.subscribe()` 获取 `(subscriberId, stream)`
2. 在 `Task` 中循环 `for await event in stream`，格式化为 JSON-RPC notification 写入 socket：

```
data: {"jsonrpc":"2.0","method":"notifications/pane_created","params":{"paneId":"...","tabId":"...","workspaceId":"..."}}

```

3. 连接关闭时调用 `await EventBus.shared.unsubscribe(subscriberId)`

心跳（30s `: ping\n\n`）保持不变。

## new_tab 改造

```swift
// CtrlToolHandler 中
let paneId: UUID = try await withCheckedThrowingContinuation { cont in
    Task { @MainActor in
        guard let tc = resolveTerminalController(arguments) else {
            cont.resume(throwing: MCPError.noWindow); return
        }
        let id = tc.addNewTab()  // 返回新 surface UUID
        cont.resume(returning: id)
    }
}
// 成功响应：{"paneId": "<uuid>"}
// 失败响应：JSON-RPC error -32603
```

## workspaceId 发现

`ping` 响应扩展为：

```json
{
  "app": "Poltertty",
  "version": "1.0",
  "workspaces": [
    { "id": "<uuid>", "isActive": true },
    { "id": "<uuid>", "isActive": false }
  ]
}
```

数据来源：`WorkspaceManager.shared`，`isActive` 标记 keyWindow 对应的 workspace。

## 新 MCP 工具

### `list_panes`

| 字段 | 类型 | 说明 |
|------|------|------|
| `workspaceId` | string (optional) | 不传则返回所有 workspace 的 panes |

响应：`[{ id, tabId, workspaceId, isActive, title }]`

### `focus_pane`

| 字段 | 类型 | 说明 |
|------|------|------|
| `paneId` | string (required) | 目标 pane UUID |

响应：`{"ok": true}`，找不到 pane 返回 -32603。

调用 `tc.switchToTab(containing: paneId)`。

### `send_text`

| 字段 | 类型 | 说明 |
|------|------|------|
| `text` | string (required) | 要写入的文本 |
| `paneId` | string (optional) | 目标 pane UUID，不传则写当前激活 pane |

响应：`{"ok": true}`。调用 `tc.writeToSurface(text:surfaceId:)` 或向 `focusedSurface` 写入。

### `split_pane`

| 字段 | 类型 | 说明 |
|------|------|------|
| `paneId` | string (required) | 参照 pane UUID |
| `direction` | "left"\|"right"\|"up"\|"down" (required) | 分屏方向 |

响应：`{"newPaneId": "<uuid>"}`。调用 `tc.newSplit(at: targetView, direction: dir)`，返回新 SurfaceView UUID。找不到 pane 或分屏失败返回 -32603。

## 变更文件清单

| 文件 | 操作 |
|------|------|
| `CtrlServer/EventBus.swift` | 新建 |
| `CtrlServer/CtrlServer.swift` | 修改：SSE 接入 EventBus，handleHook emit |
| `CtrlServer/CtrlToolHandler.swift` | 修改：new_tab 改造，新增 4 个工具，ping 附带 workspaces |
| `Features/Terminal/TerminalController.swift` | 修改：addNewTab 返回 UUID，新增 listPanes()，接入 EventBus |
| `Features/Terminal/BaseTerminalController.swift` | 修改：newSplit 接入 EventBus |
| `todos/agent-ctrl-api.md` | 修改：关闭已完成 TODO |
