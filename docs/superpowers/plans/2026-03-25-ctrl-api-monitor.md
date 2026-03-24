# Ctrl API 监控面板 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 CtrlServer 添加 API 调用监控面板，记录所有端点调用（含时间、request/response、耗时、错误），在底部 Panel 展示，支持按 workspace/surface 过滤。

**Architecture:** 在 `CtrlServer.processRequest()` 入口构造 `RequestContext`，所有 response helper 在 `contentProcessed` 回调中构造 `CtrlAPIRecord` 写入全局 `CtrlAPIStore`。SwiftUI `CtrlAPIMonitorPanel` 通过 `CtrlAPIMonitorViewModel`（订阅 `CtrlAPIStore.$records`）展示列表和详情，入口在 `BottomStatusBarView` 右侧按钮。

**Tech Stack:** Swift 5.9, SwiftUI, Combine, `@MainActor`, NWConnection

---

## 文件结构

| 文件 | 操作 | 职责 |
|------|------|------|
| `macos/Sources/Features/Agent/CtrlServer/CtrlAPIRecord.swift` | 新建 | `CtrlAPIRecord` 数据模型 + `RequestContext` |
| `macos/Sources/Features/Agent/CtrlServer/CtrlAPIStore.swift` | 新建 | `@MainActor` 全局 Store 单例 |
| `macos/Sources/Features/Agent/CtrlServer/CtrlAPIMonitorViewModel.swift` | 新建 | 过滤逻辑，订阅 Store |
| `macos/Sources/Features/Agent/CtrlServer/CtrlAPIMonitorPanel.swift` | 新建 | SwiftUI 面板 View |
| `macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift` | 修改 | 拦截改造：RequestContext 注入 + response helper 改造 |
| `macos/Sources/Features/Workspace/BottomStatusBarView.swift` | 修改 | 添加"Ctrl API"按钮和面板显示逻辑 |

---

### Task 1：CtrlAPIRecord + RequestContext 数据模型

**Files:**
- Create: `macos/Sources/Features/Agent/CtrlServer/CtrlAPIRecord.swift`

- [ ] **Step 1: 新建文件，写入数据模型**

```swift
// macos/Sources/Features/Agent/CtrlServer/CtrlAPIRecord.swift
import Foundation

struct CtrlAPIRecord: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let method: String
    let path: String
    let toolName: String?
    let requestBody: String?
    let responseBody: String?
    let statusCode: Int
    let durationMs: Double
    let error: String?
    let workspaceId: UUID?
    let surfaceId: UUID?
}

struct RequestContext: Sendable {
    let method: String
    let path: String
    let startTime: Date
    let requestBody: Data?
    let toolName: String?
    let workspaceId: UUID?
    let surfaceId: UUID?
}
```

- [ ] **Step 2: 构建验证**
```bash
cd /path/to/worktree && make dev 2>&1 | tail -20
```
Expected: 无编译错误

- [ ] **Step 3: Commit**
```bash
git add macos/Sources/Features/Agent/CtrlServer/CtrlAPIRecord.swift
git commit -m "feat(ctrl-api-monitor): add CtrlAPIRecord and RequestContext models"
```

---

### Task 2：CtrlAPIStore

**Files:**
- Create: `macos/Sources/Features/Agent/CtrlServer/CtrlAPIStore.swift`

- [ ] **Step 1: 新建文件**

```swift
// macos/Sources/Features/Agent/CtrlServer/CtrlAPIStore.swift
import Foundation
import Combine

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

    func clear() {
        records.removeAll()
    }
}
```

- [ ] **Step 2: 构建验证**
```bash
make dev 2>&1 | tail -20
```

- [ ] **Step 3: Commit**
```bash
git add macos/Sources/Features/Agent/CtrlServer/CtrlAPIStore.swift
git commit -m "feat(ctrl-api-monitor): add CtrlAPIStore"
```

---

### Task 3：CtrlServer 拦截改造

**Files:**
- Modify: `macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift`

改造要点：

1. `processRequest()` 入口解析 method/path，构造 `RequestContext`（含 workspaceId/surfaceId 解析逻辑）
2. `sendJSON()`、`sendRPCResult()`、`sendRPCError()`、`sendEmpty()` 均加 `context: RequestContext?` 参数
3. `contentProcessed` 回调中构造 `CtrlAPIRecord` 并调用 `CtrlAPIStore.shared.append()`
4. `handleToolsCall` 创建含 toolName 的新 context 副本后传入 response helper
5. SSE (`handleSSE`) 只记录连接建立一次
6. 新增 `extractRPCError(from:)` 静态方法从 response body 提取 JSON-RPC error message

