# Subagent 富信息展示 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Subagent 详情面板的 Output tab 替换为 Messages tab，展示从 JSONL 文件读取的完整对话记录、token 消耗汇总，以及 agentId/sessionId 调试信息。

**Architecture:** 新增 `SubagentTranscriptReader`（纯逻辑，可测试）负责 JSONL 路径派生和解析，新增 `SubagentMessagesView`（SwiftUI）负责展示，`AgentDrawerPanel` 将 "Output" tab 重命名为 "Messages" 并替换为新视图。

**Tech Stack:** Swift 5.9, SwiftUI (macOS 13+), Foundation (FileManager, JSONSerialization), Swift Testing framework

---

## 文件结构

| 操作 | 文件 | 职责 |
|------|------|------|
| 新增 | `macos/Sources/Features/Agent/Monitor/SubagentTranscriptReader.swift` | 路径派生 + JSONL 解析，返回 `SubagentTranscript` |
| 新增 | `macos/Sources/Features/Agent/Monitor/SubagentMessagesView.swift` | Messages tab UI |
| 修改 | `macos/Sources/Features/Agent/Monitor/AgentDrawerPanel.swift` | 重命名 tab、替换 contentArea 视图 |
| 新增 | `macos/Tests/SubagentTranscriptReaderTests.swift` | 单元测试（路径派生 + 解析逻辑） |

---

## Task 1: 数据模型 + SubagentTranscriptReader

**Files:**
- Create: `macos/Sources/Features/Agent/Monitor/SubagentTranscriptReader.swift`
- Create: `macos/Tests/SubagentTranscriptReaderTests.swift`

### 背景知识

JSONL 路径规则：`~/.claude/projects/{sanitized-cwd}/{claudeSessionId}/subagents/agent-{agentId}.jsonl`
- `sanitized-cwd`：将 cwd 的每个 `/` 和空格替换为 `-`，再去掉开头的 `-`
- 例如 `/Users/aaron/my project` → `Users-aaron-my-project`

每行 JSON 的关键字段：
- `type`: `"user"` / `"assistant"` / `"progress"` (progress 跳过)
- `message.role`: `"user"` / `"assistant"`
- `message.content`: content blocks 数组
- `message.usage`: `{input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens}`

content block 类型：
- `{"type": "text", "text": "..."}` — 文字
- `{"type": "tool_use", "id": "...", "name": "...", "input": {...}}` — 工具调用
- `{"type": "tool_result", "tool_use_id": "...", "content": [...]}` — 工具结果，content 是 blocks 数组，只取 text 块拼接

- [ ] **Step 1: 写单元测试（先写测试）**

新建 `macos/Tests/SubagentTranscriptReaderTests.swift`：

