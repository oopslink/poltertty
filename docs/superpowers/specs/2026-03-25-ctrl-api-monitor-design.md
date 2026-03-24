# Ctrl API 监控面板设计

**日期**：2026-03-25
**状态**：已批准
**目标**：为 CtrlServer 提供开发调试用的 API 调用监控面板，展示所有端点的调用历史、请求/响应内容、耗时与错误信息

---

## 背景

`CtrlServer` 是 Poltertty 内嵌的 MCP HTTP server，处理来自 Claude Code 的控制调用（`ping`、`new_tab`、`list_panes`、`focus_pane`、`send_text`、`split_pane`）以及 hook 事件接收。目前缺乏可视化手段排查 API 调用问题，需要一个开发调试向的监控面板。

---

## 需求

- 记录所有端点的调用（`/mcp`、`/hook`、`/hooks/prepare-session`、`/health`）
- 展示：调用时间、HTTP 方法、路径、tool name（tools/call 时）、耗时、状态码、request body、response body、错误信息
- 支持按 workspace 过滤
- 位置：底部 Panel，与现有 AgentMonitorPanel 风格一致
- 仅内存存储，重启清空，上限 500 条

---

## 架构

```
CtrlServer.processRequest()
  └── 拦截请求 → RequestContext（开始时间、method、path、body）
       └── sendJSON/sendRPCResult/sendRPCError/sendEmpty
            └── contentProcessed 回调 → 计算耗时 → CtrlAPIStore.shared.append()
                                                        ↓
                                              CtrlAPIMonitorPanel（SwiftUI）
                                                 ↑
                                          CtrlAPIMonitorViewModel（过滤）
```

---

## 数据模型

### CtrlAPIRecord

```swift
struct CtrlAPIRecord: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date        // 请求到达时间
    let method: String         // "POST", "GET", "DELETE"
    let path: String           // "/mcp", "/hook", "/hooks/prepare-session", "/health"
    let toolName: String?      // tools/call 时的 tool name（ping/new_tab 等），其余为 nil
    let requestBody: String?   // 截断至 4096 字节
    let responseBody: String?  // 截断至 4096 字节
    let statusCode: Int        // HTTP 状态码
    let durationMs: Double     // 耗时（毫秒）
    let error: String?         // 若响应为 JSON-RPC error，记录 error.message
    let workspaceId: UUID?     // 从 body 解析（prepare-session/hook 有）
    let surfaceId: UUID?       // 从 body 解析（prepare-session/hook 有）
}
```

### RequestContext

`CtrlServer` 内部使用的临时结构，在 response 发送后构造 `CtrlAPIRecord`：

```swift
struct RequestContext {
    let method: String
    let path: String
    let startTime: Date
    let requestBody: Data?
    let toolName: String?      // handleToolsCall 时解析 params.name 后注入
    let workspaceId: UUID?
    let surfaceId: UUID?
}
```

---

## CtrlAPIStore

```swift
@MainActor
final class CtrlAPIStore: ObservableObject {
    static let shared = CtrlAPIStore()

    @Published private(set) var records: [CtrlAPIRecord] = []
    private let maxRecords = 500

    func append(_ record: CtrlAPIRecord) {
        records.append(record)
        if records.count > maxRecords {
            records.removeFirst(records.count - maxRecords)
        }
    }

    func clear() { records.removeAll() }
}
```

---

## CtrlServer 拦截改造

### 核心改造点

`processRequest()` 入口记录 `RequestContext`，传入所有 response helper：

```swift
private func processRequest(firstLine: String, bodyData: Data, connection: NWConnection) {
    let startTime = Date()
    // 解析 method、path
    let context = RequestContext(method: method, path: path, startTime: startTime, requestBody: bodyData)
    // 路由分发，将 context 传入各 handler
    ...
}
```

所有 response helper 在 `contentProcessed` 回调中记录：

```swift
private func sendJSON(_ connection: NWConnection, status: Int, body: String, context: RequestContext?) {
    // 发送响应...
    connection.send(content: resp, completion: .contentProcessed { _ in
        connection.cancel()
        if let context {
            let record = CtrlAPIRecord(
                id: UUID(),
                timestamp: context.startTime,
                method: context.method,
                path: context.path,
                toolName: context.toolName,
                requestBody: context.requestBody.flatMap { String(data: $0.prefix(4096), encoding: .utf8) },
                responseBody: String(body.prefix(4096)),
                statusCode: status,
                durationMs: Date().timeIntervalSince(context.startTime) * 1000,
                error: Self.extractRPCError(from: body),
                workspaceId: context.workspaceId,
                surfaceId: context.surfaceId
            )
            Task { await MainActor.run { CtrlAPIStore.shared.append(record) } }
        }
    })
}
```