workspaceId/surfaceId 解析：
- `/hooks/prepare-session`：直接从 `PrepareRequest` 字段（String）转 UUID
- `/hook`：从 `HookPayload.sessionId` 调用 `await MainActor.run { HookSessionStore.shared.get(sessionId) }` 获取 workspaceId/surfaceId
  - 注意：`HookSessionStore` 是 `@MainActor`，在 `contentProcessed` 回调（非主线程）中需切换
  - 实际处理：在 `handleHook` 入口（queue 线程）解析好放入 context，再传入 `sendJSON`

- [ ] **Step 1: 改造 processRequest — 解析 method/path/context**

在 `processRequest` 签名不变的情况下，在方法开头添加 context 构造逻辑：

```swift
private func processRequest(firstLine: String, bodyData: Data, connection: NWConnection) {
    Self.logger.info("CtrlServer: \(firstLine)")

    let startTime = Date()
    let parts = firstLine.components(separatedBy: " ")
    let method = parts.count > 0 ? parts[0] : "UNKNOWN"
    let rawPath = parts.count > 1 ? parts[1] : "/"
    // 去掉 query string
    let path = rawPath.components(separatedBy: "?").first ?? rawPath

    let baseContext = RequestContext(
        method: method, path: path, startTime: startTime,
        requestBody: bodyData, toolName: nil,
        workspaceId: nil, surfaceId: nil
    )

    // --- health ---
    if method == "GET" && path.contains("/health") {
        sendJSON(connection, status: 200, body: "{}", context: baseContext); return
    }
    // --- hook routes ---
    if method == "POST" && path.contains("/hooks/prepare-session") {
        handlePrepareSession(bodyData: bodyData, connection: connection, context: baseContext); return
    }
    if method == "POST" && path.contains("/hook") {
        handleHook(bodyData: bodyData, connection: connection, context: baseContext); return
    }
    // --- MCP routes ---
    if method == "GET" && path.contains("/mcp") {
        handleSSE(connection: connection, context: baseContext); return
    }
    if method == "DELETE" && path.contains("/mcp") {
        sendJSON(connection, status: 200, body: "{}", context: baseContext); return
    }
    if method == "POST" && path.contains("/mcp") {
        handleMCP(bodyData: bodyData, connection: connection, context: baseContext); return
    }
    sendJSON(connection, status: 404, body: #"{"error":"not found"}"#, context: baseContext)
}
```

- [ ] **Step 2: 改造 sendJSON — 加 context 参数，在 contentProcessed 中写 Store**

```swift
private func sendJSON(_ connection: NWConnection, status: Int, body: String, context: RequestContext? = nil) {
    let bodyData = body.data(using: .utf8) ?? Data()
    let statusText: String
    switch status {
    case 200: statusText = "OK"
    case 400: statusText = "Bad Request"
    case 404: statusText = "Not Found"
    case 413: statusText = "Content Too Large"
    default:  statusText = "Error"
    }
    let header = "HTTP/1.1 \(status) \(statusText)\r\nContent-Length: \(bodyData.count)\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n"
    var resp = header.data(using: .utf8)!
    resp.append(bodyData)
    connection.send(content: resp, completion: .contentProcessed { _ in
        connection.cancel()
        if let ctx = context {
            let truncReq = ctx.requestBody.flatMap {
                let s = String(data: $0, encoding: .utf8) ?? ""
                return s.count > 4096 ? String(s.prefix(4096)) + " [truncated]" : s
            }
            let truncResp: String? = body.isEmpty ? nil : (body.count > 4096 ? String(body.prefix(4096)) + " [truncated]" : body)
            let record = CtrlAPIRecord(
                id: UUID(),
                timestamp: ctx.startTime,
                method: ctx.method,
                path: ctx.path,
                toolName: ctx.toolName,
                requestBody: truncReq,
                responseBody: truncResp,
                statusCode: status,
                durationMs: Date().timeIntervalSince(ctx.startTime) * 1000,
                error: Self.extractRPCError(from: body),
                workspaceId: ctx.workspaceId,
                surfaceId: ctx.surfaceId
            )
            Task { await MainActor.run { CtrlAPIStore.shared.append(record) } }
        }
    })
}

private static func extractRPCError(from body: String) -> String? {
    guard let data = body.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let error = obj["error"] as? [String: Any],
          let msg = error["message"] as? String else { return nil }
    return msg
}
```

