# Subagent 富信息展示设计

**日期**: 2026-03-18
**状态**: 已通过用户审核，待实现

---

## 背景

当前 Subagent 详情面板有两个 Tab：Output、Trace（Prompt tab 有视图文件但未暴露在 UI 中）。其中：
- **Output** 仅显示最终文本输出（`SubagentInfo.output`），无 token 信息，无对话过程
- **Trace** 显示工具调用列表（带参数）

Claude Code 会将 subagent 的完整对话写入 JSONL 文件（`~/.claude/projects/{sanitized-cwd}/{sessionId}/subagents/agent-{agentId}.jsonl`）。该文件包含完整的用户/助手消息、工具调用及结果、每轮的 token 消耗。

本设计将 Output tab 替换为 **Messages tab**，展示完整对话流程、token 消耗汇总，并在 UI 顶部显示 session/agent ID 用于调试。

---

## 设计目标

1. 展示 subagent 的完整对话过程（文字 + 工具调用 + 工具结果）
2. 汇总 token 消耗（input / output / cache tokens）
3. 展示 agentId / sessionId 用于调试对应
4. 对运行中的 subagent 每 3s 自动刷新
5. 不破坏现有 Trace tab

---

## JSONL 文件格式

### 路径规则

```
~/.claude/projects/{sanitized-cwd}/{claudeSessionId}/subagents/agent-{agentId}.jsonl
```

**`sanitized-cwd` 派生规则**：将 cwd 中的每个 `/` 和空格字符替换为 `-`，然后去掉开头的 `-`（因为 cwd 通常以 `/` 开头，替换后首字符为 `-`）。

示例：
```
输入：  /Users/aaron/my project/app
替换后：-Users-aaron-my-project-app
去首-： Users-aaron-my-project-app   ← 最终值
```

若 `session.claudeSessionId` 或 `subagent.agentId` 为 nil，则路径无法派生，返回 nil。

### 每行 JSON 结构

| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | String | `"user"` / `"assistant"` / `"progress"` |
| `message.role` | String | `"user"` / `"assistant"` |
| `message.content` | Array | content blocks |
| `message.usage` | Object | `{input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens}` |
| `agentId` | String | 对应 `SubagentInfo.agentId` |
| `sessionId` | String | 父 session 的 Claude session ID（用于路径定位） |
| `timestamp` | String | ISO 8601 |

**content block 类型**：
- `{"type": "text", "text": "..."}` — 纯文字
- `{"type": "tool_use", "id": "...", "name": "...", "input": {...}}` — 工具调用
- `{"type": "tool_result", "tool_use_id": "...", "content": [...]}` — 工具结果（content 是 blocks 数组）

---

## 数据模型（新增）

### `TranscriptBlock`

```swift
enum TranscriptBlock {
    case text(String)
    case toolUse(id: String, name: String, inputJSON: String)   // inputJSON 为 JSONSerialization 序列化后的字符串
    case toolResult(toolUseId: String, content: String)         // content 为所有 text block 的拼接，非 text block 忽略
}
```

`toolResult.content` 解析策略：遍历 `content` 数组，提取所有 `type == "text"` 的 block 的 `text` 字段，用换行拼接。非 text 类型（如图片）忽略。

### `TranscriptTurn`

```swift
struct TranscriptTurn: Identifiable {
    let id: UUID
    let role: Role           // .user / .assistant
    let blocks: [TranscriptBlock]
    let usage: TurnUsage?    // 仅 assistant 轮次有（来自 message.usage）
    let timestamp: Date

    enum Role { case user, assistant }
}

struct TurnUsage {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int    // cache_read_input_tokens
    let cacheWriteTokens: Int   // cache_creation_input_tokens
}
```

### `SubagentTranscript`

```swift
struct SubagentTranscript {
    let turns: [TranscriptTurn]
    let totalUsage: TurnUsage   // 所有 assistant 轮次 usage 字段的累加
}
```

---

## 核心组件

### `SubagentTranscriptReader`（新文件）

职责：根据 `AgentSession` + `SubagentInfo` 派生文件路径，读取并解析 JSONL 文件。

