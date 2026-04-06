# Ctrl API 2.2 剩余接口实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 Ctrl API 剩余的 4 个工具（`set_agent_label`、`get_workspace_state`、`notify`、`open_in_file_browser`）和 2 个 SSE 事件（`agent_status_changed`、`workspace_switched`）。

**Architecture:** 所有工具在 `CtrlToolHandler.swift` 添加实现，在 `CtrlServer.handleToolsList()` 注册 schema；SSE 事件在 `EventBus.swift` 添加 case，在 `CtrlServer.formatSSENotification()` 格式化，在 `AgentSessionManager.updateState()` 及 `CtrlServer.start()` 触发。

**Tech Stack:** Swift 5.9+，AppKit，Network framework（NWListener），@MainActor / actor 并发模型。

---

## 文件变更清单

| 文件 | 操作 |
|------|------|
| `macos/Sources/Features/Agent/CtrlServer/EventBus.swift` | 新增 2 个 Event case |
| `macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift` | 格式化新 SSE 事件 + 注册 workspace_switched 观察者 + 注册 4 个工具 schema |
| `macos/Sources/Features/Agent/AgentSession.swift` | 新增 `customLabel: String?` 字段 |
| `macos/Sources/Features/Agent/AgentSessionManager.swift` | `updateState()` 等处 emit agent_status_changed |
| `macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift` | 新增 4 个工具实现 + callTool switch 分支 |
| `docs/rules/ctrl-api-rules.md` | SSE 事件表新增两行 |

---

## Task 1: EventBus — 新增两个 SSE Event case

**Files:**
- Modify: `macos/Sources/Features/Agent/CtrlServer/EventBus.swift`

- [ ] **Step 1: 在 EventBus.Event 枚举末尾添加两个 case**

打开 `macos/Sources/Features/Agent/CtrlServer/EventBus.swift`，将第 16 行的 `}` 前面（即 `tabClosed` case 之后）添加：

```swift
        case agentStatusChanged(
            sessionId: String,
            state: String,
            workspaceId: UUID,
            customLabel: String?
        )
        case workspaceSwitched(
            workspaceId: UUID,
            previousWorkspaceId: UUID?
        )
```

修改后 `enum Event` 完整内容：

```swift
    enum Event: @unchecked Sendable {
        case hook(HookPayload)
        case paneCreated(paneId: UUID, tabId: UUID, workspaceId: UUID)
        case paneClosed(paneId: UUID)
        case paneFocused(paneId: UUID)
        case tabCreated(tabId: UUID, workspaceId: UUID)
        case tabClosed(tabId: UUID)
        case agentStatusChanged(
            sessionId: String,
            state: String,
            workspaceId: UUID,
            customLabel: String?
        )
        case workspaceSwitched(
            workspaceId: UUID,
            previousWorkspaceId: UUID?
        )
    }
```

- [ ] **Step 2: 编译检查**

```bash
make check
```

预期：0 errors（新 case 不需要 `formatSSENotification` 立即处理，switch 中 default 分支兜底）。

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Agent/CtrlServer/EventBus.swift
git commit -m "feat(ctrl-api): add agentStatusChanged and workspaceSwitched EventBus events"
```

---

## Task 2: CtrlServer — 格式化新 SSE 事件

**Files:**
- Modify: `macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift:361-394`

- [ ] **Step 1: 在 `formatSSENotification` 的 switch 中添加两个 case**

在 `CtrlServer.swift` 第 387 行 `case .tabClosed(let tabId):` 块之后、第 388 行 `}` 之前插入：

```swift
        case .agentStatusChanged(let sessionId, let state, let workspaceId, let customLabel):
            method = "notifications/agent_status_changed"
            params["sessionId"] = sessionId
            params["state"] = state
            params["workspaceId"] = workspaceId.uuidString
            if let label = customLabel { params["customLabel"] = label }
        case .workspaceSwitched(let workspaceId, let previousWorkspaceId):
            method = "notifications/workspace_switched"
            params["workspaceId"] = workspaceId.uuidString
            if let prev = previousWorkspaceId { params["previousWorkspaceId"] = prev.uuidString }
