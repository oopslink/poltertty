# Ctrl API 监控面板设计

**日期**：2026-03-25
**状态**：已批准
**目标**：为 CtrlServer 提供开发调试用的 API 调用监控面板，展示所有端点的调用历史、请求/响应内容、耗时与错误信息

---

## 背景

`CtrlServer` 是 Poltertty 内嵌的 MCP HTTP server，处理来自 Claude Code 的控制调用（`ping`、`new_tab`、`list_panes`、`focus_pane`、`send_text`、`split_pane`）以及 hook 事件接收。目前缺乏可视化手段排查 API 调用问题，需要一个开发调试向的监控面板。

---

## 需求

- 记录所有端点的调用（`/mcp`、`/hook`、`/hooks/prepare-session`、`/health`，含 `DELETE /mcp`）
- 展示：调用时间、HTTP 方法、路径、tool name（tools/call 时）、耗时、状态码、request body、response body、错误信息
- 支持按 workspace 和 surface 过滤
- 位置：底部 Panel，点击底部 statusbar 的"Ctrl API"按钮切换显示/隐藏
- 仅内存存储，重启清空，上限 500 条

---

## 架构

```
CtrlServer.processRequest()
  └── 拦截请求 → RequestContext（开始时间、method、path、body）
       └── sendJSON / sendRPCResult / sendRPCError / sendEmpty
            └── contentProcessed 回调 → 构造 CtrlAPIRecord → CtrlAPIStore.shared.append()
                                                                        ↓
                                                             CtrlAPIMonitorPanel（SwiftUI）
                                                                   ↑
                                                         CtrlAPIMonitorViewModel（过滤、订阅）
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
    let requestBody: String?   // 截断至 4096 字节，超出时附注 "[truncated]"
    let responseBody: String?  // 截断至 4096 字节，超出时附注 "[truncated]"
    let statusCode: Int        // HTTP 状态码
    let durationMs: Double     // 耗时（毫秒）
    let error: String?         // 若响应为 JSON-RPC error，记录 error.message；否则为 nil
    // 过滤用：仅 /hooks/prepare-session 能直接提供；/hook 通过 sessionId 查 HookSessionStore 获取
    let workspaceId: UUID?
    let surfaceId: UUID?
}
```

**workspaceId / surfaceId 来源说明：**

| 端点 | 来源 |
|------|------|
| `/hooks/prepare-session` | 直接从 `PrepareRequest` 的 `workspaceId`/`surfaceId`（String）解析为 UUID |
| `/hook` | 从 `HookPayload.sessionId` 查 `HookSessionStore.shared.session(id:)`，取其 `workspaceId`/`surfaceId` |
| `/mcp`、`/health`、`DELETE /mcp` | 无法关联，`workspaceId`/`surfaceId` 均为 nil |

UUID 解析失败时静默设为 nil，不影响记录写入。

### RequestContext

`CtrlServer` 内部使用的不可变上下文，每次请求独立创建一个实例：

```swift
struct RequestContext: Sendable {
    let method: String
    let path: String
    let startTime: Date
    let requestBody: Data?
    let toolName: String?      // 仅 handleToolsCall 路径填充，其他路径为 nil
    let workspaceId: UUID?
    let surfaceId: UUID?
}
```

`RequestContext` 是值类型（struct），**不在创建后修改**。`handleToolsCall` 在 Task 内部、已知 `toolName` 之后，用完整参数构造新的 `RequestContext` 再传入 response helper（详见下方「toolName 注入」）。

---

## CtrlAPIStore

