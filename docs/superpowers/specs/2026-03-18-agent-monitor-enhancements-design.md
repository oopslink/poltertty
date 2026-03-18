# Agent Monitor Enhancements — Design Spec

**Date**: 2026-03-18
**Branch**: feature/workspace-ai-agent
**Status**: Approved

---

## 背景

Agent Monitor 当前已实现基础功能：hook 事件接收、subagent 列表、Trace/Messages Tab。
本次增强从 claude-office 项目中提取 5 个非动画 UI/数据模式，提升运行期可观测性和跨会话历史查阅。

---

## Feature 1 — 实时 Token 累计（Live Token Polling）

### 问题

`TokenTracker.processStopEvent` 只在 Stop hook 触发时一次性读取 transcript，
session 运行期间 `SessionOverviewContent` 的 cost/context 显示始终为初始值（`—` / `0%`）。

### 方案

在每次 `postToolUse` hook 触发时，由 `AgentSessionManager` 调用
`TokenTracker.pollLiveTokens(surfaceId:)`。该方法：

1. 推导主 session transcript 路径（完整格式）：
   ```
   ~/.claude/projects/{sanitized-cwd}/{claudeSessionId}.jsonl
   ```
   其中 `sanitized-cwd` = `SubagentTranscriptReader.sanitizeCwd(session.cwd)`，
   `claudeSessionId` 来自 `session.claudeSessionId`（若为 nil 则跳过）。
   与 subagent 路径的区别：主 session 文件直接在项目目录下，**不含** `/subagents/agent-` 部分。
2. 异步读取文件，复用 `parseTranscript(at:model:)` 已有逻辑
3. 调用 `sessionManager.updateTokenUsage(surfaceId:usage:)` 更新内存状态

**节流**：`TokenTracker` 维护 `[UUID: Date]` lastPollDate 字典，同一 surfaceId 两次 poll 间隔 < 5s 时直接跳过。

**保底更新**：若 session 长时间没有工具调用（如模型思考中），`SessionOverviewContent` 的现有 3s timer 中也调用一次 `pollLiveTokens`，保证 token 数据最多滞后 5s。（timer 本身不引入额外 poll，节流逻辑统一在 TokenTracker 内）

### 数据流

```
postToolUse hook
  → AgentSessionManager.processHookEvent
    → TokenTracker.pollLiveTokens(surfaceId:)   [throttled, 5s]
      → read ~/.claude/projects/.../session.jsonl
      → updateTokenUsage(surfaceId:usage:)
        → SessionOverviewContent 更新 cost / context bar
```

### 变更文件

- `TokenTracker.swift`：添加 `pollLiveTokens(surfaceId:)`、节流字典、路径推导逻辑
- `AgentSessionManager.swift`：`.postToolUse` 分支末尾调用 `tokenTracker?.pollLiveTokens(surfaceId:)`

---

## Feature 2 — 当前工具调用气泡（Active Tool Bubble）

### 问题

sidebar subagent 行右侧只有耗时计数，无法直观看出 subagent 当前正在执行哪个工具。

### 方案

在 `AgentSessionGroup.subagentRow` 中，当 `sub.state.isActive` 时，
在耗时标签左侧插入最后一个 `isDone == false` 的 toolCall 名称：

```swift
if sub.state.isActive,
   let activeTool = sub.toolCalls.last(where: { !$0.isDone }) {
    Text(String(activeTool.toolName.prefix(12)))
        .font(.system(size: 8))
        .foregroundStyle(.orange)
}
```

无数据模型变更，纯 UI 读取已有 `sub.toolCalls`。

### 变更文件

- `AgentSessionGroup.swift`：`subagentRow` 函数内添加工具气泡

---

## Feature 3 — 跨 Subagent 活动流（Global EventLog）

### 问题

`SessionOverviewContent` 只有 subagent 状态列表，无法观察多 subagent 并行时的事件时序，
难以判断瓶颈在哪个 subagent 的哪个工具调用。

### 方案

在 subagent 列表下方新增 **ACTIVITY** section，将所有 subagent 的 `toolCalls` 平铺，
按 `startedAt` 降序排列，取最近 **50 条**，每行格式：