```

- [ ] **Step 2: 编译检查**

```bash
make check
```

预期：0 errors。

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift
git commit -m "feat(ctrl-api): format agentStatusChanged and workspaceSwitched SSE notifications"
```

---

## Task 3: CtrlServer — workspace_switched 观察者

**Files:**
- Modify: `macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift`

需要在 CtrlServer 中记录上次活跃的 workspace ID，监听 `NSWindow.didBecomeKeyNotification`，在切换时 emit。

- [ ] **Step 1: 在 CtrlServer class 属性区（第 19 行附近）添加属性**

在 `private let queue = DispatchQueue(...)` 那行之后添加：

```swift
    /// 上次 emit workspace_switched 时的 workspaceId，用于去重
    private var lastActiveWorkspaceId: UUID? = nil
    private var windowObserver: NSObjectProtocol? = nil
```

- [ ] **Step 2: 在 `start()` 方法末尾（listener.start 之后）注册观察者**

找到 `start()` 方法中 `listener.start(queue: queue)` 那行，在它之后（仍在 `start()` 函数体内）添加：

```swift
        // MARK: workspace_switched 观察
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let window = notification.object as? NSWindow,
                  let newId = WorkspaceManager.shared.workspaceId(for: window),
                  newId != self.lastActiveWorkspaceId
            else { return }
            let prev = self.lastActiveWorkspaceId
            self.lastActiveWorkspaceId = newId
            Task { await EventBus.shared.emit(.workspaceSwitched(workspaceId: newId, previousWorkspaceId: prev)) }
        }
```

注意：`WorkspaceManager.shared.workspaceId(for:)` 已经存在（`WorkspaceManager.swift:228`），直接调用即可。

- [ ] **Step 3: 编译检查**

```bash
make check
```

预期：0 errors。`NSWindow` 在 AppKit 中，但 `CtrlServer.swift` 只 import Foundation/Network。需要在文件顶部添加 `import AppKit`（如果尚未有）。

检查：
```bash
grep "import AppKit" macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift
```

若无输出，在文件第 4 行（`import Network` 之后）添加：
```swift
import AppKit
```

然后再次 `make check`。

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift
git commit -m "feat(ctrl-api): emit workspace_switched SSE on window focus change"
```

---

## Task 4: AgentSession — 新增 customLabel 字段

**Files:**
- Modify: `macos/Sources/Features/Agent/AgentSession.swift:57-83`

- [ ] **Step 1: 在 AgentSession struct 末尾添加 customLabel 字段**

在 `var deniedToolCount: Int = 0` 那行（第 77 行）之后添加：

```swift
    /// Agent 通过 set_agent_label 工具设置的自定义标签
    var customLabel: String? = nil
```

- [ ] **Step 2: 编译检查**

```bash
make check
```

预期：0 errors（新字段有默认值，不影响现有初始化）。

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Agent/AgentSession.swift
git commit -m "feat(ctrl-api): add customLabel field to AgentSession"
```

---

## Task 5: AgentSessionManager — emit agent_status_changed

**Files:**
- Modify: `macos/Sources/Features/Agent/AgentSessionManager.swift`

在以下三处触发 `EventBus.shared.emit(.agentStatusChanged(...))`：
1. `updateState(_:surfaceId:)` — 任意状态变更
2. `processHookEvent()` 的 `sessionEnd` 分支
3. `processHookEvent()` 的 `stop` 分支

辅助方法：提取一个私有方法 `emitAgentStatus(surfaceId:)` 避免重复。

- [ ] **Step 1: 在 `AgentSessionManager` 末尾（第 345 行前）添加辅助方法**

