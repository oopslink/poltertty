# Agent Monitor Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Agent Monitor 添加 5 项可观测性改进：实时 Token 显示、工具气泡、全局活动流、更快刷新频率、Session 历史持久化。

**Architecture:** 纯增量修改，不重构现有代码。F1-F4 为独立 UI/数据扩展；F5 新增 `SessionStore` 单例负责序列化，通过 `AgentMonitorViewModel.historicalSessions` 暴露给 UI。`PersistedSession.toAgentSession()` 负责只读 Overview 的数据桥接。

**Tech Stack:** Swift 6, SwiftUI, Swift Testing (`@Suite`/`@Test`/`#expect`), Foundation

---

## 文件变更清单

| 操作 | 文件 | 说明 |
|------|------|------|
| Modify | `macos/Sources/Features/Agent/Monitor/SubagentMessagesView.swift` | F4: Timer 3s→1s |
| Modify | `macos/Sources/Features/Agent/Monitor/SubagentTraceContent.swift` | F4: Timer 3s→1s |
| Modify | `macos/Sources/Features/Agent/Monitor/AgentSessionGroup.swift` | F2: 工具气泡 |
| Modify | `macos/Sources/Features/Agent/Monitor/SessionOverviewContent.swift` | F3: EventLog section |
| Modify | `macos/Sources/Features/Agent/TokenTracker/TokenTracker.swift` | F1: pollLiveTokens + 节流 |
| Modify | `macos/Sources/Features/Agent/AgentSessionManager.swift` | F1: postToolUse 调用 poll；F5: sessionEnd 写盘 |
| Create | `macos/Sources/Features/Agent/Monitor/SessionStore.swift` | F5: PersistedSession + SessionStore |
| Modify | `macos/Sources/Features/Agent/Monitor/AgentMonitorViewModel.swift` | F5: historicalSessions |
| Modify | `macos/Sources/Features/Agent/Monitor/AgentMonitorPanel.swift` | F5: HISTORY section UI |
| Modify | `macos/Sources/Features/Agent/AgentSession.swift` | F5: SubagentInfo 添加 isHistorical 标记 |
| Modify | `macos/Tests/Ghostty/SubagentTranscriptReaderTests.swift` | F3: recentEvents 测试（新 Suite） |
| Create | `macos/Tests/Ghostty/TokenTrackerThrottleTests.swift` | F1: 节流逻辑测试 |
| Create | `macos/Tests/Ghostty/SessionStoreTests.swift` | F5: save/load/toAgentSession 测试 |

---

## Task 1: F4 — Transcript Poller 频率 3s → 1s

**Files:**
- Modify: `macos/Sources/Features/Agent/Monitor/SubagentMessagesView.swift:11`
- Modify: `macos/Sources/Features/Agent/Monitor/SubagentTraceContent.swift:7`

- [ ] **Step 1: 修改 SubagentMessagesView Timer**

在 `SubagentMessagesView.swift` 第 11 行：
```swift
// 改前
private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
// 改后
private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
```

- [ ] **Step 2: 修改 SubagentTraceContent Timer**

在 `SubagentTraceContent.swift` 第 7 行同样修改：
```swift
private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
```

- [ ] **Step 3: 编译验证**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty/.worktrees/workspace-ai-agent
make check
```
Expected: 编译通过，无错误

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Agent/Monitor/SubagentMessagesView.swift \
        macos/Sources/Features/Agent/Monitor/SubagentTraceContent.swift
git commit -m "feat: reduce transcript poller interval from 3s to 1s for active subagents"
```

---

## Task 2: F2 — 工具调用气泡（Active Tool Bubble）

**Files:**
- Modify: `macos/Sources/Features/Agent/Monitor/AgentSessionGroup.swift:60-82`

- [ ] **Step 1: 在 subagentRow 中添加工具气泡**

在 `AgentSessionGroup.swift` 的 `subagentRow` 函数中，找到：
```swift
        .padding(.leading, 20).padding(.trailing, 10).padding(.vertical, 3)
```
上方的 `HStack` 内，在 `Spacer()` 和 `elapsedLabel` 之间插入：

```swift
// 当前正在执行的工具（active 时显示）
if sub.state.isActive,
   let activeTool = sub.toolCalls.last(where: { !$0.isDone }) {
    Text(String(activeTool.toolName.prefix(12)))
        .font(.system(size: 8))
        .foregroundStyle(.orange)
        .lineLimit(1)
}
```