```swift
import Testing
import Foundation
@testable import Ghostty

@Suite
struct SubagentTranscriptReaderTests {

    // MARK: - sanitizeCwd

    @Test func sanitize_absolutePath() {
        let result = SubagentTranscriptReader.sanitizeCwd("/Users/aaron/myapp")
        #expect(result == "Users-aaron-myapp")
    }

    @Test func sanitize_pathWithSpaces() {
        let result = SubagentTranscriptReader.sanitizeCwd("/Users/aaron/my project/app")
        #expect(result == "Users-aaron-my-project-app")
    }

    @Test func sanitize_trailingSlash() {
        let result = SubagentTranscriptReader.sanitizeCwd("/Users/aaron/app/")
        #expect(result == "Users-aaron-app-")  // trailing - 保留，与 Claude Code 行为一致
    }

    // MARK: - transcriptPath

    @Test func transcriptPath_returnsNilWhenNoClaudeSessionId() {
        var session = makeSession()
        session.claudeSessionId = nil
        var sub = makeSubagent()
        sub.agentId = "agent-abc"
        let path = SubagentTranscriptReader.transcriptPath(session: session, subagent: sub)
        #expect(path == nil)
    }

    @Test func transcriptPath_returnsNilWhenNoAgentId() {
        var session = makeSession()
        session.claudeSessionId = "sess-123"
        var sub = makeSubagent()
        sub.agentId = nil
        let path = SubagentTranscriptReader.transcriptPath(session: session, subagent: sub)
        #expect(path == nil)
    }

    @Test func transcriptPath_correctPath() {
        var session = makeSession()
        session.claudeSessionId = "sess-123"
        var sub = makeSubagent()
        sub.agentId = "agent-abc"
        let path = SubagentTranscriptReader.transcriptPath(session: session, subagent: sub)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let expected = "\(home)/.claude/projects/Users-aaron-myapp/sess-123/subagents/agent-agent-abc.jsonl"
        #expect(path == expected)
    }

    // MARK: - parseLines

    @Test func parse_skipsProgressLines() {
        let lines = [
            #"{"type":"progress","message":{"role":"assistant","content":[]}}"#,
        ]
        let transcript = SubagentTranscriptReader.parseLines(lines)
        #expect(transcript.turns.isEmpty)
    }

    @Test func parse_textBlock() {
        let lines = [
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hello"}],"usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#
        ]
        let transcript = SubagentTranscriptReader.parseLines(lines)
        #expect(transcript.turns.count == 1)
        #expect(transcript.turns[0].role == .assistant)
        if case .text(let t) = transcript.turns[0].blocks[0] {
            #expect(t == "Hello")
        } else {
            Issue.record("Expected text block")
        }
    }

    @Test func parse_toolUseBlock() {
        let lines = [
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu-1","name":"Read","input":{"file_path":"/foo.swift"}}],"usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#
        ]
        let transcript = SubagentTranscriptReader.parseLines(lines)
        #expect(transcript.turns.count == 1)
        if case .toolUse(let id, let name, _) = transcript.turns[0].blocks[0] {
            #expect(id == "tu-1")
            #expect(name == "Read")
        } else {
            Issue.record("Expected toolUse block")
        }
    }

    @Test func parse_toolResultExtractsText() {
        let lines = [
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tu-1","content":[{"type":"text","text":"file content"},{"type":"text","text":"more"}]}]}}"#
        ]
        let transcript = SubagentTranscriptReader.parseLines(lines)
        #expect(transcript.turns.count == 1)
        if case .toolResult(let tuId, let content) = transcript.turns[0].blocks[0] {
            #expect(tuId == "tu-1")
            #expect(content == "file content\nmore")
        } else {
            Issue.record("Expected toolResult block")
        }
    }

    @Test func parse_accumulatesTokenUsage() {
        let lines = [
            #"{"type":"assistant","message":{"role":"assistant","content":[],"usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":20,"cache_creation_input_tokens":5}}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[],"usage":{"input_tokens":200,"output_tokens":30,"cache_read_input_tokens":0,"cache_creation_input_tokens":10}}}"#
        ]
        let transcript = SubagentTranscriptReader.parseLines(lines)
        #expect(transcript.totalUsage.inputTokens == 300)
        #expect(transcript.totalUsage.outputTokens == 80)
        #expect(transcript.totalUsage.cacheReadTokens == 20)
        #expect(transcript.totalUsage.cacheWriteTokens == 15)
    }

    // MARK: - Helpers

    private func makeSession() -> AgentSession {
        // AgentDefinition 字段：id, name, command, icon, hookCapability（无 args/cwd）
        AgentSession(
            id: UUID(),
            surfaceId: UUID(),
            definition: AgentDefinition(id: "test", name: "test", command: "claude", icon: "◆", hookCapability: .full),
            workspaceId: UUID(),
            cwd: "/Users/aaron/myapp"
        )
    }

    private func makeSubagent() -> SubagentInfo {
        SubagentInfo(id: "sub-1", name: "tester", agentType: "agent")
    }
}
```