```swift
    // MARK: - SSE 事件

    /// 根据 surfaceId 找到对应 session，向 EventBus emit agentStatusChanged 事件。
    private func emitAgentStatus(surfaceId: UUID) {
        guard let session = sessions[surfaceId] else { return }
        let stateStr: String
        switch session.state {
        case .launching:       stateStr = "launching"
        case .working:         stateStr = "working"
        case .idle:            stateStr = "idle"
        case .done:            stateStr = "done"
        case .error:           stateStr = "error"
        }
        Task {
            await EventBus.shared.emit(.agentStatusChanged(
                sessionId: session.claudeSessionId ?? surfaceId.uuidString,
                state: stateStr,
                workspaceId: session.workspaceId,
                customLabel: session.customLabel
            ))
        }
    }
```

- [ ] **Step 2: 在 `updateState(_:surfaceId:)` 末尾调用辅助方法**

找到 `updateState` 方法（第 41-44 行）：
```swift
    func updateState(_ state: AgentState, surfaceId: UUID) {
        sessions[surfaceId]?.state = state
        sessions[surfaceId]?.lastEventAt = Date()
    }
```

修改为：
```swift
    func updateState(_ state: AgentState, surfaceId: UUID) {
        sessions[surfaceId]?.state = state
        sessions[surfaceId]?.lastEventAt = Date()
        emitAgentStatus(surfaceId: surfaceId)
    }
```

- [ ] **Step 3: 编译检查**

```bash
make check
```

预期：0 errors。

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Agent/AgentSessionManager.swift
git commit -m "feat(ctrl-api): emit agent_status_changed SSE on state updates"
```

---

## Task 6: notify 工具

**Files:**
- Modify: `macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift`
- Modify: `macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift`

- [ ] **Step 1: 在 `callTool` switch 中添加 notify case**

在 `CtrlToolHandler.swift` 的 `callTool` switch（第 31-65 行）中，`case "show_agent_monitor":` 之前插入：

```swift
        case "notify":               return try await callNotify(arguments: arguments)
        case "open_in_file_browser": return try await callOpenInFileBrowser(arguments: arguments)
        case "set_agent_label":      return try await callSetAgentLabel(arguments: arguments)
        case "get_workspace_state":  return try await callGetWorkspaceState(arguments: arguments)
```

（一次性把四个工具的 case 全部加上，后续任务只需实现方法即可。）

- [ ] **Step 2: 实现 `callNotify()` 方法**

在 `CtrlToolHandler.swift` 末尾（最后一个 `}` 之前）添加：

```swift
    // MARK: - notify

    private func callNotify(arguments: [String: Any]) async throws -> String {
        guard let title = arguments["title"] as? String, !title.isEmpty else {
            throw RPCError(code: -32602, message: "notify: missing required parameter 'title'")
        }
        let body = arguments["body"] as? String

        let workspaceId: UUID? = await MainActor.run {
            if let wsIdStr = arguments["workspaceId"] as? String,
               let wsId = UUID(uuidString: wsIdStr) {
                return wsId
            }
            return WorkspaceManager.shared.activeWorkspaceId()
        }

        await MainActor.run {
            AgentNotificationStore.shared.insert(AgentNotification(
                id: UUID(),
                timestamp: Date(),
                workspaceId: workspaceId,
                surfaceId: nil,
                agentDefinitionId: "ctrl-api",
                sessionId: nil,
                type: .info,
                title: title,
                body: body,
                priority: .normal
            ))
        }
        return #"{"ok":true}"#
    }
```

- [ ] **Step 3: 在 `handleToolsList()` 注册 notify schema**

在 `CtrlServer.swift` 的 `handleToolsList()` 方法中，`var tools: [[String: Any]] = [` 数组末尾（最后一个 `]` 的 `]` 之前）添加：

```swift
            ,
            [
                "name": "notify",
                "description": "Send a notification to the in-app notification panel of the specified or active workspace",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "title":       ["type": "string", "description": "Notification title (required)"],
                        "body":        ["type": "string", "description": "Notification body text (optional)"],
                        "workspaceId": ["type": "string", "description": "UUID of the target workspace (optional, defaults to active workspace)"]
                    ],
                    "required": ["title"]
                ]
            ]