`sendRPCResult` 和 `sendRPCError` 同样接收 `context`，内部调用改造后的 `sendJSON`。

### SSE 特殊处理

`GET /mcp`（SSE 长连接）只记录"连接建立"这一次：在首包 `contentProcessed` 回调中写入一条记录（`responseBody: nil`，`statusCode: 200`），后续 SSE 推送不记录。

### toolName 注入

`handleToolsCall` 解析出 `name` 后，将其注入 `context.toolName`，再传入 response helper。

---

## UI 设计

### 入口

底部 statusbar 添加"Ctrl API"按钮，点击切换面板显示/隐藏。

### 面板布局

```
┌─────────────────────────────────────────────────────┐
│ Ctrl API Monitor   [Workspace ▼]  [Surface ▼] [Clear] │  ← 工具栏
├──────────┬──────┬─────────────────────┬──────┬──────┤
│ 时间     │ 方法 │ 路径/工具            │ 耗时 │ 状态 │  ← 列表头
├──────────┼──────┼─────────────────────┼──────┼──────┤
│ 12:01:03 │ POST │ tools/call · ping   │ 12ms │ 200  │
│ 12:01:02 │ POST │ /hooks/prepare-ses… │  3ms │ 200  │  ← 错误行高亮红色
│ 12:01:01 │ GET  │ /mcp (SSE)          │  1ms │ 200  │
├─────────────────────────────────────────────────────┤
│ Request                │ Response                   │  ← 详情区（点击行展开）
│ {"method":"tools/call"}│ {"paneId":"..."}            │
└─────────────────────────────────────────────────────┘
```

### 列表行

- **路径列**：`/mcp` 的 `tools/call` 显示为 `tools/call · <toolName>`，SSE 显示为 `/mcp (SSE)`，其余显示 path
- **状态列**：HTTP 4xx/5xx 或 JSON-RPC error（`error` 字段非 nil）显示红色
- **耗时**：`< 10ms` 绿色，`10–100ms` 正常色，`> 100ms` 橙色

### 详情区

点击列表行，底部展开详情区（可折叠）：

- 左侧：Request Body（等宽字体，可横向滚动）
- 右侧：Response Body（等宽字体，可横向滚动）
- 宽松格式化 JSON（`JSONSerialization` pretty print）

### 过滤

- Workspace 下拉：过滤含 `workspaceId` 的记录；无 workspaceId 的记录（`/mcp`、`/health`）始终显示
- Surface 下拉：同上，过滤含 `surfaceId` 的记录
- Clear：清空 `CtrlAPIStore`

---

## CtrlAPIMonitorViewModel

```swift
@MainActor
final class CtrlAPIMonitorViewModel: ObservableObject {
    @ObservedObject var store = CtrlAPIStore.shared

    @Published var selectedWorkspaceId: UUID? = nil  // nil = 全部
    @Published var selectedSurfaceId: UUID? = nil
    @Published var selectedRecord: CtrlAPIRecord? = nil

    var filteredRecords: [CtrlAPIRecord] {
        store.records.filter { record in
            if let wsId = selectedWorkspaceId, record.workspaceId != nil, record.workspaceId != wsId { return false }
            if let sfId = selectedSurfaceId, record.surfaceId != nil, record.surfaceId != sfId { return false }
            return true
        }.reversed()  // 最新在上
    }

    var availableWorkspaces: [UUID] { /* 从 store.records 中去重提取 */ }
    var availableSurfaces: [UUID] { /* 同上 */ }
}
```

---

## 文件清单

| 文件 | 操作 |
|------|------|
| `CtrlServer/CtrlAPIRecord.swift` | 新建：`CtrlAPIRecord` 和 `RequestContext` |
| `CtrlServer/CtrlAPIStore.swift` | 新建：`CtrlAPIStore` 单例 |
| `CtrlServer/CtrlAPIMonitorViewModel.swift` | 新建：过滤 ViewModel |
| `CtrlServer/CtrlAPIMonitorPanel.swift` | 新建：SwiftUI 面板 View |
| `CtrlServer/CtrlServer.swift` | 修改：拦截改造（`RequestContext`、`sendJSON`/`sendRPCResult`/`sendRPCError`/`sendEmpty` 加 context 参数） |
| 底部 statusbar 相关文件 | 修改：添加"Ctrl API"按钮入口 |

---

## 不在范围内

- 持久化历史（重启即清空）
- 网络流量统计图表
- 记录导出（JSON/CSV）
- request body 中的敏感信息脱敏

---

## 错误处理

- request body 超过 4096 字节：截断并附注 `[truncated]`
- JSON 解析失败（pretty print）：原样展示
- Store append 从非主线程调用：通过 `Task { await MainActor.run { ... } }` 保证线程安全