完整 `subagentRow` 函数的 HStack 内容变为：
```swift
HStack(spacing: 4) {
    AgentStateDot(state: sub.state)
    Text(sub.name)
        .font(.system(size: 9))
        .foregroundStyle(isSelected ? (Color(hex: "#90bfff") ?? .blue) : .secondary)
        .lineLimit(1).truncationMode(.tail)
    Spacer()
    // F2: 工具气泡
    if sub.state.isActive,
       let activeTool = sub.toolCalls.last(where: { !$0.isDone }) {
        Text(String(activeTool.toolName.prefix(12)))
            .font(.system(size: 8))
            .foregroundStyle(.orange)
            .lineLimit(1)
    }
    Text(elapsedLabel(sub))
        .font(.system(size: 8, design: .monospaced))
        .foregroundStyle(isSelected ? (Color(hex: "#4a6a99") ?? Color(.tertiaryLabelColor)) : Color(.tertiaryLabelColor))
}
```

- [ ] **Step 2: 编译验证**

```bash
make check
```
Expected: 编译通过

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Agent/Monitor/AgentSessionGroup.swift
git commit -m "feat: show active tool name in subagent sidebar row (F2 tool bubble)"
```

---

## Task 3: F3 — 全局 EventLog（跨 Subagent 活动流）

**Files:**
- Modify: `macos/Sources/Features/Agent/Monitor/SessionOverviewContent.swift`
- Modify: `macos/Tests/Ghostty/SubagentTranscriptReaderTests.swift`（新增独立 Suite）

- [ ] **Step 1: 在测试文件末尾新增 EventEntry 相关测试**

在 `SubagentTranscriptReaderTests.swift` 文件末尾（最后一个 `}` 前）添加新的 Suite：

```swift
// MARK: - EventEntry helpers（测试 recentEvents 逻辑，不依赖 SwiftUI）

@Suite
struct EventEntryTests {

    @Test func recentEvents_sortedDescending() {
        // 构造两个 subagent，各含若干 toolCalls
        var sub1 = SubagentInfo(id: "s1", name: "researcher", agentType: "agent")
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 2000)
        sub1.toolCalls = [
            ToolCallRecord(id: "tc1", toolName: "Read",   isDone: true,  startedAt: t1),
            ToolCallRecord(id: "tc2", toolName: "Write",  isDone: false, startedAt: t2),
        ]
        var sub2 = SubagentInfo(id: "s2", name: "coder", agentType: "agent")
        let t3 = Date(timeIntervalSince1970: 1500)
        sub2.toolCalls = [
            ToolCallRecord(id: "tc3", toolName: "Bash", isDone: true, startedAt: t3),
        ]
        let subagents: [String: SubagentInfo] = ["s1": sub1, "s2": sub2]
        let events = makeRecentEvents(subagents: subagents, limit: 50)
        // 降序：t2(2000) > t3(1500) > t1(1000)
        #expect(events.count == 3)
        #expect(events[0].toolName == "Write")
        #expect(events[1].toolName == "Bash")
        #expect(events[2].toolName == "Read")
    }

    @Test func recentEvents_truncatesToLimit() {
        var sub = SubagentInfo(id: "s1", name: "worker", agentType: "agent")
        sub.toolCalls = (0..<60).map { i in
            ToolCallRecord(id: "tc\(i)", toolName: "Tool\(i)", isDone: true,
                           startedAt: Date(timeIntervalSince1970: Double(i)))
        }
        let events = makeRecentEvents(subagents: ["s1": sub], limit: 50)
        #expect(events.count == 50)
        // 降序，最大时间戳（59）应排第一
        #expect(events[0].toolName == "Tool59")
    }

    // 辅助函数（镜像 SessionOverviewContent 中的 recentEvents 逻辑，便于纯函数测试）
    private func makeRecentEvents(subagents: [String: SubagentInfo], limit: Int) -> [RecentEventEntry] {
        subagents.values
            .flatMap { sub in sub.toolCalls.map { call in
                RecentEventEntry(time: call.startedAt,
                                 subagentName: String(sub.name.prefix(10)),
                                 toolName: call.toolName,
                                 isDone: call.isDone)
            }}
            .sorted { $0.time > $1.time }
            .prefix(limit)
            .map { $0 }
    }
}
```

- [ ] **Step 2: 运行测试确认失败（RecentEventEntry 尚未定义）**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty/.worktrees/workspace-ai-agent
make check
```
Expected: 编译错误 `cannot find type 'RecentEventEntry'`

- [ ] **Step 3: 在 SessionOverviewContent.swift 中添加 RecentEventEntry 和 eventLogSection**

在 `SessionOverviewContent.swift` 顶部（`import SwiftUI` 后）添加：

```swift
/// 跨 subagent 全局工具调用事件（供 Overview ActivityLog 使用）
struct RecentEventEntry {
    let time: Date
    let subagentName: String
    let toolName: String
    let isDone: Bool
}
```

