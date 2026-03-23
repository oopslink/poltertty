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
    let id: UUID          // SurfaceView.id（pane 唯一标识）
    let tabId: UUID       // 所属 tab UUID（来自 TabBarViewModel）
    let workspaceId: UUID // 所属 workspace
    let isActive: Bool    // 是否为当前激活 pane（keyWindow 且为 focusedSurface）
    let title: String?    // tab 标题（可选）
}
```

**注意**：`addNewTab()` 改造为直接返回新创建 `SurfaceView` 实例的 `.id`（`UUID`），而非依赖 `tabBarViewModel.activeTabId`，避免 `@Published` 更新时序竞态。

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

    // 内部：每个订阅者持有一个 Continuation
    private var subscribers: [UUID: AsyncStream<Event>.Continuation] = [:]

    func subscribe() -> (subscriberId: UUID, AsyncStream<Event>) {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Event>.makeStream()
        // onTermination 作为双重保障：Task 取消时自动 unsubscribe
        // EventBus 是单例，self 不会提前释放，此处强捕获安全；
        // unsubscribe 被重复调用是安全的（removeValue + finish 均幂等）
        continuation.onTermination = { [self, id] _ in
            Task { await self.unsubscribe(id) }
        }
        subscribers[id] = continuation
        return (id, stream)
    }

    func unsubscribe(_ id: UUID) {
        subscribers[id]?.finish()
        subscribers.removeValue(forKey: id)
    }

    func emit(_ event: Event) {
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }
}
```

**接入点：**
- `CtrlServer.handleHook()` → `EventBus.shared.emit(.hook(payload))`
- `TerminalController.addNewTab()` → `EventBus.shared.emit(.tabCreated(...))`
- `TerminalController.newSplit()` → `EventBus.shared.emit(.paneCreated(...))`
- tab/pane 关闭、焦点切换时 → 对应 emit

## SSE 改造

`CtrlServer.handleSSE()` 建立连接后，启动一个专用 `Task` 处理事件循环，并与 `stateUpdateHandler` 协作管理生命周期：

```swift
func handleSSE(connection: NWConnection) {
    // 1. 订阅 EventBus
    let (subscriberId, stream) = await EventBus.shared.subscribe()

    // 2. 启动事件循环 Task，保存引用以便取消
    let task = Task {
        for await event in stream {
            let data = formatSSENotification(event)
            connection.send(content: data, ...)
        }
    }

    // 3. 连接断开时：取消 Task + unsubscribe（触发 stream finish）
    connection.stateUpdateHandler = { state in
        switch state {
        case .failed, .cancelled:
            task.cancel()
            Task { await EventBus.shared.unsubscribe(subscriberId) }
        default: break
        }
    }
}
```

`onTermination` 回调作为双重保障：无论是 `unsubscribe` 直接调用还是消费者侧 Task 取消，都能正确清理 `subscribers` 字典，避免 continuation 泄漏。

心跳（30s `: ping\n\n`）保持现有 `DispatchSourceTimer` 逻辑不变。

SSE notification 格式：

```
data: {"jsonrpc":"2.0","method":"notifications/pane_created","params":{"paneId":"...","tabId":"...","workspaceId":"..."}}

```

## handleToolsCall 改造

现有 `handleToolsCall()` 采用 fire-and-forget 模式（先响应 200，再异步执行 UI 副作用）。为支持工具返回实际结果，需要改造为 **async 工具路径**：

```swift
// 区分同步工具（ping）和 async 工具（其余）
// 所有工具均走 async 路径（ping 也需 MainActor.run 读取 workspace 信息）
{
    // async 路径：在 CtrlServer queue 上用 Task 桥接
    Task {
        do {
            let result = try await handler.callTool(name: tool, arguments: args)
            respondJSON(result)
        } catch {
            respondError(-32603, message: error.localizedDescription)
        }
    }
}
```

`CtrlToolHandler.callTool()` 改为 `async throws`，内部用 `withCheckedThrowingContinuation` 切换到 `@MainActor` 执行 UI 操作后 resume。

**注意**：`NWConnection` 在 continuation suspend 期间保持存活（由 `sseConnections` 或局部引用持有），无需额外生命周期管理。

## new_tab 改造