```swift
final class SubagentTranscriptReader {
    static func transcriptPath(session: AgentSession, subagent: SubagentInfo) -> String?
    static func read(session: AgentSession, subagent: SubagentInfo) async -> SubagentTranscript?
}
```

解析逻辑：
1. 逐行读取文件，跳过无法解析为 JSON 的行
2. 过滤 `type == "progress"` 的行（不展示）
3. 根据 `message.role` 构建 `TranscriptTurn`
4. 只累加 `role == "assistant"` 行的 `message.usage` 到 `totalUsage`
5. tool_use / tool_result block 保留原始顺序，由 UI 负责配对展示

### `SubagentMessagesView`（新文件）

Messages tab 内容视图，替换 `SubagentOutputContent`。

结构（从上到下）：

1. **Token 摘要栏**：`input / output / cache` 三列横排，字号 9pt，数值单位"K"
2. **Debug ID 栏**：`Agent` 对应 `subagent.agentId`，`Session` 对应 `session.claudeSessionId`，字号 9pt，等宽字体，超出截断为 16 字符 + `…`，`.textSelection(.enabled)` 支持选中复制完整值
3. **消息列表**：`ScrollView` + `LazyVStack`，每个 `TranscriptTurn` 渲染为一个区块
4. **状态占位**：
   - 首次加载中：显示 `ProgressView()`
   - 文件不存在或无法读取：显示 `"暂无对话记录"`（`.secondary` 颜色，居中）
   - 空 turns 列表：显示 `"暂无对话记录"`

#### 消息区块渲染规则

| role | 背景 | 对齐 |
|------|------|------|
| user | `Color(.controlColor).opacity(0.3)` | 左对齐 |
| assistant | `Color(.windowBackgroundColor)` | 左对齐 |

每个 turn 内部，按 block 顺序渲染：
- `text` block：直接显示文字，字号 10pt，`.lineLimit(nil)`
- `tool_use` block：折叠行（默认收起），显示工具名；点击 row 展开显示 inputJSON
- `tool_result` block：与对应 `tool_use` 配对（通过 `toolUseId` 匹配），显示在 `tool_use` 展开区域的下方，带缩进和分隔线

tool_use 折叠行样式（参考 Trace tab 风格）：
```
🔧 Read  ▶
   path: /foo/bar.swift        ← 展开后显示，可选中
   ── result ──
   (file content here)         ← tool_result 内容，可选中
```

#### 刷新机制

`SubagentMessagesView` 自持 `Timer.publish(every: 3, ...)` 用于读取刷新（与 `AgentDrawerPanel` 已有的 tick Timer 并列存在，这是与 `SubagentTraceContent` 相同的设计选择）：
- `onAppear` 时异步加载一次
- 若 `subagent.state.isActive` 为 true，每次 tick 重新读取文件并替换 `transcript`
- 若 subagent 已完成（`.done` / `.error`），不启动定时刷新

---

## AgentDrawerPanel 修改

1. **Tab 重命名**：将 `DrawerTab.output` 的 `rawValue` 从 `"Output"` 改为 `"Messages"`
2. **视图替换**：`case .output`（即 Messages tab）使用 `SubagentMessagesView(session:subagent:)` 替代 `SubagentOutputContent`
3. **`availableTabs` 不变**：`.subagentDetail` 仍返回 `[.output, .trace]`（现在显示为 "Messages" / "Trace"）
4. Trace tab 不变

---

## 文件清单

| 操作 | 文件 |
|------|------|
| 新增 | `macos/Sources/Features/Agent/Monitor/SubagentTranscriptReader.swift` |
| 新增 | `macos/Sources/Features/Agent/Monitor/SubagentMessagesView.swift` |
| 修改 | `macos/Sources/Features/Agent/Monitor/AgentDrawerPanel.swift` — Output → Messages tab 重命名，`contentArea` 替换视图 |
| 保留 | `macos/Sources/Features/Agent/Monitor/SubagentOutputContent.swift` — 暂不删除，DrawerPanel 不再引用即可 |

---

## 不在本次范围内

- 工具结果的富文本渲染（Markdown、图片）
- 消息搜索 / 过滤
- 导出对话记录
- 多 subagent 的 token 对比
- Prompt tab 的 UI 暴露（`SubagentPromptContent.swift` 存在但不在本次范围内）