- [ ] **Step 2: 运行测试确认全部 FAIL（文件不存在）**

```bash
cd /Users/aaronlin/works/codes/oss/poltertty/.worktrees/workspace-ai-agent/macos
xcodebuild test -workspace Ghostty.xcodeproj/project.xcworkspace -scheme Ghostty -destination 'platform=macOS' -only-testing:GhosttyTests/SubagentTranscriptReaderTests 2>&1 | tail -20
```

预期：编译错误（`SubagentTranscriptReader` 不存在）

- [ ] **Step 3: 实现 SubagentTranscriptReader**

新建 `macos/Sources/Features/Agent/Monitor/SubagentTranscriptReader.swift`：

```swift
// macos/Sources/Features/Agent/Monitor/SubagentTranscriptReader.swift
import Foundation

// MARK: - Data Models

enum TranscriptBlock {
    case text(String)
    case toolUse(id: String, name: String, inputJSON: String)
    case toolResult(toolUseId: String, content: String)
}

struct TurnUsage {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int

    static let zero = TurnUsage(inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0)

    func adding(_ other: TurnUsage) -> TurnUsage {
        TurnUsage(
            inputTokens: inputTokens + other.inputTokens,
            outputTokens: outputTokens + other.outputTokens,
            cacheReadTokens: cacheReadTokens + other.cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens + other.cacheWriteTokens
        )
    }
}

struct TranscriptTurn: Identifiable {
    let id: UUID
    let role: Role
    let blocks: [TranscriptBlock]
    let usage: TurnUsage?
    let timestamp: Date

    enum Role { case user, assistant }
}

struct SubagentTranscript {
    let turns: [TranscriptTurn]
    let totalUsage: TurnUsage
}

// MARK: - Reader

final class SubagentTranscriptReader {

    /// 将 cwd 转换为 Claude Code 使用的目录名：将 / 和空格替换为 -，去掉开头的 -
    static func sanitizeCwd(_ cwd: String) -> String {
        var s = cwd.replacingOccurrences(of: "/", with: "-")
                   .replacingOccurrences(of: " ", with: "-")
        if s.hasPrefix("-") { s = String(s.dropFirst()) }
        return s
    }

    /// 派生 JSONL 文件路径，任意必要字段为 nil 时返回 nil
    static func transcriptPath(session: AgentSession, subagent: SubagentInfo) -> String? {
        guard let claudeSessionId = session.claudeSessionId,
              let agentId = subagent.agentId else { return nil }
        let sanitized = sanitizeCwd(session.cwd)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/projects/\(sanitized)/\(claudeSessionId)/subagents/agent-\(agentId).jsonl"
    }

    /// 从磁盘读取并解析 JSONL，文件不存在时返回 nil
    static func read(session: AgentSession, subagent: SubagentInfo) async -> SubagentTranscript? {
        guard let path = transcriptPath(session: session, subagent: subagent) else { return nil }
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        return parseLines(lines)
    }

    /// 解析 JSONL 行数组（供测试直接调用）
    static func parseLines(_ lines: [String]) -> SubagentTranscript {
        var turns: [TranscriptTurn] = []
        var total = TurnUsage.zero
        let isoFormatter = ISO8601DateFormatter()

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type_ = obj["type"] as? String,
                  type_ != "progress",
                  let message = obj["message"] as? [String: Any],
                  let role = message["role"] as? String else { continue }

            let contentArr = message["content"] as? [[String: Any]] ?? []
            let blocks = contentArr.compactMap { parseBlock($0) }

            let usageObj = message["usage"] as? [String: Any]
            let usage = usageObj.map {
                TurnUsage(
                    inputTokens: $0["input_tokens"] as? Int ?? 0,
                    outputTokens: $0["output_tokens"] as? Int ?? 0,
                    cacheReadTokens: $0["cache_read_input_tokens"] as? Int ?? 0,
                    cacheWriteTokens: $0["cache_creation_input_tokens"] as? Int ?? 0
                )
            }

            let tsStr = obj["timestamp"] as? String ?? ""
            let timestamp = isoFormatter.date(from: tsStr) ?? Date()

            let turnRole: TranscriptTurn.Role = role == "assistant" ? .assistant : .user
            turns.append(TranscriptTurn(id: UUID(), role: turnRole, blocks: blocks, usage: usage, timestamp: timestamp))

            if turnRole == .assistant, let u = usage {
                total = total.adding(u)
            }
        }

        return SubagentTranscript(turns: turns, totalUsage: total)
    }

    // MARK: - Private

    private static func parseBlock(_ block: [String: Any]) -> TranscriptBlock? {
        guard let type_ = block["type"] as? String else { return nil }
        switch type_ {
        case "text":
            guard let text = block["text"] as? String else { return nil }
            return .text(text)
        case "tool_use":
            guard let id = block["id"] as? String,
                  let name = block["name"] as? String else { return nil }
            let inputObj = block["input"] ?? [:]
            let inputData = (try? JSONSerialization.data(withJSONObject: inputObj, options: [.sortedKeys])) ?? Data()
            let inputJSON = String(data: inputData, encoding: .utf8) ?? "{}"
            return .toolUse(id: id, name: name, inputJSON: inputJSON)
        case "tool_result":
            guard let tuId = block["tool_use_id"] as? String else { return nil }
            let contentBlocks = block["content"] as? [[String: Any]] ?? []
            let text = contentBlocks
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
            return .toolResult(toolUseId: tuId, content: text)
        default:
            return nil
        }
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
cd /Users/aaronlin/works/codes/oss/poltertty/.worktrees/workspace-ai-agent/macos
xcodebuild test -workspace Ghostty.xcodeproj/project.xcworkspace -scheme Ghostty -destination 'platform=macOS' -only-testing:GhosttyTests/SubagentTranscriptReaderTests 2>&1 | grep -E "passed|failed|error:"
```