```

- [ ] **Step 4: 编译检查**

```bash
make check
```

预期：0 errors。

- [ ] **Step 5: 手动验证**

构建并运行：
```bash
make dev
```

在终端中（打开 Poltertty 后）运行：
```bash
curl -s -X POST "http://localhost:$(cat ~/.poltertty/ctrl_port 2>/dev/null || echo 'FIND_PORT')/v1/mcp" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"notify","arguments":{"title":"测试通知","body":"来自 Ctrl API"}}}'
```

预期：侧边栏对应 workspace 出现未读角标，Notification Panel 中出现该通知。

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift \
        macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift
git commit -m "feat(ctrl-api): add notify tool"
```

---

## Task 7: open_in_file_browser 工具

**Files:**
- Modify: `macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift`
- Modify: `macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift`

- [ ] **Step 1: 实现 `callOpenInFileBrowser()` 方法**

在 `CtrlToolHandler.swift` 末尾（`callNotify` 之后）添加：

```swift
    // MARK: - open_in_file_browser

    private func callOpenInFileBrowser(arguments: [String: Any]) async throws -> String {
        guard let rawPath = arguments["path"] as? String, !rawPath.isEmpty else {
            throw RPCError(code: -32602, message: "open_in_file_browser: missing required parameter 'path'")
        }
        let path = (rawPath as NSString).expandingTildeInPath

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                let workspaceId: UUID
                if let wsIdStr = arguments["workspaceId"] as? String,
                   let wsId = UUID(uuidString: wsIdStr) {
                    workspaceId = wsId
                } else if let active = WorkspaceManager.shared.activeWorkspaceId() {
                    workspaceId = active
                } else {
                    cont.resume(throwing: RPCError(code: -32603, message: "open_in_file_browser: no active workspace"))
                    return
                }

                // 若文件浏览器未打开，先打开它
                let yaziStore = WorkspaceManager.shared.yaziSurfaceStore
                if yaziStore?.hasSurface(for: workspaceId) == false {
                    NotificationCenter.default.post(name: .toggleFileBrowser, object: nil)
                }

                // 等一个 RunLoop tick，给 yazi surface 初始化时间
                DispatchQueue.main.async {
                    WorkspaceManager.shared.yaziSurfaceStore?.cdToDirectory(workspaceId, path: path)
                    cont.resume()
                }
            }
        }
        return #"{"ok":true}"#
    }
```

**注意**：`YaziSurfaceStore` 没有独立单例，通过 `WorkspaceManager.shared.yaziSurfaceStore`（`weak var`）访问。

- [ ] **Step 2: 在 `handleToolsList()` 注册 open_in_file_browser schema**

在 notify schema 之后继续添加：

```swift
            ,
            [
                "name": "open_in_file_browser",
                "description": "Navigate the file browser (yazi) to the specified path; opens the file browser panel if not already open",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "path":        ["type": "string", "description": "Target directory or file path (~ supported)"],
                        "workspaceId": ["type": "string", "description": "UUID of the target workspace (optional, defaults to active workspace)"]
                    ],
                    "required": ["path"]
                ]
            ]
```

- [ ] **Step 3: 编译检查**

```bash
make check
```

若出现 `AppDelegate.shared` 找不到：检查 AppDelegate 的 shared 实例访问方式，改用 `(NSApp.delegate as? AppDelegate)?.yaziSurfaceStore`。

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift \
        macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift
git commit -m "feat(ctrl-api): add open_in_file_browser tool"
```

---

## Task 8: set_agent_label 工具

**Files:**
- Modify: `macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift`
- Modify: `macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift`

- [ ] **Step 1: 实现 `callSetAgentLabel()` 方法**

在 `callOpenInFileBrowser` 之后添加：

```swift
    // MARK: - set_agent_label

    private func callSetAgentLabel(arguments: [String: Any]) async throws -> String {
        guard let sessionId = arguments["sessionId"] as? String, !sessionId.isEmpty else {
            throw RPCError(code: -32602, message: "set_agent_label: missing required parameter 'sessionId'")
        }
        guard let label = arguments["label"] as? String else {
            throw RPCError(code: -32602, message: "set_agent_label: missing required parameter 'label'")
        }

        // 可选 state 参数校验
        let newState: AgentState?
        if let stateStr = arguments["state"] as? String {
            switch stateStr {
            case "working": newState = .working
            case "idle":    newState = .idle
            case "done":    newState = .done(exitCode: 0)
            default:
                throw RPCError(code: -32602, message: "set_agent_label: invalid state '\(stateStr)', allowed: working | idle | done")
            }
        } else {
            newState = nil
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                let agentManager = AgentService.shared.sessionManager
                guard agentManager.session(forClaudeSessionId: sessionId) != nil else {
                    cont.resume(throwing: RPCError(code: -32603, message: "set_agent_label: session not found for sessionId '\(sessionId)'"))
                    return
                }
                agentManager.updateFromClaudeSession(sessionId) { session in
                    session.customLabel = label
                    if let state = newState { session.state = state }
                }
                // 取出更新后的 surfaceId，emit SSE
                if let surfaceId = agentManager.sessions.first(where: { $0.value.claudeSessionId == sessionId })?.key {
                    agentManager.emitAgentStatus(surfaceId: surfaceId)
                }
                cont.resume()
            }
        }
        return #"{"ok":true}"#
    }
```

**注意**：`emitAgentStatus` 在 Task 5 中定义为 `private`，需改为 `internal`（去掉 `private` 修饰符）以便 CtrlToolHandler 调用。

检查是否需要：
```bash
grep -n "private func emitAgentStatus" macos/Sources/Features/Agent/AgentSessionManager.swift
```

若有 `private`，将其改为（无访问修饰符）：
```swift
    func emitAgentStatus(surfaceId: UUID) {
```

同时检查 AppDelegate 暴露 agentService 的方式：
```bash
grep -n "agentService\|AgentService" macos/Sources/AppDelegate.swift | head -10
```

若访问路径不同（如 `AgentService.shared`），改用：
```swift
AgentService.shared.sessionManager.session(forClaudeSessionId: sessionId)
```

- [ ] **Step 2: 在 `handleToolsList()` 注册 set_agent_label schema**

```swift
            ,
            [
                "name": "set_agent_label",
                "description": "Set a custom label and optional state for an agent session, visible in the Agent Dashboard",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "sessionId": ["type": "string", "description": "Claude session ID (CLAUDE_SESSION_ID env var)"],
                        "label":     ["type": "string", "description": "Custom display label for this session"],
                        "state":     ["type": "string", "enum": ["working", "idle", "done"], "description": "Optional state override"]
                    ],
                    "required": ["sessionId", "label"]
                ]
            ]
```

- [ ] **Step 3: 编译检查**

```bash
make check
```

`AgentService.shared.sessionManager` 已确认（`AgentService.swift:8,16`），直接使用。

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift \
        macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift \
        macos/Sources/Features/Agent/AgentSessionManager.swift
git commit -m "feat(ctrl-api): add set_agent_label tool"
```

---

## Task 9: get_workspace_state 工具

**Files:**
- Modify: `macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift`
- Modify: `macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift`

这是最复杂的工具，聚合 WorkspaceManager、list_panes 逻辑、AgentSessionManager、WorkspaceMetadataStore、git branch。

- [ ] **Step 1: 实现 `callGetWorkspaceState()` 方法**

在 `callSetAgentLabel` 之后添加：