```
[HH:mm:ss]  SubName  ToolName  ✓/⏳
```

- `✓` (绿) = `isDone == true`
- `⏳` (orange) = 进行中，同时显示已耗秒数

**数据推导（纯计算，无副作用）**：

```swift
struct EventEntry {
    let time: Date
    let subagentName: String
    let toolName: String
    let isDone: Bool
}

// 在 SessionOverviewContent 中计算：
var recentEvents: [EventEntry] {
    session.subagents.values
        .flatMap { sub in sub.toolCalls.map { call in
            EventEntry(time: call.startedAt,
                       subagentName: String(sub.name.prefix(10)),
                       toolName: call.toolName,
                       isDone: call.isDone)
        }}
        .sorted { $0.time > $1.time }   // 降序：最新的排在最上方
        .prefix(50)                      // 最多显示 50 条
}
```

**UI 排列**：最新事件在顶部（降序）。无日期分隔符，纯线性列表。若条目超过 50 条显示「… and N more」提示行。
```

### 变更文件

- `SessionOverviewContent.swift`：添加 `eventLogSection` view + `recentEvents` 计算属性

---

## Feature 4 — Transcript Poller 频率优化

### 问题

`SubagentMessagesView` 和 `SubagentTraceContent` 的 Timer 均为 3s，
active subagent 时消息/工具调用更新感觉明显滞后。

### 方案

将两处 Timer 间隔统一改为 **1s**：

```swift
// 旧
private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
// 新
private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
```

`SubagentMessagesView` 的 `loadTranscript()` 已经是异步读文件，1s 轮询的 I/O 开销在可接受范围内。
`SubagentTraceContent` 依赖内存数据（hook 事件已推送），1s 只是刷新 elapsed 计时。

### 变更文件

- `SubagentMessagesView.swift`：Timer 3 → 1
- `SubagentTraceContent.swift`：Timer 3 → 1

---

## Feature 5 — Session 持久化（Session Store）

### 问题

app 重启后所有 session 历史清空，无法回顾已完成 agent 的 token 消耗、subagent 数量和结果。

### 存储路径

```
~/.config/poltertty/workspaces/{workspaceId}/sessions/{sessionId}.json
```

（与现有 `workspaceDir` 路径体系保持一致）

### 数据模型

```swift
// macos/Sources/Features/Agent/Monitor/SessionStore.swift

struct PersistedSession: Codable, Identifiable {
    let id: UUID
    let workspaceId: UUID
    let agentName: String
    let cwd: String
    let claudeSessionId: String?
    let startedAt: Date
    let finishedAt: Date
    let tokenUsage: TokenUsage           // 已 Codable
    let subagents: [PersistedSubagent]
}

struct PersistedSubagent: Codable, Identifiable {
    let id: String
    let name: String
    let agentType: String
    let agentId: String?
    let startedAt: Date
    let finishedAt: Date?
    let exitCode: Int32?       // nil = 未正常结束；0 = 成功；非 0 = 失败
    let toolCallCount: Int
    let output: String?        // agent 最终输出文本（来自 PostToolUse tool_response）
}

final class SessionStore {
    static let shared = SessionStore()