```swift
@MainActor
final class CtrlAPIStore: ObservableObject {
    static let shared = CtrlAPIStore()
    private init() {}

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

`processRequest()` 入口构造初始 `RequestContext`（不含 toolName），传入各 handler。各 handler 在调用 response helper 时传入最终的 context（可能含 toolName）：

```swift
private func processRequest(firstLine: String, bodyData: Data, connection: NWConnection) {
    let startTime = Date()
    // 解析 method、path
    // 对 /hook 和 /hooks/prepare-session 解析 workspaceId/surfaceId
    let context = RequestContext(
        method: method, path: path, startTime: startTime,
        requestBody: bodyData, toolName: nil,
        workspaceId: resolvedWorkspaceId, surfaceId: resolvedSurfaceId
    )
    // 路由分发，将 context 传入各 handler
}
```

所有 response helper 加 `context: RequestContext?` 参数，在 `contentProcessed` 回调中记录：

```swift
private func sendJSON(_ connection: NWConnection, status: Int, body: String, context: RequestContext?) {
    // 构造并发送响应...
    connection.send(content: resp, completion: .contentProcessed { _ in
        connection.cancel()
        guard let context else { return }
        let truncatedReq = context.requestBody.flatMap {
            let s = String(data: $0, encoding: .utf8) ?? ""
            return s.count > 4096 ? String(s.prefix(4096)) + " [truncated]" : s
        }
        let truncatedResp: String? = {
            guard !body.isEmpty else { return nil }
            return body.count > 4096 ? String(body.prefix(4096)) + " [truncated]" : body
        }()
        let record = CtrlAPIRecord(
            id: UUID(),
            timestamp: context.startTime,
            method: context.method,
            path: context.path,
            toolName: context.toolName,
            requestBody: truncatedReq,
            responseBody: truncatedResp,
            statusCode: status,
            durationMs: Date().timeIntervalSince(context.startTime) * 1000,
            error: Self.extractRPCError(from: body),
            workspaceId: context.workspaceId,
            surfaceId: context.surfaceId
        )
        Task { await MainActor.run { CtrlAPIStore.shared.append(record) } }
    })
}
```

`sendRPCResult`、`sendRPCError` 同样接收 `context`，内部调用改造后的 `sendJSON`。

### toolName 注入

`handleToolsCall` 是异步路径（在 Task 内执行），在已知 toolName 后构造带 toolName 的新 context 副本，再传入 response helper：

```swift
private func handleToolsCall(connection: NWConnection, id: Any?, params: [String: Any]?, context: RequestContext) {
    guard let name = params?["name"] as? String else {
        sendRPCError(connection, id: id, code: -32602, message: "Invalid params: missing name", context: context)
        return
    }
    let arguments = params?["arguments"] as? [String: Any] ?? [:]
    // 构造含 toolName 的 context 副本
    let toolContext = RequestContext(
        method: context.method, path: context.path, startTime: context.startTime,
        requestBody: context.requestBody, toolName: name,
        workspaceId: context.workspaceId, surfaceId: context.surfaceId
    )
    let handler = CtrlToolHandler(port: self.port)
    Task {
        do {
            let resultText = try await handler.callTool(name: name, arguments: arguments)
            let content: [[String: Any]] = [["type": "text", "text": resultText]]
            self.sendRPCResult(connection, id: id, result: ["content": content], context: toolContext)
        } catch let err as CtrlToolHandler.RPCError {
            self.sendRPCError(connection, id: id, code: err.code, message: err.message, context: toolContext)
        } catch {
            self.sendRPCError(connection, id: id, code: -32603, message: error.localizedDescription, context: toolContext)
        }
    }
}
```

### SSE 特殊处理

`GET /mcp`（SSE 长连接）只记录"连接建立"这一次：在首包 `contentProcessed` 回调中写入一条记录（`statusCode: 200`，`responseBody: nil`，`toolName: nil`），后续 SSE 推送帧不记录。

### notifications/\* 处理

`POST /mcp` 的 notifications 消息（method 以 `notifications/` 开头）返回 202 Accepted（无 body）。调用 `sendEmpty` 时同样传入 context，记录为：`statusCode: 202`，`responseBody: nil`。

### DELETE /mcp 处理

返回 200 `{}`，与普通路由一样传入 context 记录。

---

## UI 设计

### 入口

`BottomStatusBarView.swift` 右侧添加"Ctrl API"按钮，点击切换面板显示/隐藏（通过 `@State var showCtrlAPIMonitor: Bool` 控制）。

### 面板布局

```
┌─────────────────────────────────────────────────────────┐
│ Ctrl API Monitor   [Workspace ▼]  [Surface ▼]  [Clear]  │  ← 工具栏
├──────────┬──────┬──────────────────────┬──────┬─────────┤
│ 时间     │ 方法 │ 路径/工具             │ 耗时 │ 状态    │  ← 列表头
├──────────┼──────┼──────────────────────┼──────┼─────────┤
│ 12:01:03 │ POST │ tools/call · ping    │ 12ms │ 200     │
│ 12:01:02 │ POST │ /hooks/prepare-ses…  │  3ms │ 200     │
│ 12:01:01 │ GET  │ /mcp (SSE)           │  1ms │ 200     │  ← 错误行高亮红色
├─────────────────────────────────────────────────────────┤
│ Request                  │ Response                     │  ← 详情区（点击行展开）
│ {"method":"tools/call"}  │ {"paneId":"..."}             │
└─────────────────────────────────────────────────────────┘
```

### 列表行

- **路径列**：
  - `tools/call` → `tools/call · <toolName>`
  - `GET /mcp` → `/mcp (SSE)`
  - `notifications/*` → `/mcp notifications`
  - 其余 → 显示原始 path
- **状态列**：HTTP 4xx/5xx 或 `error` 字段非 nil 时显示红色
- **耗时色**：`< 10ms` 绿色，`10–100ms` 正常色，`> 100ms` 橙色

### 详情区

点击列表行，底部展开详情区（再次点击同一行收起）：

- 左侧：Request Body（等宽字体，可横向滚动）
- 右侧：Response Body（等宽字体，可横向滚动）
- 尝试 pretty-print JSON（`JSONSerialization`），解析失败则原样展示

### 过滤行为

- **Workspace 下拉**（选项从 `workspaceId` 非 nil 的记录中动态提取）：
  - 选中某 workspace → 仅展示 `workspaceId == 选中值` 的记录 **以及** `workspaceId == nil` 的记录（`/mcp`、`/health` 等无 workspace 上下文，始终可见，便于调试全局端点）
  - 选"全部"（nil）→ 展示所有
- **Surface 下拉**：逻辑同上，针对 `surfaceId`
- **Clear**：清空 `CtrlAPIStore`，同时重置 `selectedRecord`

---

## CtrlAPIMonitorViewModel

ViewModel 直接订阅 `CtrlAPIStore.$records`，驱动 SwiftUI 更新：

```swift
@MainActor
final class CtrlAPIMonitorViewModel: ObservableObject {
    @Published private(set) var records: [CtrlAPIRecord] = []
    @Published var selectedWorkspaceId: UUID? = nil  // nil = 全部
    @Published var selectedSurfaceId: UUID? = nil
    @Published var selectedRecord: CtrlAPIRecord? = nil

    private var cancellable: AnyCancellable?

    init() {
        cancellable = CtrlAPIStore.shared.$records
            .receive(on: RunLoop.main)
            .assign(to: \.records, on: self)
    }

    var filteredRecords: [CtrlAPIRecord] {
        records.filter { record in
            if let wsId = selectedWorkspaceId {
                // workspaceId 为 nil 的记录（/mcp、/health 等）始终通过
                if let recWs = record.workspaceId, recWs != wsId { return false }
            }
            if let sfId = selectedSurfaceId {
                if let recSf = record.surfaceId, recSf != sfId { return false }
            }
            return true
        }.reversed()  // 最新在上
    }

    var availableWorkspaceIds: [UUID] {
        Array(Set(records.compactMap(\.workspaceId))).sorted { $0.uuidString < $1.uuidString }
    }
    var availableSurfaceIds: [UUID] {
        Array(Set(records.compactMap(\.surfaceId))).sorted { $0.uuidString < $1.uuidString }
    }
}
```

---

## 文件清单

| 文件 | 操作 |
|------|------|
| `Features/Agent/CtrlServer/CtrlAPIRecord.swift` | 新建：`CtrlAPIRecord`、`RequestContext` |
| `Features/Agent/CtrlServer/CtrlAPIStore.swift` | 新建：`CtrlAPIStore` 单例 |
| `Features/Agent/CtrlServer/CtrlAPIMonitorViewModel.swift` | 新建：过滤 ViewModel（订阅 Store） |
| `Features/Agent/CtrlServer/CtrlAPIMonitorPanel.swift` | 新建：SwiftUI 面板 View |
| `Features/Agent/CtrlServer/CtrlServer.swift` | 修改：拦截改造（RequestContext 构造、sendJSON/sendRPCResult/sendRPCError/sendEmpty 加 context 参数、handleToolsCall toolName 注入、workspaceId/surfaceId 从 prepare-session/hook 解析） |
| `Features/Workspace/BottomStatusBarView.swift` | 修改：添加"Ctrl API"按钮 + 面板切换状态 |

---

## 不在范围内

- 持久化历史（重启即清空）
- 网络流量统计图表
- 记录导出（JSON/CSV）
- request body 中的敏感信息脱敏

---

## 错误处理

- request/response body 超过 4096 字节：截断并附注 `[truncated]`
- JSON pretty-print 失败：原样展示
- Store.append 从非主线程调用：通过 `Task { await MainActor.run { ... } }` 保证线程安全
- workspaceId/surfaceId UUID 解析失败：静默设为 nil，记录照常写入
- HookSessionStore 查不到 sessionId：workspaceId/surfaceId 设为 nil