在 `SessionOverviewContent` struct 内添加计算属性：

```swift
private var recentEvents: [RecentEventEntry] {
    session.subagents.values
        .flatMap { sub in sub.toolCalls.map { call in
            RecentEventEntry(time: call.startedAt,
                             subagentName: String(sub.name.prefix(10)),
                             toolName: call.toolName,
                             isDone: call.isDone)
        }}
        .sorted { $0.time > $1.time }
        .prefix(50)
        .map { $0 }
}
```

在 `body` 中的 `AgentGraphView` block 之前（`if !session.subagents.isEmpty` 那个 block 后面），追加 eventLog section：

```swift
// MARK: - Activity Log
let events = recentEvents
if !events.isEmpty {
    Divider().padding(.vertical, 6)
    Text("ACTIVITY")
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.tertiary)
        .padding(.bottom, 4)
    eventLogSection(events)
}
```

并添加 `eventLogSection` 视图函数：

```swift
private func eventLogSection(_ events: [RecentEventEntry]) -> some View {
    let fmt = DateFormatter()
    fmt.dateFormat = "HH:mm:ss"
    let total = session.subagents.values.flatMap { $0.toolCalls }.count
    return VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(events.enumerated()), id: \.offset) { _, ev in
            HStack(spacing: 4) {
                Text(fmt.string(from: ev.time))
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                    .frame(width: 54, alignment: .leading)
                Text(ev.subagentName)
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
                    .lineLimit(1).truncationMode(.tail)
                Text(ev.toolName)
                    .font(.system(size: 9)).foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                if ev.isDone {
                    Text("✓").font(.system(size: 9)).foregroundStyle(Color(hex: "#4caf50") ?? .green)
                } else {
                    Text("⏳").font(.system(size: 9)).foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 1)
        }
        if total > 50 {
            Text("… and \(total - 50) more")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
make check
```
Expected: 编译通过（Swift Testing 测试在 `make check` 时不运行，只验证编译）

在 Xcode 中运行 `EventEntryTests` suite 确认两个测试均 PASS。

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Agent/Monitor/SessionOverviewContent.swift \
        macos/Tests/Ghostty/SubagentTranscriptReaderTests.swift
git commit -m "feat: add global activity log to session overview (F3 EventLog)"
```

---

## Task 4: F1 — 实时 Token 累计（Live Token Polling）

**Files:**
- Modify: `macos/Sources/Features/Agent/TokenTracker/TokenTracker.swift`
- Modify: `macos/Sources/Features/Agent/AgentSessionManager.swift`
- Modify: `macos/Sources/Features/Agent/Monitor/SessionOverviewContent.swift`
- Create: `macos/Tests/Ghostty/TokenTrackerThrottleTests.swift`

- [ ] **Step 1: 编写节流逻辑测试**

创建 `macos/Tests/Ghostty/TokenTrackerThrottleTests.swift`：

```swift
import Testing
import Foundation
@testable import Ghostty

@Suite
struct TokenTrackerThrottleTests {

    @Test func throttle_allowsFirstPoll() {
        var lastPollDates: [UUID: Date] = [:]
        let id = UUID()
        let now = Date()
        let shouldPoll = Self.checkThrottle(id: id, lastPollDates: &lastPollDates,
                                            now: now, interval: 5)
        #expect(shouldPoll == true)
        #expect(lastPollDates[id] != nil)
    }

    @Test func throttle_blocksWithinInterval() {
        var lastPollDates: [UUID: Date] = [:]
        let id = UUID()
        let t0 = Date(timeIntervalSince1970: 1000)
        let t1 = Date(timeIntervalSince1970: 1003)  // 3s 后，< 5s
        _ = Self.checkThrottle(id: id, lastPollDates: &lastPollDates, now: t0, interval: 5)
        let shouldPoll = Self.checkThrottle(id: id, lastPollDates: &lastPollDates,
                                            now: t1, interval: 5)
        #expect(shouldPoll == false)
    }

    @Test func throttle_allowsAfterInterval() {
        var lastPollDates: [UUID: Date] = [:]
        let id = UUID()
        let t0 = Date(timeIntervalSince1970: 1000)
        let t1 = Date(timeIntervalSince1970: 1006)  // 6s 后，> 5s
        _ = Self.checkThrottle(id: id, lastPollDates: &lastPollDates, now: t0, interval: 5)
        let shouldPoll = Self.checkThrottle(id: id, lastPollDates: &lastPollDates,
                                            now: t1, interval: 5)
        #expect(shouldPoll == true)
    }