- [ ] **Step 3: 改造 sendEmpty — 加 context 参数**

```swift
private func sendEmpty(_ connection: NWConnection, status: Int, context: RequestContext? = nil) {
    let statusText: String
    switch status {
    case 202: statusText = "Accepted"
    default:  statusText = "No Content"
    }
    let header = "HTTP/1.1 \(status) \(statusText)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    let data = header.data(using: .utf8)!
    connection.send(content: data, completion: .contentProcessed { _ in
        connection.cancel()
        if let ctx = context {
            let record = CtrlAPIRecord(
                id: UUID(), timestamp: ctx.startTime,
                method: ctx.method, path: ctx.path, toolName: ctx.toolName,
                requestBody: ctx.requestBody.flatMap { String(data: $0.prefix(4096), encoding: .utf8) },
                responseBody: nil,
                statusCode: status,
                durationMs: Date().timeIntervalSince(ctx.startTime) * 1000,
                error: nil,
                workspaceId: ctx.workspaceId, surfaceId: ctx.surfaceId
            )
            Task { await MainActor.run { CtrlAPIStore.shared.append(record) } }
        }
    })
}
```

- [ ] **Step 4: 改造 sendRPCResult/sendRPCError — 透传 context**

```swift
private func sendRPCResult(_ connection: NWConnection, id: Any?, result: [String: Any], context: RequestContext? = nil) {
    var obj: [String: Any] = ["jsonrpc": "2.0", "result": result]
    if let id { obj["id"] = id }
    guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
    sendJSON(connection, status: 200, body: String(data: data, encoding: .utf8) ?? "{}", context: context)
}

private func sendRPCError(_ connection: NWConnection, id: Any?, code: Int, message: String, context: RequestContext? = nil) {
    var obj: [String: Any] = [
        "jsonrpc": "2.0",
        "error": ["code": code, "message": message]
    ]
    if let id { obj["id"] = id }
    guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
    sendJSON(connection, status: 200, body: String(data: data, encoding: .utf8) ?? "{}", context: context)
}
```

- [ ] **Step 5: 改造 handlePrepareSession — 解析 workspaceId/surfaceId，传入 context**

在 `handlePrepareSession` 中 decode `PrepareRequest` 后，构造含 workspaceId/surfaceId 的 context，传入 `sendJSON`：

```swift
private func handlePrepareSession(bodyData: Data, connection: NWConnection, context: RequestContext) {
    guard let req = try? decoder.decode(PrepareRequest.self, from: bodyData) else {
        sendJSON(connection, status: 400, body: #"{"error":"invalid json"}"#, context: context)
        return
    }
    let wsId = UUID(uuidString: req.workspaceId)
    let sfId = UUID(uuidString: req.surfaceId)
    let ctx = RequestContext(
        method: context.method, path: context.path, startTime: context.startTime,
        requestBody: context.requestBody, toolName: nil,
        workspaceId: wsId, surfaceId: sfId
    )
    // ... 原有逻辑不变，最后 sendJSON 改为传入 ctx ...
    // Task { @MainActor in ... self.sendJSON(connection, status: 200, body: responseBody, context: ctx) }
}
```

- [ ] **Step 6: 改造 handleHook — 解析 sessionId → workspaceId/surfaceId**

在 decode 成功后，通过 `HookSessionStore.shared.get(sessionId)` 获取 workspace/surface（需在 `@MainActor` Task 内）：