    func save(_ session: AgentSession)                          // 写盘
    func load(for workspaceId: UUID) -> [PersistedSession]     // 读盘（按 finishedAt 降序）
    func delete(sessionId: UUID, workspaceId: UUID)            // 可选：清理旧记录
}
```

### 写入时机

`AgentSessionManager.processHookEvent(.sessionEnd)` 中，session 进入 `.done` 后：

```swift
if let session = sessions[surfaceId] {
    Task.detached(priority: .utility) {
        SessionStore.shared.save(session)
    }
}
```

### PersistedSession → AgentSession 映射（只读 Overview）

点击历史记录时，需将 `PersistedSession` 转换为临时 `AgentSession` 供 `AgentDrawerPanel` 渲染：

```swift
extension PersistedSession {
    func toAgentSession(definition: AgentDefinition) -> AgentSession {
        var s = AgentSession(
            id: id, surfaceId: UUID(),   // 临时 surfaceId，不注册到 SessionManager
            definition: definition,
            workspaceId: workspaceId,
            cwd: cwd
        )
        s.state = .done(exitCode: 0)
        s.claudeSessionId = claudeSessionId
        s.startedAt = startedAt
        s.tokenUsage = tokenUsage
        // 将 PersistedSubagent 还原为 SubagentInfo（只有摘要数据，不含 toolCalls 列表）
        s.subagents = Dictionary(uniqueKeysWithValues: subagents.map { ps in
            var sub = SubagentInfo(id: ps.id, name: ps.name, agentType: ps.agentType)
            sub.agentId = ps.agentId
            sub.startedAt = ps.startedAt
            sub.finishedAt = ps.finishedAt
            sub.state = ps.exitCode != nil ? .done(exitCode: ps.exitCode!) : .done(exitCode: 0)
            sub.output = ps.output
            // toolCalls 为空：历史记录只展示摘要，Trace Tab 显示「(N tool calls)」文本而非列表
            return (ps.id, sub)
        })
        return s
    }
}
```

历史 Overview 中：Trace Tab 显示「此会话共调用工具 N 次（历史记录不保留详情）」；Messages Tab 仍可读取 JSONL 文件（若文件存在）。

### 读取与 UI 呈现

`AgentMonitorViewModel` 新增 `historicalSessions: [PersistedSession]`，**懒加载**：
- 当用户点开 HISTORY section 时（或当前 workspace 无活跃 session 时自动展开）才调用 `SessionStore.shared.load(for:)`
- 每次加载最多取 **20 条**（按 finishedAt 降序），避免内存占用
- 不实现翻页（历史较长时只看最近 20 个即可）

`AgentMonitorPanel` 在活跃 session 列表后增加 **HISTORY** section：
- 仅在有历史记录时显示，默认折叠，点击展开
- 每行：done 状态图标 + agentName + cost + finishedAt（相对时间：「2h ago」）
- 点击 → `AgentDrawerPanel` SessionOverview（只读，通过 `toAgentSession` 构建）

### SessionStore 目录管理

`SessionStore.save` 负责创建 `sessions/` 子目录（若不存在）：
```swift
let dir = (workspaceDir as NSString).appendingPathComponent("sessions")
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
```
无需修改 `WorkspaceManager`。

### 新增文件

- `macos/Sources/Features/Agent/Monitor/SessionStore.swift`

### 变更文件

- `AgentSessionManager.swift`：sessionEnd 时调用 `SessionStore.shared.save`
- `AgentMonitorViewModel.swift`：加载 `historicalSessions`
- `AgentMonitorPanel.swift`：渲染 HISTORY section

---

## 实现顺序

| 步骤 | Feature | 复杂度 | 变更量 |
|------|---------|--------|--------|
| 1 | F4 Poller 频率 | 极低 | 2 行 |
| 2 | F2 工具气泡 | 低 | 1 文件 |
| 3 | F3 EventLog | 低 | 1 文件 |
| 4 | F1 实时 Token | 中 | 2 文件 |
| 5 | F5 Session 持久化 | 高 | 1 新增 + 3 变更 |

步骤 1-3 互相独立，步骤 4 依赖 TokenTracker 已理解路径推导，步骤 5 独立。

---

## 测试策略

- **F1**：单测 `TokenTracker.pollLiveTokens` 节流逻辑；集成验证 session 运行期间 cost 更新
- **F2**：UI 快照或手动验证 active subagent 行工具名显示
- **F3**：单测 `recentEvents` 计算属性（排序、截断 50 条）
- **F4**：无单测，手动验证 Messages/Trace Tab 刷新延迟降低
- **F5**：单测 `SessionStore.save/load` 往返；集成验证 restart 后 HISTORY section 显示

---

## 不在范围内

- 动画效果（明确排除）
- subagent 之间的父子关系图谱（已有 AgentGraphView）
- WebSocket 实时推送（Poltertty 用 hook + polling，无需 server）
- JSONL replay / 时间轴回放