    // 镜像 TokenTracker 内部节流逻辑，供纯函数测试
    static func checkThrottle(id: UUID, lastPollDates: inout [UUID: Date],
                               now: Date, interval: TimeInterval) -> Bool {
        if let last = lastPollDates[id], now.timeIntervalSince(last) < interval {
            return false
        }
        lastPollDates[id] = now
        return true
    }
}
```

- [ ] **Step 2: 运行测试确认通过**

在 Xcode 中运行 `TokenTrackerThrottleTests`，确认 3 个测试均 PASS（这些是纯函数测试，无需 `TokenTracker` 实现）。

- [ ] **Step 3: 在 TokenTracker 中添加 pollLiveTokens**

在 `TokenTracker.swift` 中添加：

1. 节流字典（在 `init` 之前）：
```swift
private var lastPollDates: [UUID: Date] = [:]
private static let pollInterval: TimeInterval = 5
```

2. 路径推导辅助函数（私有）：
```swift
private func liveTranscriptPath(for session: AgentSession) -> String? {
    guard let claudeSessionId = session.claudeSessionId else { return nil }
    let sanitized = SubagentTranscriptReader.sanitizeCwd(session.cwd)
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return "\(home)/.claude/projects/\(sanitized)/\(claudeSessionId).jsonl"
}
```

3. `pollLiveTokens` 方法（在 `processStopEvent` 之后）：
```swift
/// 节流轮询主 session transcript，在 postToolUse 和 Overview 3s timer 时调用
func pollLiveTokens(surfaceId: UUID) {
    let now = Date()
    if let last = lastPollDates[surfaceId],
       now.timeIntervalSince(last) < Self.pollInterval { return }
    lastPollDates[surfaceId] = now

    guard let session = sessionManager.session(for: surfaceId),
          let path = liveTranscriptPath(for: session) else { return }
    let model = session.definition.command == "claude" ? "claude-sonnet-4" : "claude-sonnet-4"

    Task.detached(priority: .utility) { [weak self] in
        let usage = await self?.parseTranscript(at: path, model: model) ?? TokenUsage()
        guard usage.totalTokens > 0 else { return }
        await MainActor.run {
            self?.sessionManager.updateTokenUsage(surfaceId: surfaceId, usage: usage)
        }
    }
}
```

- [ ] **Step 4: 在 AgentSessionManager.postToolUse 调用 pollLiveTokens**

在 `AgentSessionManager.swift` 的 `.postToolUse` case 末尾（`if payload.toolName == "Agent"` block 之後，case 结束前）添加。
注意：这段代码在 `processHookEvent` 方法**内部**，`claudeSessionIndex` 是私有成员，此处可以直接访问：

```swift
// F1: 实时 token 轮询（代码在 AgentSessionManager 内部，claudeSessionIndex 可直接访问）
if let surfaceId = claudeSessionIndex[sid] {
    AgentService.shared.tokenTracker?.pollLiveTokens(surfaceId: surfaceId)
}
```

同时在 `remove(surfaceId:)` 方法中清理节流字典，防止内存积累。在 `remove` 方法末尾添加：
```swift
AgentService.shared.tokenTracker?.clearThrottle(surfaceId: surfaceId)
```

并在 `TokenTracker.swift` 中添加对应的 `clearThrottle` 方法：
```swift
func clearThrottle(surfaceId: UUID) {
    lastPollDates.removeValue(forKey: surfaceId)
}
```

- [ ] **Step 5: SessionOverviewContent 的 timer 也调用 pollLiveTokens**

在 `SessionOverviewContent.swift` 中，找到 `.onReceive(timer)` 修改为：

```swift
.onReceive(timer) { t in
    if session.state.isActive {
        tick = t
        // F1: 保底 token 更新（仅 active session；历史 session 的 isActive==false，不会触发）
        // AgentSession.surfaceId 是公开字段，通过 sessions 字典查找
        if let surfaceId = AgentService.shared.sessionManager.sessions.values
                .first(where: { $0.claudeSessionId == session.claudeSessionId })?.surfaceId {
            AgentService.shared.tokenTracker?.pollLiveTokens(surfaceId: surfaceId)
        }
    }
}
```

此查找仅对 active session 有效（`session.state.isActive == true`），历史 session 的状态为 `.done`，timer 回调不会触发 poll。

- [ ] **Step 6: 编译验证**

```bash
make check
```
Expected: 编译通过

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/Features/Agent/TokenTracker/TokenTracker.swift \
        macos/Sources/Features/Agent/AgentSessionManager.swift \
        macos/Sources/Features/Agent/Monitor/SessionOverviewContent.swift \
        macos/Tests/Ghostty/TokenTrackerThrottleTests.swift
git commit -m "feat: live token polling during active sessions (F1 real-time token accumulation)"
```

---

## Task 5: F5 — Session 持久化（SessionStore）