```swift
// CtrlToolHandler.callTool("new_tab")
let paneId: UUID = try await withCheckedThrowingContinuation { cont in
    Task { @MainActor in
        guard let tc = resolveTerminalController(arguments) else {
            cont.resume(throwing: MCPError.noWindow); return
        }
        // addNewTab() 返回新创建的 SurfaceView.id
        let id = tc.addNewTab()
        cont.resume(returning: id)
    }
}
// 成功响应：{"paneId": "<uuid>"}
// 失败响应：JSON-RPC error -32603
```

## workspaceId 发现

`ping` 工具需要在 `@MainActor` 上读取 workspace 信息（访问 `NSApp.keyWindow` 需主线程），改造为 async 工具：

```swift
// 在 @MainActor 上组装 workspaces 列表
let workspaces: [[String: Any]] = await MainActor.run {
    WorkspaceManager.shared.allWorkspaceIds().map { id in
        let isActive = WorkspaceManager.shared.windowForWorkspace(id)?.isKeyWindow == true
        return ["id": id.uuidString, "isActive": isActive]
    }
}
```

响应格式：

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

## 新 MCP 工具

### `list_panes`

| 字段 | 类型 | 说明 |
|------|------|------|
| `workspaceId` | string (optional) | 不传则返回所有 workspace 的 panes |

响应：`[{ id, tabId, workspaceId, isActive, title }]`

**实现要点**：`TerminalController.listPanes()` 需同时枚举：
- `tabSurfaceTrees`（非活跃 tab）
- 当前活跃 tab 的 `surfaceTree`（未 flush 到 `tabSurfaceTrees`）

跨 workspace 时遍历 `WorkspaceManager.shared.activeWindows`；若某 window 已释放则静默跳过（返回部分结果，不报错）。整个 `listPanes()` 需在 `@MainActor` 上调用（与其他 UI 操作一致，避免 data race）。

### `focus_pane`

| 字段 | 类型 | 说明 |
|------|------|------|
| `paneId` | string (required) | 目标 pane UUID |

响应：`{"ok": true}`，找不到 pane 返回 -32603。

实现：先调用 `tc.switchToTab(containing: paneId)` 切换到对应 tab，再调用 `tc.focusSurface(paneId)` 将焦点移至具体 pane（使其成为 key responder）。两步都需要成功，否则返回 -32603。

### `send_text`

| 字段 | 类型 | 说明 |
|------|------|------|
| `text` | string (required) | 要写入的文本 |
| `paneId` | string (optional) | 目标 pane UUID，不传则写 keyWindow 的 focusedSurface |

响应：`{"ok": true}`。

- 有 `paneId`：调用 `tc.writeToSurface(text:surfaceId:)`，需先定位持有该 surface 的 `TerminalController`（跨 workspace 遍历）
- 无 `paneId`：取 keyWindow 对应的 `TerminalController.focusedSurface`

### `split_pane`

| 字段 | 类型 | 说明 |
|------|------|------|
| `paneId` | string (required) | 参照 pane UUID |
| `direction` | "left"\|"right"\|"up"\|"down" (required) | 分屏方向 |

响应：`{"newPaneId": "<uuid>"}`。

**注意**：`newSplit(at:direction:)` 只在当前活跃 tab 的 `surfaceTree` 中查找目标 pane。实现时需先调用 `switchToTab(containing: paneId)` 确保目标 tab 激活，再执行 split。返回新 `SurfaceView.id`；找不到 pane 或分屏失败返回 -32603。

## 变更文件清单

| 文件 | 操作 |
|------|------|
| `CtrlServer/EventBus.swift` | 新建 |
| `CtrlServer/CtrlServer.swift` | 修改：SSE 接入 EventBus + Task 生命周期，handleHook emit，handleToolsCall 支持 async 路径 |
| `CtrlServer/CtrlToolHandler.swift` | 修改：callTool 改为 async throws，new_tab 改造，新增 4 个工具，ping 改为 async 附带 workspaces |
| `Features/Terminal/TerminalController.swift` | 修改：addNewTab 返回 SurfaceView.id，新增 listPanes()，focusSurface()，接入 EventBus |
| `Features/Terminal/BaseTerminalController.swift` | 修改：newSplit 接入 EventBus |
| `Features/Workspace/WorkspaceManager.swift` | 修改：新增 allWorkspaceIds() 方法 |
| `todos/agent-ctrl-api.md` | 修改：关闭已完成 TODO |
