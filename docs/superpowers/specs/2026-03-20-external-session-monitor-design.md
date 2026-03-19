# External Session Monitor — Design Spec

**日期：** 2026-03-20
**状态：** 待实现
**目标：** 在现有 AgentMonitorPanel 中集成对独立启动的 AI 编程工具实例的监控，作为现有派生 agent 监控的补充。

---

## 背景

现有 AgentMonitor 仅监控通过 AgentLauncher（Agent 工具）派生的子 agent。用户在独立终端中手动启动的 Claude Code、OpenCode 等实例无法被监控。

各工具将运行时信息写入本地文件系统：
- **Claude Code**：`~/.claude/sessions/<pid>.json`（进程元数据）+ `~/.claude/projects/<cwd>/<sessionId>.jsonl`（对话历史）
- **OpenCode**：`~/.local/share/opencode/opencode.db`（SQLite，含 `session.directory` 和 `message.data`）
- **Gemini CLI**：预留扩展点（当前未安装）

---

## 目标

- 发现 `cwd` 与当前 workspace `rootDir` 匹配的外部 session
- 监听文件变化获取准实时状态（最后一条消息）
- 在现有 AgentMonitorPanel 中合并展示，加 badge 区分来源
- 30s 定时兜底刷新 + 进程存活检测

---

## 架构

```
~/.claude/sessions/        ~/.local/share/opencode/opencode.db
        │                              │
        ▼ FSEvents                     ▼ FSEvents
ClaudeSessionProvider      OpenCodeSessionProvider     GeminiSessionProvider (stub)
        │                              │                         │
        └──────────────────────────────┴─────────────────────────┘
                                       │
                          ExternalSessionDiscovery（编排器）
                          @Published sessions: [ExternalSessionRecord]
                          在 AgentMonitorViewModel 中持有并订阅
                                       │
                          AgentMonitorViewModel（@Published externalSessions）
                                       │
                          AgentMonitorPanel（新增"外部会话"section）
```

---

## 数据模型

### `ExternalToolType`（定义在 `ExternalSessionRecord.swift` 中）

```swift
enum ExternalToolType: String {
    case claudeCode = "claude-code"
    case openCode   = "opencode"
    case geminiCli  = "gemini-cli"

    var badge: String {
        switch self { case .claudeCode: "[CC]"; case .openCode: "[OC]"; case .geminiCli: "[GM]" }
    }
}
```

使用独立枚举而非复用 `AgentDefinition.id`（String），避免外部监控与 AgentLauncher 的概念耦合。

### `ExternalSessionRecord`

```swift
struct ExternalSessionRecord: Identifiable {
    let id: String              // sessionId（Claude）或 session.id（OpenCode）
    let toolType: ExternalToolType
    let pid: Int?               // Claude 有 pid；OpenCode 无 pid 文件
    let cwd: String             // 工作目录（已展开 ~）
    let startedAt: Date
    var isAlive: Bool
    var lastMessage: LastMessage?

    struct LastMessage {
        enum Role { case user, assistant }
        let role: Role
        let text: String        // 截断至 120 字符
        let timestamp: Date
    }
}
```

---

## 新增文件

所有新文件放在 `macos/Sources/Features/Agent/ExternalMonitor/` 目录。

### `ExternalAgentProvider.swift`（协议）

Provider 在主线程上被调用；FSEvents 回调必须在主线程上触发 `onChange`。

```swift
@MainActor
protocol ExternalAgentProvider: AnyObject {
    var toolType: ExternalToolType { get }
    /// 返回当前匹配 workspaceDir 的 session 快照（主线程调用）
    func currentSessions() -> [ExternalSessionRecord]
    /// 开始监听；onChange 在主线程触发
    func startWatching(onChange: @escaping @MainActor () -> Void)
    func stopWatching()
}
```

`workspaceDir` 在构造时传入 Provider，不在 `currentSessions()` 重复传递，保持方法无状态参数。

### `ClaudeSessionProvider.swift`

**数据来源：**
- `~/.claude/sessions/` 目录：FSEvents 监听，变化时全量 scan `.json` 文件
- `~/.claude/projects/<cwd>/<sessionId>.jsonl`：对每个 **存活** session 单独监听

**实现要点：**

```swift
@MainActor
final class ClaudeSessionProvider: ExternalAgentProvider {
    let toolType: ExternalToolType = .claudeCode
    private let workspaceDir: String
    private var sessionsDirSource: DispatchSourceFileSystemObject?
    private var jsonlSources: [String: DispatchSourceFileSystemObject] = [:]  // sessionId → source
    private var records: [String: ExternalSessionRecord] = [:]                 // sessionId → record
    private var onChange: (@MainActor () -> Void)?

    init(workspaceDir: String) {
        self.workspaceDir = workspaceDir
    }

    func startWatching(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        scan()
        watchDir()
    }

    func stopWatching() {
        sessionsDirSource?.cancel()
        jsonlSources.values.forEach { $0.cancel() }
        jsonlSources.removeAll()
    }

    func currentSessions() -> [ExternalSessionRecord] {
        Array(records.values)
    }
}
```