```swift
private func handleHook(bodyData: Data, connection: NWConnection, context: RequestContext) {
    guard var payload = try? decoder.decode(HookPayload.self, from: bodyData) else {
        sendJSON(connection, status: 400, body: #"{"error":"invalid json"}"#, context: context)
        return
    }
    // ... 注入 toolInputRaw 逻辑不变 ...
    sendJSON(connection, status: 200, body: "{}", context: nil)  // 先发响应
    Task { await EventBus.shared.emit(.hook(payload)) }
    Task { @MainActor in
        self.sessionManager.processHookEvent(payload)
        // 异步补录 hook 记录（含 workspaceId/surfaceId）
        let wsId: UUID?
        let sfId: UUID?
        if let sid = payload.sessionId, let session = HookSessionStore.shared.get(sid) {
            wsId = UUID(uuidString: session.workspaceId)
            sfId = UUID(uuidString: session.surfaceId)
        } else {
            wsId = nil; sfId = nil
        }
        let truncReq = context.requestBody.flatMap {
            let s = String(data: $0, encoding: .utf8) ?? ""
            return s.count > 4096 ? String(s.prefix(4096)) + " [truncated]" : s
        }
        let record = CtrlAPIRecord(
            id: UUID(), timestamp: context.startTime,
            method: context.method, path: context.path, toolName: nil,
            requestBody: truncReq, responseBody: "{}",
            statusCode: 200,
            durationMs: Date().timeIntervalSince(context.startTime) * 1000,
            error: nil, workspaceId: wsId, surfaceId: sfId
        )
        CtrlAPIStore.shared.append(record)
    }
}
```

- [ ] **Step 7: 改造 handleMCP — notifications 传 context，handleToolsCall 注入 toolName**

```swift
private func handleMCP(bodyData: Data, connection: NWConnection, context: RequestContext) {
    // ... parse method, id, params ...
    if method.hasPrefix("notifications/") {
        sendEmpty(connection, status: 202, context: context)
        return
    }
    switch method {
    case "initialize":   handleInitialize(connection: connection, id: id, context: context)
    case "tools/list":   handleToolsList(connection: connection, id: id, context: context)
    case "tools/call":   handleToolsCall(connection: connection, id: id, params: params, context: context)
    default:             sendRPCError(connection, id: id, code: -32601, message: "Method not found: \(method)", context: context)
    }
}

private func handleToolsCall(connection: NWConnection, id: Any?, params: [String: Any]?, context: RequestContext) {
    guard let name = params?["name"] as? String else {
        sendRPCError(connection, id: id, code: -32602, message: "Invalid params: missing name", context: context)
        return
    }
    let arguments = params?["arguments"] as? [String: Any] ?? [:]
    let toolCtx = RequestContext(
        method: context.method, path: context.path, startTime: context.startTime,
        requestBody: context.requestBody, toolName: name,
        workspaceId: context.workspaceId, surfaceId: context.surfaceId
    )
    let handler = CtrlToolHandler(port: self.port)
    Task {
        do {
            let resultText = try await handler.callTool(name: name, arguments: arguments)
            let content: [[String: Any]] = [["type": "text", "text": resultText]]
            self.sendRPCResult(connection, id: id, result: ["content": content], context: toolCtx)
        } catch let err as CtrlToolHandler.RPCError {
            self.sendRPCError(connection, id: id, code: err.code, message: err.message, context: toolCtx)
        } catch {
            self.sendRPCError(connection, id: id, code: -32603, message: error.localizedDescription, context: toolCtx)
        }
    }
}
```

- [ ] **Step 8: 改造 handleSSE — 只记录连接建立**

```swift
private func handleSSE(connection: NWConnection, context: RequestContext) {
    let header = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n"
    connection.send(content: header.data(using: .utf8)!, completion: .contentProcessed { [weak self] error in
        guard let self, error == nil else { connection.cancel(); return }
        // 记录 SSE 连接建立
        let record = CtrlAPIRecord(
            id: UUID(), timestamp: context.startTime,
            method: context.method, path: "/mcp (SSE)", toolName: nil,
            requestBody: nil, responseBody: nil,
            statusCode: 200,
            durationMs: Date().timeIntervalSince(context.startTime) * 1000,
            error: nil, workspaceId: nil, surfaceId: nil
        )
        Task { await MainActor.run { CtrlAPIStore.shared.append(record) } }
        // ... 原有 SSE 逻辑不变（timer、EventBus 订阅等）...
    })
}
```

- [ ] **Step 9: 构建验证**
```bash
make dev 2>&1 | tail -30
```
Expected: 无编译错误

- [ ] **Step 10: Commit**
```bash
git add macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift
git commit -m "feat(ctrl-api-monitor): intercept all CtrlServer requests into CtrlAPIStore"
```

---

### Task 4：CtrlAPIMonitorViewModel

**Files:**
- Create: `macos/Sources/Features/Agent/CtrlServer/CtrlAPIMonitorViewModel.swift`

- [ ] **Step 1: 新建文件**