### Task 5a: 为 SubagentInfo 添加 isHistorical 标记

**Files:**
- Modify: `macos/Sources/Features/Agent/AgentSession.swift`

- [ ] **Step 1: SubagentInfo 添加 isHistorical 字段**

在 `AgentSession.swift` 的 `SubagentInfo` struct 中添加一个标记字段：

```swift
var isHistorical: Bool = false   // 由 PersistedSession.toAgentSession() 设置，标识只读历史记录
```

- [ ] **Step 2: 编译验证**

```bash
make check
```
Expected: 编译通过（新字段有默认值，无需修改现有构造调用）

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Agent/AgentSession.swift
git commit -m "feat: add isHistorical flag to SubagentInfo for read-only history mode"
```

---

### Task 5b: 创建 SessionStore + PersistedSession

**Files:**
- Create: `macos/Sources/Features/Agent/Monitor/SessionStore.swift`
- Create: `macos/Tests/Ghostty/SessionStoreTests.swift`

- [ ] **Step 1: 编写测试**

创建 `macos/Tests/Ghostty/SessionStoreTests.swift`：

```swift
import Testing
import Foundation
@testable import Ghostty

@Suite
struct SessionStoreTests {

    // 使用临时目录隔离测试
    private func makeTempStore() -> (SessionStore, URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("poltertty-test-\(UUID())")
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return (SessionStore(baseDir: tmp.path), tmp)
    }

    @Test func saveAndLoad_roundTrip() throws {
        let (store, tmp) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let wsId = UUID()
        let ps = PersistedSession(
            id: UUID(),
            workspaceId: wsId,
            definitionId: "claude-code",
            agentName: "Claude Code",
            agentCommand: "claude",
            agentIcon: "◆",
            cwd: "/Users/test/project",
            claudeSessionId: "sess-abc",
            startedAt: Date(timeIntervalSince1970: 1000),
            finishedAt: Date(timeIntervalSince1970: 2000),
            tokenUsage: TokenUsage(),
            subagents: []
        )
        store.save(ps)

        let loaded = store.load(for: wsId)
        #expect(loaded.count == 1)
        #expect(loaded[0].id == ps.id)
        #expect(loaded[0].claudeSessionId == "sess-abc")
        #expect(loaded[0].cwd == "/Users/test/project")
    }

    @Test func load_returnsDescendingByFinishedAt() throws {
        let (store, tmp) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let wsId = UUID()
        let older = makeSession(wsId: wsId, finishedAt: Date(timeIntervalSince1970: 1000))
        let newer = makeSession(wsId: wsId, finishedAt: Date(timeIntervalSince1970: 2000))
        store.save(older)
        store.save(newer)

        let loaded = store.load(for: wsId)
        #expect(loaded.count == 2)
        #expect(loaded[0].finishedAt > loaded[1].finishedAt)  // newer first
    }

    @Test func load_limitsTo20() throws {
        let (store, tmp) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let wsId = UUID()
        for i in 0..<25 {
            store.save(makeSession(wsId: wsId, finishedAt: Date(timeIntervalSince1970: Double(i * 100))))
        }
        let loaded = store.load(for: wsId)
        #expect(loaded.count == 20)
    }