```swift
    // MARK: - get_workspace_state

    private func callGetWorkspaceState(arguments: [String: Any]) async throws -> String {
        // 1. 解析 workspaceId
        let workspaceId: UUID = try await withCheckedThrowingContinuation { cont in
            Task { @MainActor in
                if let wsIdStr = arguments["workspaceId"] as? String,
                   let wsId = UUID(uuidString: wsIdStr) {
                    cont.resume(returning: wsId)
                } else if let active = WorkspaceManager.shared.activeWorkspaceId() {
                    cont.resume(returning: active)
                } else {
                    cont.resume(throwing: RPCError(code: -32602, message: "get_workspace_state: no workspaceId provided and no active workspace"))
                }
            }
        }

        // 2. 采集所有数据（@MainActor）
        let snapshot: (
            name: String?,
            rootDir: String?,
            color: String?,
            panes: [[String: Any]],
            agents: [[String: Any]],
            ports: [Int],
            prStatus: PRStatus?,
            agentSessions: [AgentSession]
        ) = try await withCheckedThrowingContinuation { cont in
            Task { @MainActor in
                guard let ws = WorkspaceManager.shared.workspace(for: workspaceId) else {
                    cont.resume(throwing: RPCError(code: -32603, message: "get_workspace_state: workspace not found"))
                    return
                }

                // panes
                let panes: [[String: Any]]
                if let tc = Self.tcForWorkspace(workspaceId) {
                    panes = tc.listPanes().map { p in
                        var d: [String: Any] = [
                            "id": p.id.uuidString,
                            "tabId": p.tabId.uuidString,
                            "isActive": p.isActive,
                            "tabIndex": p.tabIndex,
                            "paneIndex": p.paneIndex
                        ]
                        if let title = p.title { d["title"] = title }
                        if let annotation = p.annotation { d["annotation"] = annotation }
                        return d
                    }
                } else {
                    panes = []
                }

                // agents
                let agentSessions = AgentService.shared.sessionManager.sessions.values
                    .filter { $0.workspaceId == workspaceId }
                    .sorted { $0.startedAt < $1.startedAt }

                let agentsArr: [[String: Any]] = agentSessions.map { s in
                    let stateStr: String
                    switch s.state {
                    case .launching: stateStr = "launching"
                    case .working:   stateStr = "working"
                    case .idle:      stateStr = "idle"
                    case .done:      stateStr = "done"
                    case .error:     stateStr = "error"
                    }
                    var d: [String: Any] = [
                        "surfaceId": s.surfaceId.uuidString,
                        "state": stateStr,
                        "startedAt": ISO8601DateFormatter().string(from: s.startedAt)
                    ]
                    if let sid = s.claudeSessionId { d["sessionId"] = sid }
                    if let model = s.model { d["model"] = model }
                    if let label = s.customLabel { d["customLabel"] = label }
                    return d
                }

                // metadata
                let meta = WorkspaceMetadataStore.shared.metadata[workspaceId]

                cont.resume(returning: (
                    name: ws.name,
                    rootDir: ws.rootDirExpanded,
                    color: ws.colorHex,
                    panes: panes,
                    agents: agentsArr,
                    ports: meta?.listeningPorts ?? [],
                    prStatus: meta?.prStatus,
                    agentSessions: Array(agentSessions)
                ))
            }
        }

        // 3. 获取 git branch（非 @MainActor，可直接 shell）
        var result: [String: Any] = [
            "workspaceId": workspaceId.uuidString,
            "name": snapshot.name ?? "",
            "rootDir": snapshot.rootDir ?? "",
            "panes": snapshot.panes,
            "agents": snapshot.agents
        ]
        if let color = snapshot.color { result["color"] = color }

        if let rootDir = snapshot.rootDir {
            let branchResult = CtrlShellRunner.git(["-C", rootDir, "branch", "--show-current"])
            let branch = branchResult.trimmedStdout
            if !branch.isEmpty { result["branch"] = branch }
        }

        if !snapshot.ports.isEmpty {
            result["ports"] = snapshot.ports.map { ":\($0)" }
        }

        if let pr = snapshot.prStatus {
            var prDict: [String: Any]
            switch pr {
            case .open(let n):   prDict = ["number": n, "state": "open"]
            case .draft(let n):  prDict = ["number": n, "state": "draft"]
            case .merged(let n): prDict = ["number": n, "state": "merged"]
            }
            if let branch = result["branch"] as? String { prDict["branch"] = branch }
            result["prStatus"] = prDict
        }

        guard let data = try? JSONSerialization.data(withJSONObject: result),
              let str = String(data: data, encoding: .utf8) else {
            throw RPCError(code: -32603, message: "get_workspace_state: serialization failed")
        }
        return str
    }
```