```swift
// macos/Sources/Features/Agent/CtrlServer/CtrlAPIMonitorViewModel.swift
import Foundation
import Combine

@MainActor
final class CtrlAPIMonitorViewModel: ObservableObject {
    @Published private(set) var records: [CtrlAPIRecord] = []
    @Published var selectedWorkspaceId: UUID? = nil
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
                if let recWs = record.workspaceId, recWs != wsId { return false }
            }
            if let sfId = selectedSurfaceId {
                if let recSf = record.surfaceId, recSf != sfId { return false }
            }
            return true
        }.reversed()
    }

    var availableWorkspaceIds: [UUID] {
        Array(Set(records.compactMap(\.workspaceId))).sorted { $0.uuidString < $1.uuidString }
    }

    var availableSurfaceIds: [UUID] {
        Array(Set(records.compactMap(\.surfaceId))).sorted { $0.uuidString < $1.uuidString }
    }

    func clearRecords() {
        CtrlAPIStore.shared.clear()
        selectedRecord = nil
    }
}
```

- [ ] **Step 2: 构建验证 + Commit**
```bash
make dev 2>&1 | tail -20
git add macos/Sources/Features/Agent/CtrlServer/CtrlAPIMonitorViewModel.swift
git commit -m "feat(ctrl-api-monitor): add CtrlAPIMonitorViewModel"
```

---

### Task 5：CtrlAPIMonitorPanel（SwiftUI View）

**Files:**
- Create: `macos/Sources/Features/Agent/CtrlServer/CtrlAPIMonitorPanel.swift`

- [ ] **Step 1: 新建文件**

```swift
// macos/Sources/Features/Agent/CtrlServer/CtrlAPIMonitorPanel.swift
import SwiftUI

struct CtrlAPIMonitorPanel: View {
    @StateObject private var viewModel = CtrlAPIMonitorViewModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if viewModel.filteredRecords.isEmpty {
                emptyState
            } else {
                VSplitView {
                    recordList
                    if viewModel.selectedRecord != nil {
                        detailView
                            .frame(minHeight: 80, idealHeight: 160)
                    }
                }
            }
        }
        .frame(minHeight: 120)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "network")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Ctrl API")
                    .font(.system(size: 11, weight: .semibold))
            }
            Spacer()
            // Workspace filter
            if !viewModel.availableWorkspaceIds.isEmpty {
                Picker("WS", selection: $viewModel.selectedWorkspaceId) {
                    Text("All WS").tag(Optional<UUID>.none)
                    ForEach(viewModel.availableWorkspaceIds, id: \.self) { id in
                        Text(id.uuidString.prefix(8) + "…").tag(Optional(id))
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.mini)
                .frame(maxWidth: 80)
            }
            // Surface filter
            if !viewModel.availableSurfaceIds.isEmpty {
                Picker("SF", selection: $viewModel.selectedSurfaceId) {
                    Text("All SF").tag(Optional<UUID>.none)
                    ForEach(viewModel.availableSurfaceIds, id: \.self) { id in
                        Text(id.uuidString.prefix(8) + "…").tag(Optional(id))
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.mini)
                .frame(maxWidth: 80)
            }
            Button("Clear") { viewModel.clearRecords() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 4) {
            Spacer()
            Image(systemName: "network.slash")
                .font(.system(size: 20, weight: .thin))
                .foregroundStyle(.quaternary)
            Text("No API calls recorded")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Record List

    private var recordList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.filteredRecords) { record in
                    RecordRow(record: record, isSelected: viewModel.selectedRecord?.id == record.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if viewModel.selectedRecord?.id == record.id {
                                viewModel.selectedRecord = nil
                            } else {
                                viewModel.selectedRecord = record
                            }
                        }
                    Divider().padding(.leading, 8)
                }
            }
        }
    }

    // MARK: - Detail View

    private var detailView: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Request")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                ScrollView([.horizontal, .vertical]) {
                    Text(prettyJSON(viewModel.selectedRecord?.requestBody))
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                        .textSelection(.enabled)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Response")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                ScrollView([.horizontal, .vertical]) {
                    Text(prettyJSON(viewModel.selectedRecord?.responseBody))
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                        .textSelection(.enabled)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
    }

    private func prettyJSON(_ str: String?) -> String {
        guard let str, let data = str.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
              let result = String(data: pretty, encoding: .utf8) else {
            return str ?? "(empty)"
        }
        return result
    }
}

// MARK: - RecordRow

private struct RecordRow: View {
    let record: CtrlAPIRecord
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            // 时间
            Text(timeString)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            // 方法
            Text(record.method)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(methodColor)
                .frame(width: 38, alignment: .leading)
            // 路径/工具
            Text(displayPath)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            // 耗时
            Text(durationString)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(durationColor)
                .frame(width: 46, alignment: .trailing)
            // 状态
            Text("\(record.statusCode)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(statusColor)
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: record.timestamp)
    }

    private var displayPath: String {
        if let tool = record.toolName { return "tools/call · \(tool)" }
        if record.path.contains("/mcp") && record.method == "GET" { return "/mcp (SSE)" }
        return record.path
    }

    private var durationString: String {
        let ms = record.durationMs
        if ms < 10 { return String(format: "%.1fms", ms) }
        return String(format: "%.0fms", ms)
    }

    private var methodColor: Color {
        switch record.method {
        case "POST":   return .blue
        case "GET":    return .green
        case "DELETE": return .red
        default:       return .secondary
        }
    }

    private var statusColor: Color {
        if record.error != nil { return .red }
        if record.statusCode >= 400 { return .red }
        if record.statusCode >= 200 { return .primary }
        return .secondary
    }

    private var durationColor: Color {
        if record.durationMs < 10 { return .green }
        if record.durationMs < 100 { return .primary }
        return .orange
    }
}
```