**scan() 逻辑：**
1. 读取 `~/.claude/sessions/*.json`，解码为 `{ pid, sessionId, cwd, startedAt }`
2. 过滤 `cwd == workspaceDir`（已展开 `~`）
3. 对每个匹配项：`isAlive = kill(pid, 0) == 0`
4. 新增的存活 session → 调用 `watchJsonl(for:)`
5. 消失的或死亡的 session → `jsonlSources[id]?.cancel()`，从 `jsonlSources` 和 `records` 移除
6. 更新 `records`，调用 `onChange()`

**watchJsonl(for:) 逻辑：**
- 用 `DispatchSource.makeFileSystemObjectSource(fileDescriptor:eventMask:queue:)` 监听 `.jsonl` 文件
- FSEvents 回调中：`DispatchQueue.main.async { self.parseJsonlTail(sessionId:); self.onChange?() }`（必须回到主线程，避免打破 `@MainActor` 隔离）
- 必须设置 `cancelHandler`：`source.setCancelHandler { close(fd) }`，防止 fd 泄漏（参考项目内 `GitStatusService` 的做法）
- session 死亡时（下次 scan 发现 pid 不存活）：`cancel()` 对应 source 并从 `jsonlSources` 移除

**parseJsonlTail 解析：**
- 从文件尾部反向读行（最多扫描 50 行）
- 找第一条 `type == "user"` 或 `type == "assistant"` 的条目
- 取 `message.content`：若为 String 直接用；若为数组取第一个 `type == "text"` 的 `text` 字段
- 截断至 120 字符
- 注意：`.jsonl` 顶层 `type` 字段值为 `"user"` / `"assistant"`（已验证，非 `"human"`）

**30s 兜底刷新：** 在 `ExternalSessionDiscovery` 层统一处理，Provider 无需自行实现 Timer。

### `OpenCodeSessionProvider.swift`

**数据来源：** `~/.local/share/opencode/opencode.db`（SQLite）

```swift
@MainActor
final class OpenCodeSessionProvider: ExternalAgentProvider {
    let toolType: ExternalToolType = .openCode
    private let workspaceDir: String
    private let dbPath: String
    private var dbFileSource: DispatchSourceFileSystemObject?

    init(workspaceDir: String) {
        self.workspaceDir = workspaceDir
        self.dbPath = "\(NSHomeDirectory())/.local/share/opencode/opencode.db"
    }
}
```

**SQLite 查询：**

```sql
SELECT s.id, s.directory, s.time_created, s.time_updated,
       m.data AS last_message_data, m.time_updated AS msg_time
FROM session s
LEFT JOIN (
    SELECT session_id, data, time_updated
    FROM message
    WHERE rowid IN (
        SELECT MAX(rowid) FROM message GROUP BY session_id
    )
) m ON m.session_id = s.id
WHERE s.directory = ?
  AND s.time_archived IS NULL
```

**SQLite 打开方式：**
- 使用 `SQLITE_OPEN_READONLY` 标志，避免写锁竞争
- 设置 `sqlite3_busy_timeout(db, 500)`，处理 OpenCode 写入时的 WAL 锁定
- 查询失败（`SQLITE_BUSY`）时静默跳过，等待下次 FSEvents 触发

**isAlive 判断：** 不使用 `pgrep`（无法区分多 workspace 的多个 opencode 进程）。改为：
- `session.time_updated` 在最近 5 分钟内 → `isAlive = true`
- 超过 5 分钟 → `isAlive = false`

**lastMessage 解析：** `message.data` 为 JSON，格式与 Claude 类似，取 `role` 和文本内容块。

**FSEvents：** 监听 `opencode.db` 文件变化（WAL 提交时会触发），回调中重新查询并调用 `onChange()`。回调必须通过 `DispatchQueue.main.async` 回到主线程。

### `GeminiSessionProvider.swift`（stub）

显式声明 `init(workspaceDir:)` 保持与其他 Provider 接口一致，未来实现时无需修改 `ExternalSessionDiscovery`。

```swift
@MainActor
final class GeminiSessionProvider: ExternalAgentProvider {
    let toolType: ExternalToolType = .geminiCli
    init(workspaceDir: String) {}   // 保持接口一致；Gemini 安装后在此实现
    func currentSessions() -> [ExternalSessionRecord] { [] }
    func startWatching(onChange: @escaping @MainActor () -> Void) {}
    func stopWatching() {}
}
```

### `ExternalSessionDiscovery.swift`（编排器）