**注意**：`AgentService.shared.sessionManager` 已确认（`AgentService.swift:8,16`），直接使用。

- [ ] **Step 2: 在 `handleToolsList()` 注册 get_workspace_state schema**

```swift
            ,
            [
                "name": "get_workspace_state",
                "description": "Get full state snapshot of a workspace: metadata, panes, agents, listening ports, PR status, and git branch",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "workspaceId": ["type": "string", "description": "UUID of the target workspace (optional, defaults to active workspace)"]
                    ]
                ]
            ]
```

- [ ] **Step 3: 编译检查**

```bash
make check
```

若编译报 `trimmedStdout` 找不到，检查 `CtrlShellRunner.Result` 的属性名（该属性定义在 `CtrlShellRunner.swift:14`）。

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift \
        macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift
git commit -m "feat(ctrl-api): add get_workspace_state tool"
```

---

## Task 10: 更新文档

**Files:**
- Modify: `docs/rules/ctrl-api-rules.md`
- Update: `docs/roadmap.md`

- [ ] **Step 1: 在 ctrl-api-rules.md SSE 事件表中添加两行**

找到 `docs/rules/ctrl-api-rules.md` 中 `## 3. SSE 事件流` 的表格，在 `tab_closed` 行之后添加：

```markdown
| `notifications/agent_status_changed` | Agent 状态变更 | `{sessionId, state, workspaceId, customLabel?}` |
| `notifications/workspace_switched` | 用户切换 Workspace | `{workspaceId, previousWorkspaceId?}` |
```

- [ ] **Step 2: 更新 roadmap.md 中 2.2 剩余接口状态**

找到 `docs/roadmap.md` 中 `## Phase 2` → `### ✅（大部分）2.2 Ctrl API 扩展` 的**尚未实现**表格，将所有行状态改为已实现，并将标题改为 `### ✅ 2.2 Ctrl API 扩展`：

原文：
```markdown
### ✅（大部分）2.2 Ctrl API 扩展
```
改为：
```markdown
### ✅ 2.2 Ctrl API 扩展
```

删除"尚未实现"表格，改为：

```markdown
**已实现接口（完整）**：`ping`、`new_tab`、`send_text`、`list_panes`、`focus_pane`、`split_pane`、`list_worktrees`、`create_worktree`、`get_git_status`、`get_instance_info`、`screenshot`、`open_workspace`（即 create_workspace）、`notify`、`open_in_file_browser`、`set_agent_label`、`get_workspace_state`

**已实现 SSE 事件**：`pane_created`、`pane_closed`、`pane_focused`、`tab_created`、`tab_closed`、`hook`、`agent_status_changed`、`workspace_switched`
```

- [ ] **Step 3: Commit**

```bash
git add docs/rules/ctrl-api-rules.md docs/roadmap.md
git commit -m "docs: mark Ctrl API 2.2 as complete, update SSE events table"
```

---

## 验证清单

全部任务完成后，手动验证：

```bash
# 构建
make dev

# 找到 ctrl port
CTRL_PORT=$(lsof -i TCP -sTCP:LISTEN -P | grep ghostty | head -1 | awk '{print $9}' | cut -d: -f2)

# 验证工具列表包含新工具
curl -s -X POST "http://localhost:$CTRL_PORT/v1/mcp" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
  | python3 -c "import sys,json; tools=json.load(sys.stdin)['result']['tools']; print([t['name'] for t in tools])"

# 预期输出包含: notify, open_in_file_browser, set_agent_label, get_workspace_state

# 测试 notify
curl -s -X POST "http://localhost:$CTRL_PORT/v1/mcp" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"notify","arguments":{"title":"验证完成","body":"Ctrl API 2.2 全部实现"}}}'

# 测试 get_workspace_state
curl -s -X POST "http://localhost:$CTRL_PORT/v1/mcp" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_workspace_state","arguments":{}}}' \
  | python3 -m json.tool
```