    @Test func toAgentSession_mapsFieldsCorrectly() {
        let wsId = UUID()
        let sub = PersistedSubagent(
            id: "sub-1", name: "researcher", agentType: "agent", agentId: "aid-1",
            startedAt: Date(timeIntervalSince1970: 100),
            finishedAt: Date(timeIntervalSince1970: 200),
            exitCode: 0, toolCallCount: 5, output: "done"
        )
        let ps = PersistedSession(
            id: UUID(), workspaceId: wsId, definitionId: "claude-code",
            agentName: "Claude Code", agentCommand: "claude", agentIcon: "◆",
            cwd: "/tmp", claudeSessionId: "sess-xyz",
            startedAt: Date(timeIntervalSince1970: 0),
            finishedAt: Date(timeIntervalSince1970: 300),
            tokenUsage: TokenUsage(), subagents: [sub]
        )
        let session = ps.toAgentSession()
        #expect(session.cwd == "/tmp")
        #expect(session.claudeSessionId == "sess-xyz")
        if case .done(let code) = session.state { #expect(code == 0) }
        else { Issue.record("Expected .done state") }
        #expect(session.subagents.count == 1)
        let restoredSub = session.subagents["sub-1"]!
        #expect(restoredSub.name == "researcher")
        #expect(restoredSub.output == "done")
    }

    // MARK: - Helpers
    private func makeSession(wsId: UUID, finishedAt: Date) -> PersistedSession {
        PersistedSession(
            id: UUID(), workspaceId: wsId, definitionId: "claude-code",
            agentName: "Claude Code", agentCommand: "claude", agentIcon: "◆",
            cwd: "/tmp", claudeSessionId: nil,
            startedAt: finishedAt.addingTimeInterval(-60),
            finishedAt: finishedAt,
            tokenUsage: TokenUsage(), subagents: []
        )
    }
}
```

- [ ] **Step 2: 运行测试确认失败（SessionStore 尚未存在）**

```bash
make check
```
Expected: 编译错误

- [ ] **Step 3: 创建 SessionStore.swift**

创建 `macos/Sources/Features/Agent/Monitor/SessionStore.swift`：

```swift
// macos/Sources/Features/Agent/Monitor/SessionStore.swift
import Foundation
import OSLog

// MARK: - Data Models

struct PersistedSession: Codable, Identifiable {
    let id: UUID
    let workspaceId: UUID
    let definitionId: String      // 用于 UI 标识
    let agentName: String
    let agentCommand: String      // 保留 command 避免 AgentRegistry 查找失败时信息丢失
    let agentIcon: String         // 保留 icon
    let cwd: String
    let claudeSessionId: String?
    let startedAt: Date
    let finishedAt: Date
    var tokenUsage: TokenUsage
    let subagents: [PersistedSubagent]
}

struct PersistedSubagent: Codable, Identifiable {
    let id: String
    let name: String
    let agentType: String
    let agentId: String?
    let startedAt: Date
    let finishedAt: Date?
    let exitCode: Int32?
    let toolCallCount: Int
    let output: String?
}

// MARK: - AgentSession → PersistedSession 转换

extension AgentSession {
    func toPersistedSession() -> PersistedSession? {
        // 只持久化已完成的 session
        guard case .done = state,
              let finishedAt = subagents.values.map({ $0.finishedAt ?? lastEventAt }).max()
                              ?? Optional(lastEventAt) else { return nil }
        let persistedSubs = subagents.values.map { sub -> PersistedSubagent in
            let exitCode: Int32? = {
                if case .done(let code) = sub.state { return code }
                return nil
            }()
            return PersistedSubagent(
                id: sub.id, name: sub.name, agentType: sub.agentType,
                agentId: sub.agentId,
                startedAt: sub.startedAt, finishedAt: sub.finishedAt,
                exitCode: exitCode,
                toolCallCount: sub.toolCalls.count,
                output: sub.output
            )
        }.sorted { $0.startedAt < $1.startedAt }

        return PersistedSession(
            id: id, workspaceId: workspaceId,
            definitionId: definition.id, agentName: definition.name,
            agentCommand: definition.command, agentIcon: definition.icon,
            cwd: cwd, claudeSessionId: claudeSessionId,
            startedAt: startedAt, finishedAt: lastEventAt,
            tokenUsage: tokenUsage, subagents: persistedSubs
        )
    }
}

// MARK: - PersistedSession → AgentSession 转换（只读 Overview）

extension PersistedSession {
    /// 注意：此方法直接用保存的 command/icon 构建 AgentDefinition，无需访问 @MainActor AgentRegistry
    func toAgentSession() -> AgentSession {
        let def = AgentDefinition(id: definitionId, name: agentName,
                                  command: agentCommand, icon: agentIcon, hookCapability: .full)
        var s = AgentSession(
            id: id, surfaceId: UUID(),
            definition: def, workspaceId: workspaceId, cwd: cwd
        )
        s.state = .done(exitCode: 0)
        s.claudeSessionId = claudeSessionId
        s.startedAt = startedAt
        s.lastEventAt = finishedAt
        s.tokenUsage = tokenUsage
        s.subagents = Dictionary(uniqueKeysWithValues: subagents.map { ps in
            var sub = SubagentInfo(id: ps.id, name: ps.name, agentType: ps.agentType)
            sub.agentId = ps.agentId
            sub.startedAt = ps.startedAt
            sub.finishedAt = ps.finishedAt
            sub.state = ps.exitCode != nil ? .done(exitCode: ps.exitCode!) : .done(exitCode: 0)
            sub.output = ps.output
            sub.isHistorical = true    // 标记为只读历史记录，供 TraceContent 检测
            return (ps.id, sub)
        })
        return s
    }
}

// MARK: - SessionStore

final class SessionStore {
    static let shared = SessionStore()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "poltertty",
                                category: "SessionStore")
    private let baseDir: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// 生产环境使用 WorkspaceManager 路径；测试时可注入临时目录
    init(baseDir: String = PolterttyConfig.shared.workspaceDir) {
        self.baseDir = baseDir
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Public API

    func save(_ session: AgentSession) {
        guard let ps = session.toPersistedSession() else { return }
        save(ps)
    }

    func save(_ ps: PersistedSession) {
        let dir = sessionsDir(for: ps.workspaceId)
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let path = sessionPath(dir: dir, id: ps.id)
            let data = try encoder.encode(ps)
            let tmp = path + ".tmp"
            try data.write(to: URL(fileURLWithPath: tmp))
            try FileManager.default.moveItem(atPath: tmp, toPath: path)
        } catch {
            logger.error("SessionStore.save failed: \(error)")
        }
    }