预期：所有测试 PASS

> **注意**：若 `AgentSession` / `SubagentInfo` / `AgentDefinition` 构造器参数不匹配，根据实际定义调整测试中的 `makeSession()` / `makeSubagent()` helper。

- [ ] **Step 5: Commit**

```bash
cd /Users/aaronlin/works/codes/oss/poltertty/.worktrees/workspace-ai-agent
git add macos/Sources/Features/Agent/Monitor/SubagentTranscriptReader.swift \
        macos/Tests/SubagentTranscriptReaderTests.swift
git commit -m "feat: add SubagentTranscriptReader with JSONL parsing"
```

---

## Task 2: SubagentMessagesView UI

**Files:**
- Create: `macos/Sources/Features/Agent/Monitor/SubagentMessagesView.swift`

### 背景知识

参考 `SubagentTraceContent.swift` 中的 Timer 自刷新模式：

```swift
@State private var tick = Date()
private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
// body 中：.onReceive(timer) { t in if subagent.state.isActive { tick = t } }
```

参考 `SubagentOutputContent.swift` 中的 section 分隔符样式（字号 9pt semibold tertiary）。

`Color(hex:)` 扩展在项目中已存在（`Color+Hex.swift`）。

- [ ] **Step 1: 实现 SubagentMessagesView**

新建 `macos/Sources/Features/Agent/Monitor/SubagentMessagesView.swift`：