- [ ] **Step 2: 构建验证 + Commit**
```bash
make dev 2>&1 | tail -30
git add macos/Sources/Features/Agent/CtrlServer/CtrlAPIMonitorPanel.swift
git commit -m "feat(ctrl-api-monitor): add CtrlAPIMonitorPanel SwiftUI view"
```

---

### Task 6：BottomStatusBarView — 添加入口按钮

**Files:**
- Modify: `macos/Sources/Features/Workspace/BottomStatusBarView.swift`

`BottomStatusBarView` 是 per-pane 组件，不适合在其内部持有面板状态（否则每个 pane 各有独立 Panel）。入口按钮放在 statusbar，但面板在 pane 的 parent view 层级展示。

查看 `BottomStatusBarView` 的使用方，找到 parent view 在哪里添加面板。

- [ ] **Step 1: 查找 BottomStatusBarView 的调用方**
```bash
grep -rn "BottomStatusBarView" macos/Sources/ --include="*.swift"
```

- [ ] **Step 2: 在 parent view 添加状态 + 面板**

找到调用 `BottomStatusBarView` 的 view，添加：
```swift
@State private var showCtrlAPIMonitor = false
```

在 `BottomStatusBarView` 下方添加：
```swift
if showCtrlAPIMonitor {
    Divider()
    CtrlAPIMonitorPanel()
        .frame(height: 220)
}
```

- [ ] **Step 3: 在 BottomStatusBarView 添加按钮**

`BottomStatusBarView` 需要一个回调或 binding 来控制面板显示。添加 binding 参数：

```swift
struct BottomStatusBarView: View {
    // 现有参数...
    @Binding var showCtrlAPIMonitor: Bool
    // ...
}
```

在 `AgentButtonView` 右侧添加按钮：
```swift
Button(action: { showCtrlAPIMonitor.toggle() }) {
    Image(systemName: "network")
        .font(.system(size: 11))
        .foregroundStyle(showCtrlAPIMonitor ? Color.accentColor : Color.secondary)
}
.buttonStyle(.plain)
.help("Ctrl API Monitor")
```

- [ ] **Step 4: 构建验证**
```bash
make dev 2>&1 | tail -30
```
Expected: 无编译错误

- [ ] **Step 5: Commit**
```bash
git add macos/Sources/Features/Workspace/BottomStatusBarView.swift
git add macos/Sources/  # 任何 parent view 修改
git commit -m "feat(ctrl-api-monitor): add Ctrl API monitor button to bottom statusbar"
```

---

### Task 7：最终构建验证 + PR

- [ ] **Step 1: 全量构建**
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/Ghostty-* && make clean && make dev 2>&1 | tail -40
```
Expected: Build Succeeded

- [ ] **Step 2: 提交 PR**
```bash
git push -u origin feat/ctrl-api-monitor
gh pr create --title "feat(ctrl-api-monitor): 添加 Ctrl API 调用监控面板" --body "..."
```