    /// 读取最近 20 条，按 finishedAt 降序
    func load(for workspaceId: UUID) -> [PersistedSession] {
        let dir = sessionsDir(for: workspaceId)
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return files
            .filter { $0.hasSuffix(".json") && !$0.hasSuffix(".tmp") }
            .compactMap { name -> PersistedSession? in
                let path = (dir as NSString).appendingPathComponent(name)
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
                return try? decoder.decode(PersistedSession.self, from: data)
            }
            .sorted { $0.finishedAt > $1.finishedAt }
            .prefix(20)
            .map { $0 }
    }

    // MARK: - Private

    private func sessionsDir(for workspaceId: UUID) -> String {
        let wsDir = (baseDir as NSString).appendingPathComponent(workspaceId.uuidString)
        return (wsDir as NSString).appendingPathComponent("sessions")
    }

    private func sessionPath(dir: String, id: UUID) -> String {
        (dir as NSString).appendingPathComponent("\(id.uuidString).json")
    }
}
```

- [ ] **Step 4: 编译并运行测试**

```bash
make check
```
Expected: 编译通过

在 Xcode 中运行 `SessionStoreTests`，确认 4 个测试均 PASS。

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Agent/Monitor/SessionStore.swift \
        macos/Tests/Ghostty/SessionStoreTests.swift
git commit -m "feat: add SessionStore and PersistedSession model (F5 session persistence)"
```

---

### Task 5b: 集成写盘 + UI 展示

**Files:**
- Modify: `macos/Sources/Features/Agent/AgentSessionManager.swift`
- Modify: `macos/Sources/Features/Agent/Monitor/AgentMonitorViewModel.swift`
- Modify: `macos/Sources/Features/Agent/Monitor/AgentMonitorPanel.swift`

- [ ] **Step 1: AgentSessionManager sessionEnd 时写盘**

在 `AgentSessionManager.swift` 的 `.sessionEnd` case 中，在 `updateFromClaudeSession` 之后追加：

```swift
// F5: 持久化到磁盘
if let surfaceId = claudeSessionIndex[sid],
   let session = sessions[surfaceId] {
    let snap = session  // 值拷贝，避免后续修改竞争
    Task.detached(priority: .utility) {
        SessionStore.shared.save(snap)
    }
}
```

- [ ] **Step 2: AgentMonitorViewModel 添加 historicalSessions**

在 `AgentMonitorViewModel.swift` 中添加：

```swift
@Published private(set) var historicalSessions: [PersistedSession] = []
@Published var historyExpanded: Bool = false

func loadHistory() {
    let wid = workspaceId
    Task.detached(priority: .utility) { [weak self] in
        let sessions = SessionStore.shared.load(for: wid)
        await MainActor.run { self?.historicalSessions = sessions }
    }
}

func toggleHistory() {
    historyExpanded.toggle()
    if historyExpanded { loadHistory() }
}

/// 点击历史 session → 在 Drawer 中显示只读 Overview
func selectHistory(_ ps: PersistedSession) {
    let session = ps.toAgentSession()
    selectedItems = [.sessionOverview(session)]
}
```

- [ ] **Step 3: AgentMonitorPanel 添加 HISTORY section**

在 `AgentMonitorPanel.swift` 的 `body` 中，在 `ForEach(viewModel.sessions)` 之后，`}` (ScrollView 关闭) 之前添加：

```swift
// F5: 历史 session
if !viewModel.historicalSessions.isEmpty || viewModel.historyExpanded {
    historySectionView
}
```

在 `AgentMonitorPanel` 中新增计算属性：