```swift
// macos/Sources/Features/Agent/Monitor/SubagentMessagesView.swift
import SwiftUI

struct SubagentMessagesView: View {
    let session: AgentSession
    let subagent: SubagentInfo

    @State private var transcript: SubagentTranscript? = nil
    @State private var isLoading = true
    @State private var tick = Date()
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                tokenSummary
                debugIdBar
                Divider().padding(.vertical, 6)
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding(20)
                } else if let t = transcript, !t.turns.isEmpty {
                    messageList(t)
                } else {
                    Text("暂无对话记录")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(20)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await loadTranscript() }
        .onReceive(timer) { t in
            if subagent.state.isActive {
                tick = t
                Task { await loadTranscript() }
            }
        }
    }

    // MARK: - Token Summary

    private var tokenSummary: some View {
        let usage = transcript?.totalUsage ?? TurnUsage.zero
        return HStack(spacing: 0) {
            tokenCell(label: "IN", value: usage.inputTokens)
            Divider().frame(height: 20)
            tokenCell(label: "OUT", value: usage.outputTokens)
            Divider().frame(height: 20)
            tokenCell(label: "CACHE", value: usage.cacheReadTokens + usage.cacheWriteTokens)
            Spacer()
        }
        .padding(.bottom, 6)
    }

    private func tokenCell(label: String, value: Int) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
            Text(formatTokens(value))
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
        }
        .frame(minWidth: 60)
        .padding(.vertical, 4)
    }

    private func formatTokens(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fK", Double(n) / 1000) : "\(n)"
    }

    // MARK: - Debug ID Bar

    private var debugIdBar: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let agentId = subagent.agentId {
                debugIdRow(label: "Agent", value: agentId)
            }
            if let sessionId = session.claudeSessionId {
                debugIdRow(label: "Session", value: sessionId)
            }
        }
        .padding(.bottom, 4)
    }

    private func debugIdRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                .frame(width: 44, alignment: .leading)
            Text(value.count > 16 ? String(value.prefix(16)) + "…" : value)
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    // MARK: - Message List

    private func messageList(_ transcript: SubagentTranscript) -> some View {
        LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(transcript.turns) { turn in
                TurnView(turn: turn)
            }
        }
    }

    // MARK: - Load

    private func loadTranscript() async {
        let result = await SubagentTranscriptReader.read(session: session, subagent: subagent)
        await MainActor.run {
            transcript = result
            isLoading = false
        }
    }
}

// MARK: - TurnView

private struct TurnView: View {
    let turn: TranscriptTurn
    @State private var expandedToolIds: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(turn.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(turn.role == .user
            ? Color(.controlColor).opacity(0.3)
            : Color(.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func blockView(_ block: TranscriptBlock) -> some View {
        switch block {
        case .text(let t):
            Text(t)
                .font(.system(size: 10))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .toolUse(let id, let name, let inputJSON):
            VStack(alignment: .leading, spacing: 0) {
                Button(action: { toggleExpand(id) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.fill")
                            .font(.system(size: 8)).foregroundStyle(.secondary)
                        Text(name)
                            .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: expandedToolIds.contains(id) ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8)).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())

                if expandedToolIds.contains(id) {
                    Text(inputJSON)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .padding(.top, 3).padding(.leading, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

        case .toolResult(_, let content):
            if !content.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("── result ──")
                        .font(.system(size: 8)).foregroundStyle(.quaternary)
                    Text(content)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .lineLimit(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, 12)
            }
        }
    }

    private func toggleExpand(_ id: String) {
        if expandedToolIds.contains(id) {
            expandedToolIds.remove(id)
        } else {
            expandedToolIds.insert(id)
        }
    }
}
```

> **macOS 兼容性提示**：`.quaternary` 前景色在 macOS 13 可用（SwiftUI Color），如出现编译错误，替换为 `.tertiary.opacity(0.5)`。

- [ ] **Step 2: 构建验证**

```bash
cd /Users/aaronlin/works/codes/oss/poltertty/.worktrees/workspace-ai-agent/macos
xcodebuild build -workspace Ghostty.xcodeproj/project.xcworkspace -scheme Ghostty -destination 'platform=macOS' 2>&1 | grep -E "error:|warning:|BUILD SUCCEEDED|BUILD FAILED"
```

预期：`BUILD SUCCEEDED`（此时 `SubagentMessagesView` 还未被使用，不影响构建）

- [ ] **Step 3: Commit**