```swift
@MainActor
final class ExternalSessionDiscovery: ObservableObject {
    @Published private(set) var sessions: [ExternalSessionRecord] = []

    private let workspaceDir: String
    private let providers: [any ExternalAgentProvider]
    private var refreshTimer: Timer?

    init(workspaceRootDir: String) {
        self.workspaceDir = workspaceRootDir
        self.providers = [
            ClaudeSessionProvider(workspaceDir: workspaceRootDir),
            OpenCodeSessionProvider(workspaceDir: workspaceRootDir),
            GeminiSessionProvider(workspaceDir: workspaceRootDir),
        ]
    }

    func start() {
        providers.forEach { p in
            p.startWatching { [weak self] in self?.refresh() }
        }
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func stop() {
        providers.forEach { $0.stopWatching() }
        refreshTimer?.invalidate()
        refreshTimer = nil
        sessions = []
    }

    deinit {
        // Timer 在 deinit 前已通过 stop() 失效；
        // 若未调用 stop()，此处兜底 invalidate
        refreshTimer?.invalidate()
    }

    private func refresh() {
        sessions = providers.flatMap { $0.currentSessions() }
    }
}
```

---

## 修改文件

### `AgentMonitorViewModel.swift`

`ExternalSessionDiscovery` **在 ViewModel 中持有**，通过 Combine 驱动 UI 刷新：

```swift
// 新增属性
@Published private(set) var externalSessions: [ExternalSessionRecord] = []
private var externalDiscovery: ExternalSessionDiscovery?

// init(workspaceId:) 中追加
// workspaceDir 通过 WorkspaceManager.shared.workspace(for: workspaceId)?.rootDirExpanded 获取
if let rootDir = WorkspaceManager.shared.workspace(for: workspaceId)?.rootDirExpanded,
   !rootDir.isEmpty {
    let discovery = ExternalSessionDiscovery(workspaceRootDir: rootDir)
    externalDiscovery = discovery
    discovery.$sessions
        .receive(on: RunLoop.main)
        .assign(to: &$externalSessions)
    discovery.start()
}

// deinit 中
// 注意：deinit 不受 @MainActor 保证，stop() 中只取消资源（cancel source、invalidate timer），
// 不写 @Published 属性（此时已无观察者，不需要触发 UI 更新）
deinit {
    externalDiscovery?.stop()
}

// 辅助计算属性
var hasExternalSessions: Bool { !externalSessions.isEmpty }
```

`WorkspaceManager.shared.workspace(for: workspaceId)?.rootDirExpanded` 将已展开 `~` 的绝对路径传给 Discovery，与 `~/.claude/sessions/*.json` 中的 `cwd` 字段格式一致。

### `AgentMonitorPanel.swift`

现有 `AgentMonitorPanel` 使用 `ScrollView + LazyVStack` 布局（非 `List`），不支持 `Section { } header: { }` 语法。外部会话 section 使用手动 header + `ForEach` 与现有布局对齐：

```swift
if viewModel.hasExternalSessions {
    // 手动 header，与现有 LazyVStack 布局兼容
    Text("外部会话 (\(viewModel.externalSessions.count))")
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 8)

    ForEach(viewModel.externalSessions) { session in
        ExternalSessionRow(session: session)
    }
}
```

**空状态处理：** 现有"No active agents"空状态提示，条件从 `sessions.isEmpty` 改为 `sessions.isEmpty && !viewModel.hasExternalSessions`，避免有外部会话时仍显示"无 agent"提示。

**新增 `ExternalSessionRow` 组件（同文件或独立文件）：**

```
┌───────────────────────────────────┐
│ [CC] poltertty           ● pid    │  ← badge + cwd末段 + 存活状态 + pid
│ 你：不是使用 agent launch…        │  ← lastMessage 单行截断
│ 23:03                             │  ← 启动时间
└───────────────────────────────────┘
```

- `[CC]` 橙色 / `[OC]` 蓝色 / `[GM]` 绿色
- `isAlive` 为 false 时 badge 和存活点变灰，row 降低 opacity
- `pid` 仅 Claude Code 显示（OpenCode 无 pid）

### `TerminalController.swift`

**不需要修改。** `ExternalSessionDiscovery` 的生命周期绑定在 `AgentMonitorViewModel` 的 `init/deinit` 上，随 ViewModel 创建/销毁自动管理，无需在 `TerminalController` 添加额外的生命周期调用。

---

## 文件清单

**新增（6 个文件）：**
```
macos/Sources/Features/Agent/ExternalMonitor/
    ExternalSessionRecord.swift      — 数据模型 + ExternalToolType 枚举
    ExternalAgentProvider.swift      — @MainActor 协议
    ClaudeSessionProvider.swift      — 文件系统实现
    OpenCodeSessionProvider.swift    — SQLite 实现
    GeminiSessionProvider.swift      — stub
    ExternalSessionDiscovery.swift   — 编排器
```

**修改（2 个文件）：**
```
macos/Sources/Features/Agent/Monitor/AgentMonitorViewModel.swift  — 持有 Discovery，@Published externalSessions
macos/Sources/Features/Agent/Monitor/AgentMonitorPanel.swift      — 外部会话 section + 空状态修正
```

**项目文件：**
```
macos/Sources/Xcode/Ghostty.xcodeproj/project.pbxproj             — 添加 6 个新文件引用
```

---

## 不在本次范围内

- 向外部 session 注入 HookServer（需要工具重启，体验代价高）
- Gemini CLI 的实际实现（未安装，待后续）
- 外部 session 的操作控制（停止、重启等）
- 跨 workspace 的全局外部 session 视图