```swift
private var historySectionView: some View {
    VStack(alignment: .leading, spacing: 0) {
        // 折叠/展开 header
        Button(action: { viewModel.toggleHistory() }) {
            HStack(spacing: 4) {
                Image(systemName: viewModel.historyExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8)).foregroundStyle(.tertiary)
                Text("HISTORY")
                    .font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .onAppear { viewModel.loadHistory() }

        if viewModel.historyExpanded {
            ForEach(viewModel.historicalSessions) { ps in
                historyRow(ps)
            }
        }
    }
    .background(Color(.windowBackgroundColor))
}

private func historyRow(_ ps: PersistedSession) -> some View {
    Button(action: {
        viewModel.isVisible = true
        viewModel.selectHistory(ps)
    }) {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 8)).foregroundStyle(Color(hex: "#4caf50") ?? .green)
            Text(ps.agentName)
                .font(.system(size: 9)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail)
            Spacer()
            let cost = NSDecimalNumber(decimal: ps.tokenUsage.cost).doubleValue
            if cost > 0 {
                Text(String(format: "$%.2f", cost))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(Color(hex: "#4caf50") ?? .green)
            }
            Text(relativeTime(ps.finishedAt))
                .font(.system(size: 8, design: .monospaced)).foregroundStyle(.tertiary)
        }
        .padding(.leading, 18).padding(.trailing, 10).padding(.vertical, 3)
    }
    .buttonStyle(.plain)
}

private func relativeTime(_ date: Date) -> String {
    let secs = Int(Date().timeIntervalSince(date))
    if secs < 3600  { return "\(secs / 60)m" }
    if secs < 86400 { return "\(secs / 3600)h" }
    return "\(secs / 86400)d"
}
```

- [ ] **Step 4: SubagentTraceContent 历史模式显示摘要**

在 `SubagentTraceContent.swift` 中找到：

```swift
if subagent.toolCalls.isEmpty {
    Text(subagent.state.isActive ? "等待工具调用…" : "无工具调用记录")
```

修改为（使用 `isHistorical` 标记而非 state+output 组合检测，避免误判正在运行的空 subagent）：

```swift
if subagent.toolCalls.isEmpty {
    if subagent.isHistorical {
        // 历史记录：toolCalls 为空是因为持久化不保留详情（isHistorical 标记由 toAgentSession() 设置）
        Text("历史记录不保留工具调用详情")
            .font(.system(size: 10)).foregroundStyle(.tertiary).padding(12)
        if let output = subagent.output {
            Text("最终输出：")
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            Text(output)
                .font(.system(size: 10)).foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(.horizontal, 12).padding(.top, 4)
        }
    } else {
        Text(subagent.state.isActive ? "等待工具调用…" : "无工具调用记录")
            .font(.system(size: 10)).foregroundStyle(.tertiary).padding(12)
    }
```

- [ ] **Step 5: 编译验证**

```bash
make check
```
Expected: 编译通过

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Agent/AgentSessionManager.swift \
        macos/Sources/Features/Agent/Monitor/AgentMonitorViewModel.swift \
        macos/Sources/Features/Agent/Monitor/AgentMonitorPanel.swift \
        macos/Sources/Features/Agent/Monitor/SubagentTraceContent.swift
git commit -m "feat: session history persistence UI - save on end, show in HISTORY section (F5)"
```

---

## Task 6: 全量构建 & 手动验证

- [ ] **Step 1: 全量构建**

```bash
make dev
```
Expected: 构建成功，无警告/错误

- [ ] **Step 2: 运行所有测试**

在 Xcode 中 ⌘U 运行所有测试，确认：
- `EventEntryTests` (2个) ✓
- `TokenTrackerThrottleTests` (3个) ✓
- `SessionStoreTests` (4个) ✓
- 原有 `SubagentTranscriptReaderTests` (7个) ✓

- [ ] **Step 3: 手动验证清单**

启动 Poltertty dev build（`make run-dev`），启动一个 claude agent：

| 验证项 | 预期结果 |
|--------|----------|
| F2: subagent 行右侧橙色文字 | active subagent 执行工具时显示工具名 |
| F3: Overview 下方 ACTIVITY 区 | 多个 subagent 的工具调用按时间降序排列 |
| F4: Messages Tab 刷新延迟 | 肉眼感觉约 1s 更新一次 |
| F1: Overview Cost 字段 | session 运行期间显示递增的 cost，而非 `—` |
| F5: 重启 app 后 HISTORY section | 上次 session 出现在 HISTORY 中，点击可查看 Overview |

- [ ] **Step 4: 最终 commit**

```bash
git add -u
git commit -m "chore: all 5 agent monitor enhancements complete and verified"
```

---

## 注意事项

- `PolterttyConfig.shared.workspaceDir` 返回 `~/.config/poltertty/workspaces`，`SessionStore` 在此基础上拼接 `{workspaceId}/sessions/`
- `AgentDefinition` 是值类型，`AgentRegistry.shared.definitions` 在 `@MainActor` 上，`toAgentSession()` 在非 main context 调用时需注意；测试中使用 fallback 构造即可
- F1 的 `parseTranscript` 取最后一条含 `usage` 的 message（非累加），与 Stop event 行为一致
- `make check` 只做编译检查，Swift Testing 测试需在 Xcode 中运行