```bash
cd /Users/aaronlin/works/codes/oss/poltertty/.worktrees/workspace-ai-agent
git add macos/Sources/Features/Agent/Monitor/SubagentMessagesView.swift
git commit -m "feat: add SubagentMessagesView with transcript display"
```

---

## Task 3: 接入 AgentDrawerPanel

**Files:**
- Modify: `macos/Sources/Features/Agent/Monitor/AgentDrawerPanel.swift:4-8,154-158`

### 背景知识

当前代码（行号供参考）：
```swift
// line 4-8
enum DrawerTab: String, CaseIterable {
    case output   = "Output"   // ← 改为 "Messages"
    case trace    = "Trace"
    case overview = "Overview"
}

// line 154-158
case .subagentDetail(let session, let sub):
    switch tab {
    case .output:    SubagentOutputContent(session: session, subagent: sub)  // ← 替换
    case .trace:     SubagentTraceContent(subagent: sub)
    case .overview:  EmptyView()
    }
```

- [ ] **Step 1: 修改 DrawerTab 枚举的 rawValue**

在 `macos/Sources/Features/Agent/Monitor/AgentDrawerPanel.swift` 第 5 行：

将：
```swift
    case output   = "Output"
```
改为：
```swift
    case output   = "Messages"
```

- [ ] **Step 2: 替换 contentArea 中的 Output 视图**

在同文件第 155 行，将：
```swift
            case .output:    SubagentOutputContent(session: session, subagent: sub)
```
改为：
```swift
            case .output:    SubagentMessagesView(session: session, subagent: sub)
```

- [ ] **Step 3: 构建验证**

```bash
cd /Users/aaronlin/works/codes/oss/poltertty/.worktrees/workspace-ai-agent/macos
xcodebuild build -workspace Ghostty.xcodeproj/project.xcworkspace -scheme Ghostty -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

预期：`BUILD SUCCEEDED`

- [ ] **Step 4: 运行所有单元测试**

```bash
cd /Users/aaronlin/works/codes/oss/poltertty/.worktrees/workspace-ai-agent/macos
xcodebuild test -workspace Ghostty.xcodeproj/project.xcworkspace -scheme Ghostty -destination 'platform=macOS' 2>&1 | grep -E "passed|failed|error:"
```

预期：所有测试通过，无新失败

- [ ] **Step 5: 手动验证（构建并运行 app）**

```bash
cd /Users/aaronlin/works/codes/oss/poltertty/.worktrees/workspace-ai-agent/macos
xcodebuild build -workspace Ghostty.xcodeproj/project.xcworkspace -scheme Ghostty -destination 'platform=macOS' -derivedDataPath build/DerivedData 2>&1 | tail -5
open build/DerivedData/Build/Products/Debug/Poltertty.app
```

验证清单：
- [ ] 打开 Agent Monitor，点击一个 subagent → Drawer 出现，Tab 显示 "Messages" 和 "Trace"
- [ ] Messages tab 显示 Token 摘要（IN / OUT / CACHE）
- [ ] Messages tab 显示 Agent / Session debug ID（截断 + 可选中复制）
- [ ] 若 subagent 有 JSONL 文件，消息列表正常展示
- [ ] 若无 JSONL 文件，显示 "暂无对话记录"
- [ ] Trace tab 仍正常工作（未被影响）

- [ ] **Step 6: Commit**

```bash
cd /Users/aaronlin/works/codes/oss/poltertty/.worktrees/workspace-ai-agent
git add macos/Sources/Features/Agent/Monitor/AgentDrawerPanel.swift
git commit -m "feat: replace Output tab with Messages tab in subagent detail panel"
```

---

## 验收标准

1. `SubagentTranscriptReaderTests` 全部通过
2. 构建无 error
3. Tab 名称从 "Output" 变为 "Messages"
4. Messages tab 展示 token 摘要、debug ID、消息列表
5. Trace tab 功能不受影响
