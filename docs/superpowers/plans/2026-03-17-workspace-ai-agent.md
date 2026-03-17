# Workspace AI Agent 管理系统实现计划

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Poltertty 中原生支持 AI agent（Claude Code、Gemini CLI 等）的启动、状态监控、自动续命和计费，无需 tmux 或 Web 中间层。

**Architecture:** `AgentService` 中心化单例持有所有子模块（AgentRegistry、AgentSessionManager、HookServer、RespawnController、TokenTracker），app 启动时初始化。Agent 状态通过三层感知：HTTP Hook（HookServer）→ 文件系统监听（FileWatcher）→ 进程退出监控（ProcessMonitor），`@Published` 属性驱动 SwiftUI 自动刷新。

**Tech Stack:** Swift 5.9+, SwiftUI, `@MainActor`, `Network.framework`（NWListener 作内嵌 HTTP server），`DispatchSource`（文件/进程监控），`NSFileCoordinator`（原子文件操作）

---

## Xcode 项目文件说明

每次添加新 Swift 文件后，必须将其加入 `macos/Ghostty.xcodeproj`，否则不参与编译：

```bash
# 推荐方式：在 Xcode 中打开项目
open macos/Ghostty.xcodeproj
# 右键目标 Group → Add Files to "Ghostty"，勾选正确 Target
# 然后 make check 验证
```

**注意：** 每个 Task 的 Commit 步骤中都包含 `macos/Ghostty.xcodeproj/project.pbxproj`，记得在 Xcode 中添加文件后再提交。

---

## 文件结构

### 新增文件

```
macos/Sources/Features/Agent/
├── AgentDefinition.swift          — AgentDefinition struct + AgentRegistry（内置预设 + 用户自定义）
├── AgentSession.swift             — AgentSession struct + AgentState 状态机 + 占位子类型
├── AgentSessionManager.swift      — @MainActor @Published session 跟踪，surfaceId ↔ session 映射
├── AgentService.swift             — @MainActor 单例，持有所有子模块，生命周期管理
├── HookServer/
│   ├── HookEvent.swift            — 所有 hook payload 的 Decodable 类型
│   ├── HookServer.swift           — NWListener HTTP server，localhost:19198，多实例协调
│   └── HookInjector.swift         — .claude/settings.local.json 原子写入/合并/清理
├── Monitoring/
│   └── ProcessMonitor.swift       — DispatchSource.makeProcessSource，进程退出检测
├── Launcher/
│   ├── AgentLauncher.swift        — 启动逻辑：创建 surface，写 PTY，注册 session
│   └── AgentLaunchMenu.swift      — SwiftUI 两步下拉菜单（选 agent → 选位置）
├── Monitor/
│   ├── AgentMonitorViewModel.swift — @MainActor @Published，Monitor Panel 数据层
│   ├── AgentMonitorPanel.swift    — 右侧面板 SwiftUI 视图，Cmd+Shift+M 切换
│   └── SubagentListView.swift     — Subagent 折叠列表
├── Respawn/
│   ├── RespawnMode.swift          — RespawnMode enum + 每种模式配置参数
│   └── RespawnController.swift    — idle 检测、自动写 continue、circuit breaker
└── TokenTracker/
    ├── TokenUsage.swift           — TokenUsage struct + TokenSnapshot，Codable
    ├── ModelPricing.swift         — 内置价格表（Opus/Sonnet/Haiku/Gemini）
    └── TokenTracker.swift         — 解析 transcript、累计费用、持久化
```

### 修改文件

```
macos/Sources/Features/Workspace/WorkspaceManager.swift
  — 存储格式迁移：{UUID}.json → {UUID}/workspace.json
  — 新增 public workspaceDir(for:) 方法

macos/Sources/App/macOS/AppDelegate.swift
  — applicationDidFinishLaunching: 初始化 AgentService
  — applicationWillTerminate: 调用 AgentService.shutdown()

macos/Sources/Features/Workspace/TabBar/TabBarViewModel.swift
  — 新增 agentState(for surfaceId:) 和 agentCostDisplay(for surfaceId:)

macos/Sources/Features/Workspace/TabBar/TerminalTabItem.swift
  — tab 标题旁显示状态圆点 + AgentStateDot 视图

macos/Sources/Features/Workspace/TabBar/TerminalTabBar.swift
  — 向 TerminalTabItem 传入 agentState

macos/Sources/Features/Terminal/TerminalController.swift
  — Cmd+Shift+A 快捷键，showAgentLaunchMenu，addNewTab，addSplitPane，writeToActiveSurface

macos/Sources/Features/Workspace/PolterttyRootView.swift
  — 集成 AgentMonitorPanel（右侧），Cmd+Shift+M 快捷键
```

---

## Phase 1：数据模型 + 存储迁移

### Task 1.1：AgentDefinition + AgentRegistry

**Files:**
- Create: `macos/Sources/Features/Agent/AgentDefinition.swift`

- [ ] **Step 1：创建目录结构**

```bash
cd .worktrees/workspace-ai-agent
mkdir -p macos/Sources/Features/Agent/HookServer
mkdir -p macos/Sources/Features/Agent/Monitoring
mkdir -p macos/Sources/Features/Agent/Launcher
mkdir -p macos/Sources/Features/Agent/Monitor
mkdir -p macos/Sources/Features/Agent/Respawn
mkdir -p macos/Sources/Features/Agent/TokenTracker
```

- [ ] **Step 2：创建 AgentDefinition.swift**

```swift
// macos/Sources/Features/Agent/AgentDefinition.swift
import Foundation

/// Agent 支持的 hook 能力等级
enum HookCapability: String, Codable {
    case full        // HTTP hook（Claude Code）
    case commandOnly // command hook + 桥接脚本（Gemini CLI）
    case none        // 无 hook，仅进程监控
}

/// 单个 Agent 类型定义
struct AgentDefinition: Identifiable, Codable {
    let id: String
    var name: String
    var command: String
    var icon: String
    var hookCapability: HookCapability

    static let claudeCode = AgentDefinition(
        id: "claude-code", name: "Claude Code",
        command: "claude", icon: "◆", hookCapability: .full
    )
    static let geminiCLI = AgentDefinition(
        id: "gemini-cli", name: "Gemini CLI",
        command: "gemini", icon: "✦", hookCapability: .commandOnly
    )
    static let openCode = AgentDefinition(
        id: "opencode", name: "OpenCode",
        command: "opencode", icon: "⬡", hookCapability: .none
    )
}

/// 所有可用 agent 的注册表（内置 + 用户自定义）
@MainActor
final class AgentRegistry: ObservableObject {
    static let shared = AgentRegistry()

    @Published private(set) var definitions: [AgentDefinition] = []

    private let builtins: [AgentDefinition] = [.claudeCode, .geminiCLI, .openCode]

    private static let customConfigPath: String = {
        let base = ("~/.config/poltertty" as NSString).expandingTildeInPath
        return (base as NSString).appendingPathComponent("agents.json")
    }()

    private struct CustomAgentsFile: Codable { var agents: [AgentDefinition] }

    private init() { reload() }

    func reload() {
        var all = builtins
        if let data = try? Data(contentsOf: URL(fileURLWithPath: Self.customConfigPath)),
           let custom = try? JSONDecoder().decode(CustomAgentsFile.self, from: data) {
            for agent in custom.agents {
                if let idx = all.firstIndex(where: { $0.id == agent.id }) {
                    all[idx] = agent
                } else {
                    all.append(agent)
                }
            }
        }
        definitions = all
    }
}
```

- [ ] **Step 3：在 Xcode 中添加文件，在 Features 下新建 Agent group**

- [ ] **Step 4：编译检查**

```bash
cd .worktrees/workspace-ai-agent && make check
```

- [ ] **Step 5：Commit**

```bash
cd .worktrees/workspace-ai-agent
git add macos/Sources/Features/Agent/AgentDefinition.swift macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "feat(agent): add AgentDefinition and AgentRegistry"
```

---

### Task 1.2：AgentSession 数据模型

**Files:**
- Create: `macos/Sources/Features/Agent/AgentSession.swift`

- [ ] **Step 1：创建 AgentSession.swift**

```swift
// macos/Sources/Features/Agent/AgentSession.swift
import Foundation

/// Agent 运行状态机
enum AgentState: Equatable {
    case launching
    case working
    case idle
    case done(exitCode: Int32)
    case error(String)

    var isActive: Bool {
        switch self {
        case .launching, .working, .idle: return true
        case .done, .error: return false
        }
    }

    /// 用于 tab 聚合显示的优先级（越高越重要）
    var priority: Int {
        switch self {
        case .launching: return 4
        case .error:     return 3
        case .working:   return 2
        case .idle:      return 1
        case .done:      return 0
        }
    }
}

/// Respawn 预设模式（完整配置见 RespawnMode.swift，Phase 5 填充）
enum RespawnMode: String, CaseIterable, Codable {
    case soloWork  = "solo-work"
    case teamLead  = "team-lead"
    case overnight = "overnight"
    case manual    = "manual"

    var displayName: String {
        switch self {
        case .soloWork:  return "Solo"
        case .teamLead:  return "Team"
        case .overnight: return "Night"
        case .manual:    return "Manual"
        }
    }
}

/// Token 用量（完整实现见 TokenUsage.swift，Phase 6 替换）
struct TokenUsage: Codable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cost: Decimal = 0
    var contextUtilization: Float = 0
    var compactCount: Int = 0
}

/// Subagent 信息（由 SubagentStart/Stop hook 事件填充）
struct SubagentInfo: Identifiable {
    let id: String
    var name: String
    var agentType: String
    var state: AgentState = .launching
    var startedAt: Date = Date()
    var finishedAt: Date? = nil
}

/// 一个活跃 agent 的运行时状态
struct AgentSession: Identifiable {
    let id: UUID
    let surfaceId: UUID
    let definition: AgentDefinition
    let workspaceId: UUID
    let cwd: String
    var state: AgentState = .launching
    var claudeSessionId: String? = nil
    var shellPid: Int32 = 0
    var startedAt: Date = Date()
    var lastEventAt: Date = Date()
    var respawnMode: RespawnMode = .manual
    var tokenUsage: TokenUsage = TokenUsage()
    var subagents: [String: SubagentInfo] = [:]
}
```

- [ ] **Step 2：Xcode 添加文件 → 编译检查**

```bash
cd .worktrees/workspace-ai-agent && make check
```

- [ ] **Step 3：Commit**

```bash
cd .worktrees/workspace-ai-agent
git add macos/Sources/Features/Agent/AgentSession.swift macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "feat(agent): add AgentSession data model and state machine"
```

---

### Task 1.3：AgentSessionManager

**Files:**
- Create: `macos/Sources/Features/Agent/AgentSessionManager.swift`

- [ ] **Step 1：创建 AgentSessionManager.swift**

```swift
// macos/Sources/Features/Agent/AgentSessionManager.swift
import Foundation
import Combine

@MainActor
final class AgentSessionManager: ObservableObject {
    @Published private(set) var sessions: [UUID: AgentSession] = [:]  // surfaceId → session
    private var claudeSessionIndex: [String: UUID] = [:]              // claudeSessionId → surfaceId

    // MARK: - 生命周期

    func register(_ session: AgentSession) {
        sessions[session.surfaceId] = session
    }

    func remove(surfaceId: UUID) {
        if let sid = sessions[surfaceId]?.claudeSessionId {
            claudeSessionIndex.removeValue(forKey: sid)
        }
        sessions.removeValue(forKey: surfaceId)
    }

    func removeAll(for workspaceId: UUID) {
        sessions.filter { $0.value.workspaceId == workspaceId }
               .map(\.key)
               .forEach { remove(surfaceId: $0) }
    }

    // MARK: - 状态更新

    func updateState(_ state: AgentState, surfaceId: UUID) {
        sessions[surfaceId]?.state = state
        sessions[surfaceId]?.lastEventAt = Date()
    }

    func bindClaudeSession(surfaceId: UUID, claudeSessionId: String) {
        sessions[surfaceId]?.claudeSessionId = claudeSessionId
        claudeSessionIndex[claudeSessionId] = surfaceId
    }

    func updateFromClaudeSession(_ claudeSessionId: String, _ update: (inout AgentSession) -> Void) {
        guard let surfaceId = claudeSessionIndex[claudeSessionId],
              sessions[surfaceId] != nil else { return }
        update(&sessions[surfaceId]!)
        sessions[surfaceId]?.lastEventAt = Date()
    }

    // MARK: - 查询

    func session(for surfaceId: UUID) -> AgentSession? { sessions[surfaceId] }

    func session(forClaudeSessionId id: String) -> AgentSession? {
        guard let surfaceId = claudeSessionIndex[id] else { return nil }
        return sessions[surfaceId]
    }

    /// cwd 匹配、尚未绑定 claudeSessionId 的候选 surface（用于 SessionStart 关联）
    func candidateSurfaces(for cwd: String) -> [UUID] {
        sessions.filter { $0.value.cwd == cwd && $0.value.claudeSessionId == nil }.map(\.key)
    }

    /// 给定 workspaceId 的聚合状态（最高优先级）
    func aggregateState(for workspaceId: UUID) -> AgentState? {
        sessions.values
                .filter { $0.workspaceId == workspaceId }
                .max(by: { $0.state.priority < $1.state.priority })?.state
    }

    // MARK: - Hook 事件处理（Phase 2 填充 HookServer 后调用此处）

    func processHookEvent(_ payload: HookPayload) {
        switch payload.hookEventName {
        case .sessionStart:
            bindOrCreateSession(payload: payload)
        case .sessionEnd:
            updateFromClaudeSession(payload.sessionId) { $0.state = .done(exitCode: 0) }
        case .preToolUse, .postToolUse:
            updateFromClaudeSession(payload.sessionId) { $0.state = .working }
        case .notification:
            if payload.notificationType == "idle_prompt" {
                updateFromClaudeSession(payload.sessionId) { $0.state = .idle }
            }
        case .stop:
            updateFromClaudeSession(payload.sessionId) { $0.state = .idle }
        case .subagentStart:
            if let agentId = payload.agentId, let name = payload.agentName {
                updateFromClaudeSession(payload.sessionId) {
                    $0.subagents[agentId] = SubagentInfo(
                        id: agentId, name: name,
                        agentType: payload.agentType ?? "subagent"
                    )
                }
            }
        case .subagentStop:
            if let agentId = payload.agentId {
                updateFromClaudeSession(payload.sessionId) {
                    $0.subagents[agentId]?.state = .done(exitCode: 0)
                    $0.subagents[agentId]?.finishedAt = Date()
                }
            }
        default:
            break
        }
    }

    private func bindOrCreateSession(payload: HookPayload) {
        if let surfaceId = candidateSurfaces(for: payload.cwd).first {
            bindClaudeSession(surfaceId: surfaceId, claudeSessionId: payload.sessionId)
            updateState(.working, surfaceId: surfaceId)
        }
    }
}
```

- [ ] **Step 2：Xcode 添加文件 → 编译检查**

```bash
cd .worktrees/workspace-ai-agent && make check
```

注意：`HookPayload` 类型在 Phase 2 才创建，此处会报编译错误。先在文件末尾用占位类型通过编译：

```swift
// 占位（Phase 2 替换为 HookServer/HookEvent.swift 中的真实类型）
struct HookPayload {
    enum EventType { case sessionStart, sessionEnd, preToolUse, postToolUse
                     case notification, stop, subagentStart, subagentStop
                     case preCompact, postCompact, unknown }
    let hookEventName: EventType
    let sessionId: String
    let cwd: String
    let notificationType: String?
    let transcriptPath: String?
    let agentId: String?
    let agentName: String?
    let agentType: String?
}
```

- [ ] **Step 3：Commit**

```bash
cd .worktrees/workspace-ai-agent
git add macos/Sources/Features/Agent/AgentSessionManager.swift macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "feat(agent): add AgentSessionManager with hook event routing"
```

---

### Task 1.4：AgentService 骨架 + AppDelegate 集成

**Files:**
- Create: `macos/Sources/Features/Agent/AgentService.swift`
- Modify: `macos/Sources/App/macOS/AppDelegate.swift`
- Modify: `macos/Sources/Features/Workspace/WorkspaceManager.swift`

- [ ] **Step 1：创建 AgentService.swift**

```swift
// macos/Sources/Features/Agent/AgentService.swift
import Foundation
import OSLog

@MainActor
final class AgentService {
    static let shared = AgentService()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "AgentService"
    )

    let registry = AgentRegistry.shared
    let sessionManager = AgentSessionManager()

    // 后续 Phase 填充（声明为可选，避免循环依赖）
    // var hookServer: HookServer?
    // var respawnController: RespawnController?
    // var tokenTracker: TokenTracker?

    private init() {}

    func start() {
        Self.logger.info("AgentService starting")
        // Phase 2: hookServer = HookServer(sessionManager: sessionManager); hookServer?.start()
        Self.logger.info("AgentService started")
    }

    func cleanupForWorkspace(id: UUID) {
        sessionManager.removeAll(for: id)
        // Phase 2: cleanup hook injection for workspace rootDir
        Self.logger.info("Cleaned up sessions for workspace \(id)")
    }

    func shutdown() {
        Self.logger.info("AgentService shutting down")
        // Phase 2: hookServer?.stop()
    }

    func injectHooks(for cwd: String) {
        // Phase 2: guard let port = hookServer?.port, port > 0 else { return }
        // HookInjector.inject(cwd: cwd, port: port)
    }

    func cleanupHooks(for cwd: String) {
        // Phase 2: HookInjector.cleanup(cwd: cwd)
    }
}
```

- [ ] **Step 2：在 AppDelegate.applicationDidFinishLaunching 末尾添加**

找到 `applicationDidFinishLaunching`（约第 211 行），在方法末尾添加：

```swift
Task { @MainActor in
    AgentService.shared.start()
}
```

- [ ] **Step 3：在 AppDelegate.applicationWillTerminate 中添加**

在 `isTerminating = true` 之后添加：

```swift
AgentService.shared.shutdown()
```

- [ ] **Step 4：在 WorkspaceManager.delete 中添加清理**

在 `workspaces.removeAll { $0.id == id }` 之前添加：

```swift
Task { @MainActor in
    AgentService.shared.cleanupForWorkspace(id: id)
}
```

- [ ] **Step 5：编译检查**

```bash
cd .worktrees/workspace-ai-agent && make check
```

- [ ] **Step 6：Commit**

```bash
cd .worktrees/workspace-ai-agent
git add macos/Sources/Features/Agent/AgentService.swift \
        macos/Sources/App/macOS/AppDelegate.swift \
        macos/Sources/Features/Workspace/WorkspaceManager.swift \
        macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "feat(agent): add AgentService skeleton and wire into app lifecycle"
```

---

### Task 1.5：WorkspaceManager 存储迁移

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceManager.swift`

目标：`{UUID}.json` → `{UUID}/workspace.json`，启动时自动迁移旧格式。

- [ ] **Step 1：在 WorkspaceManager 中添加目录路径方法**

找到 `private func snapshotPath(for id: UUID)` 方法（约第 266 行），在其上方插入：

```swift
/// Workspace 数据目录（新格式）：{storageDir}/{UUID}/
func workspaceDir(for id: UUID) -> String {
    (storageDir as NSString).appendingPathComponent(id.uuidString)
}

/// 旧格式路径（仅用于迁移检测）
private func legacySnapshotPath(for id: UUID) -> String {
    (storageDir as NSString).appendingPathComponent("\(id.uuidString).json")
}
```

- [ ] **Step 2：修改 snapshotPath 指向新格式**

将现有 `snapshotPath` 方法替换为：

```swift
private func snapshotPath(for id: UUID) -> String {
    let dir = workspaceDir(for: id)
    return (dir as NSString).appendingPathComponent("workspace.json")
}
```

- [ ] **Step 3：修改 save 方法，写入前确保目录存在**

找到 `private func save(_ workspace: WorkspaceModel)` 方法，在方法开头（`guard !workspace.isTemporary` 之后）添加：

```swift
let dir = workspaceDir(for: workspace.id)
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
```

- [ ] **Step 4：修改 loadAll 支持新格式 + 自动迁移旧格式**

将 `loadAll()` 方法替换为：

```swift
private func loadAll() {
    let fm = FileManager.default
    var loadedIds = Set<UUID>()

    // 加载新格式：{UUID}/ 目录
    if let entries = try? fm.contentsOfDirectory(atPath: storageDir) {
        for entry in entries {
            guard UUID(uuidString: entry) != nil else { continue }
            let dirPath = (storageDir as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else { continue }
            let filePath = (dirPath as NSString).appendingPathComponent("workspace.json")
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
                  let snapshot = try? decoder.decode(WorkspaceSnapshot.self, from: data) else { continue }
            workspaces.append(snapshot.workspace)
            loadedIds.insert(snapshot.workspace.id)
        }
    }

    // 迁移旧格式：{UUID}.json
    if let files = try? fm.contentsOfDirectory(atPath: storageDir) {
        for file in files where file.hasSuffix(".json") {
            let uuidStr = (file as NSString).deletingPathExtension
            guard let uuid = UUID(uuidString: uuidStr), !loadedIds.contains(uuid) else { continue }
            let legacyPath = (storageDir as NSString).appendingPathComponent(file)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: legacyPath)),
                  let snapshot = try? decoder.decode(WorkspaceSnapshot.self, from: data) else { continue }
            migrateLegacySnapshot(snapshot, legacyPath: legacyPath)
            workspaces.append(snapshot.workspace)
        }
    }

    workspaces.sort { $0.createdAt < $1.createdAt }
}

private func migrateLegacySnapshot(_ snapshot: WorkspaceSnapshot, legacyPath: String) {
    let newDir = workspaceDir(for: snapshot.workspace.id)
    try? FileManager.default.createDirectory(atPath: newDir, withIntermediateDirectories: true)
    let newPath = snapshotPath(for: snapshot.workspace.id)
    guard let data = try? encoder.encode(snapshot) else { return }
    let tmpPath = newPath + ".tmp"
    guard (try? data.write(to: URL(fileURLWithPath: tmpPath))) != nil else { return }
    try? FileManager.default.moveItem(atPath: tmpPath, toPath: newPath)
    try? FileManager.default.removeItem(atPath: legacyPath)
}
```

- [ ] **Step 5：修改 delete 方法删除整个目录**

找到 `let path = snapshotPath(for: id)` 那一行（在 delete 方法中），替换为：

```swift
let dirPath = workspaceDir(for: id)
try? FileManager.default.removeItem(atPath: dirPath)
let legacyPath = legacySnapshotPath(for: id)
try? FileManager.default.removeItem(atPath: legacyPath)
```

并删除原来的 `try? FileManager.default.removeItem(atPath: path)` 这行。

- [ ] **Step 6：编译检查**

```bash
cd .worktrees/workspace-ai-agent && make check
```

- [ ] **Step 7：手动验证存储迁移**

```bash
make run-dev
# 确认 workspace 正常加载
# ls ~/.config/poltertty/workspaces/ 应出现 {UUID}/ 目录
```

- [ ] **Step 8：Commit**

```bash
cd .worktrees/workspace-ai-agent
git add macos/Sources/Features/Workspace/WorkspaceManager.swift
git commit -m "feat(storage): migrate workspace storage to per-UUID directory format"
```

---

## Phase 2：HookServer

### Task 2.1：HookEvent 类型定义

**Files:**
- Create: `macos/Sources/Features/Agent/HookServer/HookEvent.swift`

- [ ] **Step 1：创建 HookEvent.swift**

```swift
// macos/Sources/Features/Agent/HookServer/HookEvent.swift
import Foundation

enum HookEventType: String, Decodable {
    case sessionStart   = "SessionStart"
    case sessionEnd     = "SessionEnd"
    case notification   = "Notification"
    case preToolUse     = "PreToolUse"
    case postToolUse    = "PostToolUse"
    case stop           = "Stop"
    case subagentStart  = "SubagentStart"
    case subagentStop   = "SubagentStop"
    case preCompact     = "PreCompact"
    case postCompact    = "PostCompact"
    case unknown
}

struct HookPayload: Decodable {
    let hookEventName: HookEventType
    let sessionId: String
    let cwd: String
    let notificationType: String?
    let transcriptPath: String?
    let agentId: String?
    let agentName: String?
    let agentType: String?

    enum CodingKeys: String, CodingKey {
        case hookEventName   = "hook_event_name"
        case sessionId       = "session_id"
        case cwd
        case notificationType = "notification_type"
        case transcriptPath  = "transcript_path"
        case agentId         = "agent_id"
        case agentName       = "agent_name"
        case agentType       = "agent_type"
    }
}
```

- [ ] **Step 2：删除 AgentSessionManager.swift 中的占位 HookPayload**

删除 Task 1.3 中临时加入的占位 `struct HookPayload { ... }` 块。

- [ ] **Step 3：Xcode 添加文件 → 编译检查**

```bash
cd .worktrees/workspace-ai-agent && make check
```

- [ ] **Step 4：Commit**

```bash
cd .worktrees/workspace-ai-agent
git add macos/Sources/Features/Agent/HookServer/HookEvent.swift \
        macos/Sources/Features/Agent/AgentSessionManager.swift \
        macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "feat(agent): add HookEvent payload types, replace placeholder"
```

---

### Task 2.2：HookServer（内嵌 HTTP）

**Files:**
- Create: `macos/Sources/Features/Agent/HookServer/HookServer.swift`

- [ ] **Step 1：创建 HookServer.swift**

```swift
// macos/Sources/Features/Agent/HookServer/HookServer.swift
import Foundation
import Network
import OSLog

/// 内嵌 HTTP server，接收 Claude Code hook 事件
/// 绑定 localhost 固定端口，多个 Poltertty 实例共享同一 server
final class HookServer {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "HookServer"
    )

    static let defaultPort: UInt16 = 19198
    static let maxPortRetries: Int = 10

    private static let lockFilePath: String = {
        let base = ("~/.config/poltertty" as NSString).expandingTildeInPath
        return (base as NSString).appendingPathComponent("hook-server.json")
    }()

    private struct LockFile: Codable {
        let port: UInt16
        let pid: Int32
    }

    private var listener: NWListener?
    private(set) var port: UInt16 = 0

    private let sessionManager: AgentSessionManager
    private let decoder = JSONDecoder()

    init(sessionManager: AgentSessionManager) {
        self.sessionManager = sessionManager
    }

    // MARK: - 生命周期

    func start() {
        if tryReuseExisting() { return }
        for offset in 0..<Self.maxPortRetries {
            let candidate = Self.defaultPort + UInt16(offset)
            if tryListen(on: candidate) {
                writeLockFile(port: candidate)
                Self.logger.info("HookServer listening on port \(candidate)")
                return
            }
        }
        Self.logger.error("HookServer: failed to bind any port")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        removeLockFile()
    }

    // MARK: - 多实例协调

    private func tryReuseExisting() -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: Self.lockFilePath)),
              let lock = try? JSONDecoder().decode(LockFile.self, from: data) else { return false }
        guard kill(lock.pid, 0) == 0 else {
            try? FileManager.default.removeItem(atPath: Self.lockFilePath)
            return false
        }
        if lock.pid == getpid() { return false }
        self.port = lock.port
        Self.logger.info("HookServer: reusing port \(lock.port) from PID \(lock.pid)")
        return true
    }

    private func tryListen(on port: UInt16) -> Bool {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let portObj = NWEndpoint.Port(rawValue: port),
              let listener = try? NWListener(using: params, on: portObj) else { return false }

        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:   success = true; semaphore.signal()
            case .failed:  semaphore.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in self?.handleConnection(conn) }
        listener.start(queue: .global(qos: .utility))
        semaphore.wait()

        if success { self.listener = listener; self.port = port }
        return success
    }

    // MARK: - HTTP 处理

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self, let data, !data.isEmpty else { return }
            self.processRequest(data: data, connection: connection)
        }
    }

    private func processRequest(data: Data, connection: NWConnection) {
        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A])
        guard let range = data.range(of: separator) else {
            sendResponse(connection, status: 400, body: "Bad Request"); return
        }
        let headerStr = String(data: data[..<range.lowerBound], encoding: .utf8) ?? ""
        let firstLine = headerStr.components(separatedBy: "\r\n").first ?? ""

        if firstLine.hasPrefix("GET /health") {
            sendResponse(connection, status: 200, body: "ok"); return
        }
        guard firstLine.hasPrefix("POST /hook") else {
            sendResponse(connection, status: 404, body: "Not Found"); return
        }

        let bodyData = data[range.upperBound...]
        guard let payload = try? decoder.decode(HookPayload.self, from: bodyData) else {
            Self.logger.warning("HookServer: failed to decode hook payload")
            sendResponse(connection, status: 400, body: "Invalid JSON"); return
        }
        sendResponse(connection, status: 200, body: "ok")
        Task { @MainActor in self.sessionManager.processHookEvent(payload) }
    }

    private func sendResponse(_ connection: NWConnection, status: Int, body: String) {
        let bodyData = (body.data(using: .utf8)) ?? Data()
        let header = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\nContent-Length: \(bodyData.count)\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n"
        var resp = header.data(using: .utf8)!
        resp.append(bodyData)
        connection.send(content: resp, completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: - 锁文件

    private func writeLockFile(port: UInt16) {
        let lock = LockFile(port: port, pid: getpid())
        let dir = ("~/.config/poltertty" as NSString).expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(lock).write(to: URL(fileURLWithPath: Self.lockFilePath))
    }

    private func removeLockFile() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: Self.lockFilePath)),
              let lock = try? JSONDecoder().decode(LockFile.self, from: data),
              lock.pid == getpid() else { return }
        try? FileManager.default.removeItem(atPath: Self.lockFilePath)
    }
}
```

- [ ] **Step 2：在 AgentService 启动 HookServer**

在 `AgentService.swift` 中，将注释的 `hookServer` 声明和 start/stop 代码取消注释：

```swift
// 替换 AgentService.swift 中的注释占位
var hookServer: HookServer?

// 在 start() 中
hookServer = HookServer(sessionManager: sessionManager)
hookServer?.start()

// 在 shutdown() 中
hookServer?.stop()

// 在 injectHooks(for:) 中
guard let port = hookServer?.port, port > 0 else { return }
HookInjector.inject(cwd: cwd, port: port)

// 在 cleanupHooks(for:) 中
HookInjector.cleanup(cwd: cwd)
```

（HookInjector 在 Task 2.3 创建，先保留注释）

- [ ] **Step 3：Xcode 添加文件 → 编译检查**

```bash
cd .worktrees/workspace-ai-agent && make check
```

- [ ] **Step 4：Commit**

```bash
cd .worktrees/workspace-ai-agent
git add macos/Sources/Features/Agent/HookServer/HookServer.swift \
        macos/Sources/Features/Agent/AgentService.swift \
        macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "feat(agent): add HookServer NWListener with multi-instance coordination"
```

---

### Task 2.3：HookInjector

**Files:**
- Create: `macos/Sources/Features/Agent/HookServer/HookInjector.swift`

- [ ] **Step 1：创建 HookInjector.swift**

```swift
// macos/Sources/Features/Agent/HookServer/HookInjector.swift
import Foundation
import OSLog

/// 向项目目录注入 Claude Code hook 配置（项目级 .local.json，不修改全局配置）
final class HookInjector {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "HookInjector"
    )

    private static let marker = "_poltertty"

    private static let hookEventNames = [
        "SessionStart", "SessionEnd", "Notification",
        "PreToolUse", "PostToolUse", "Stop",
        "SubagentStart", "SubagentStop", "PreCompact", "PostCompact"
    ]

    static func inject(cwd: String, port: UInt16) {
        let path = settingsPath(cwd: cwd)
        let url = "http://localhost:\(port)/hook"
        modifySettings(at: path) { settings in
            var hooks = settings["hooks"] as? [String: Any] ?? [:]
            let entry: [String: Any] = ["type": "http", "url": url, marker: true]
            let wrapper: [String: Any] = ["hooks": [entry]]
            for event in hookEventNames {
                var list = hooks[event] as? [[String: Any]] ?? []
                list.removeAll { ($0[marker] as? Bool) == true }
                list.append(wrapper)
                hooks[event] = list
            }
            settings["hooks"] = hooks
        }
    }

    static func cleanup(cwd: String) {
        let path = settingsPath(cwd: cwd)
        guard FileManager.default.fileExists(atPath: path) else { return }
        modifySettings(at: path) { settings in
            guard var hooks = settings["hooks"] as? [String: Any] else { return }
            for event in hookEventNames {
                if var list = hooks[event] as? [[String: Any]] {
                    list.removeAll { entry in
                        (entry[marker] as? Bool) == true ||
                        ((entry["hooks"] as? [[String: Any]])?.contains { ($0[marker] as? Bool) == true } ?? false)
                    }
                    hooks[event] = list.isEmpty ? nil : list
                }
            }
            settings["hooks"] = hooks.isEmpty ? nil : hooks
        }
    }

    // MARK: - Private

    private static func settingsPath(cwd: String) -> String {
        let claudeDir = (cwd as NSString).appendingPathComponent(".claude")
        return (claudeDir as NSString).appendingPathComponent("settings.local.json")
    }

    private static func modifySettings(at path: String, modify: (inout [String: Any]) -> Void) {
        let fileURL = URL(fileURLWithPath: path)
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordError) { writeURL in
            var settings: [String: Any] = [:]
            if let data = try? Data(contentsOf: writeURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                settings = json
            }
            let claudeDir = (path as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)
            modify(&settings)
            guard let newData = try? JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted) else { return }
            let tmpURL = writeURL.appendingPathExtension("tmp")
            try? newData.write(to: tmpURL)
            try? FileManager.default.moveItem(at: tmpURL, to: writeURL)
        }
        if let err = coordError { logger.error("HookInjector coordinator error: \(err)") }
    }
}
```

- [ ] **Step 2：在 AgentService 取消 HookInjector 注释**

取消 `injectHooks` 和 `cleanupHooks` 中的注释，让其调用 `HookInjector`。

- [ ] **Step 3：编译检查**

```bash
cd .worktrees/workspace-ai-agent && make check
```

- [ ] **Step 4：Commit**

```bash
cd .worktrees/workspace-ai-agent
git add macos/Sources/Features/Agent/HookServer/HookInjector.swift \
        macos/Sources/Features/Agent/AgentService.swift \
        macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "feat(agent): add HookInjector for non-invasive hook config injection"
```

---

### Task 2.4：ProcessMonitor

**Files:**
- Create: `macos/Sources/Features/Agent/Monitoring/ProcessMonitor.swift`

- [ ] **Step 1：创建 ProcessMonitor.swift**

```swift
// macos/Sources/Features/Agent/Monitoring/ProcessMonitor.swift
import Foundation

/// 使用 DispatchSource 监听进程退出，作为状态感知的兜底方案
@MainActor
final class ProcessMonitor {
    private var sources: [UUID: DispatchSourceProcess] = [:]

    func watch(pid: Int32, surfaceId: UUID, onExit: @escaping @MainActor (UUID, Int32) -> Void) {
        let source = DispatchSource.makeProcessSource(
            identifier: pid_t(pid), eventMask: .exit, queue: .main
        )
        source.setEventHandler {
            let status = Int32(source.data)
            Task { @MainActor in onExit(surfaceId, status) }
        }
        source.setCancelHandler { [weak self] in
            Task { @MainActor in self?.sources.removeValue(forKey: surfaceId) }
        }
        source.resume()
        sources[surfaceId] = source
    }

    func unwatch(surfaceId: UUID) {
        sources[surfaceId]?.cancel()
        sources.removeValue(forKey: surfaceId)
    }

    func unwatchAll() {
        sources.values.forEach { $0.cancel() }
        sources.removeAll()
    }
}
```

- [ ] **Step 2：在 AgentService 集成**

在 `AgentService.swift` 添加：

```swift
let processMonitor = ProcessMonitor()

func watchProcess(pid: Int32, surfaceId: UUID) {
    processMonitor.watch(pid: pid, surfaceId: surfaceId) { [weak self] sid, exitCode in
        self?.sessionManager.updateState(.done(exitCode: exitCode), surfaceId: sid)
    }
}
```

- [ ] **Step 3：编译检查**

```bash
cd .worktrees/workspace-ai-agent && make check
```

- [ ] **Step 4：Commit**

```bash
cd .worktrees/workspace-ai-agent
git add macos/Sources/Features/Agent/Monitoring/ProcessMonitor.swift \
        macos/Sources/Features/Agent/AgentService.swift \
        macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "feat(agent): add ProcessMonitor for process exit detection"
```

---

## Phase 3：AgentLauncher UI

### Task 3.1：阅读 TerminalController 现有 API

在写 AgentLauncher 之前，必须了解 TerminalController 中已有的接口。

- [ ] **Step 1：阅读 TerminalController 关键方法**

```bash
grep -n "func\|tabBarViewModel\|ghostty_surface\|split\|newTab\|addTab\|writeToStdin\|SplitDirection" \
  .worktrees/workspace-ai-agent/macos/Sources/Features/Terminal/TerminalController.swift | head -60
```

- [ ] **Step 2：理解 surface 写入方式**

```bash
grep -n "ghostty_surface_key\|write\|input\|text" \
  .worktrees/workspace-ai-agent/macos/Sources/Ghostty/Ghostty.Surface.swift | head -30
```

记录以下信息（执行后填入）：
- 创建新 tab 的方法名：`_________`
- 创建 split 的方法名：`_________`
- 向 PTY 写文本的方式：`_________`

---

### Task 3.2：AgentLauncher + TerminalController 扩展

**Files:**
- Create: `macos/Sources/Features/Agent/Launcher/AgentLauncher.swift`
- Modify: `macos/Sources/Features/Terminal/TerminalController.swift`

- [ ] **Step 1：在 TerminalController 末尾添加 Agent 支持方法**

根据 Task 3.1 的阅读结果，在 `TerminalController.swift` 末尾添加：

```swift
// MARK: - Agent Support

/// 向指定 surface 写入文本（用于启动命令和 respawn）
func writeToSurface(text: String, surfaceId: UUID) {
    guard let surface = tabBarViewModel.surfaces[surfaceId] else { return }
    // 使用 Ghostty 的 key text 输入 API
    // 根据 Task 3.1 的结果填入正确调用方式
    // 示例（需根据实际 API 调整）：
    text.withCString { ptr in
        ghostty_surface_binding_action(surface.surface, .text, ptr)
    }
}

/// 启动 agent 菜单（Cmd+Shift+A 触发）
func launchAgentAction() {
    guard let workspaceId = self.workspaceId,
          let workspace = WorkspaceManager.shared.workspace(for: workspaceId) else { return }
    showAgentLaunchMenu(workspaceId: workspaceId, cwd: workspace.rootDirExpanded)
}

func showAgentLaunchMenu(workspaceId: UUID, cwd: String) {
    let popover = NSPopover()
    popover.behavior = .transient
    let menu = AgentLaunchMenu(
        workspaceId: workspaceId,
        cwd: cwd,
        onLaunch: { [weak self, weak popover] definition, location, respawnMode in
            popover?.close()
            AgentLauncher(terminalController: self).launch(
                definition: definition,
                location: location,
                respawnMode: respawnMode,
                workspaceId: workspaceId,
                cwd: cwd
            )
        },
        onCancel: { [weak popover] in popover?.close() }
    )
    popover.contentViewController = NSHostingController(rootView: menu)
    if let view = self.window?.contentView {
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}
```

- [ ] **Step 2：创建 AgentLauncher.swift**

```swift
// macos/Sources/Features/Agent/Launcher/AgentLauncher.swift
import Foundation
import OSLog

enum AgentLaunchLocation: CaseIterable {
    case currentPane
    case newTab
    case splitRight
    case splitBottom

    var displayName: String {
        switch self {
        case .currentPane: return "Current Pane"
        case .newTab:      return "New Tab"
        case .splitRight:  return "Split Right"
        case .splitBottom: return "Split Bottom"
        }
    }
}

@MainActor
final class AgentLauncher {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "AgentLauncher"
    )

    weak var terminalController: TerminalController?

    init(terminalController: TerminalController?) {
        self.terminalController = terminalController
    }

    func launch(
        definition: AgentDefinition,
        location: AgentLaunchLocation,
        respawnMode: RespawnMode,
        workspaceId: UUID,
        cwd: String
    ) {
        guard let tc = terminalController else { return }

        // 1. 确定目标 surfaceId（根据 location，对应 TerminalController 的已有 API）
        let surfaceId: UUID
        switch location {
        case .currentPane:
            guard let tab = tc.tabBarViewModel.tabs.first(where: { $0.isActive }) else { return }
            surfaceId = tab.surfaceId
        case .newTab:
            // 调用 TerminalController 现有的新建 tab 方法（根据 Task 3.1 调整）
            tc.newTab(nil)
            guard let tab = tc.tabBarViewModel.tabs.last else { return }
            surfaceId = tab.surfaceId
        case .splitRight:
            tc.splitRight(nil)
            guard let tab = tc.tabBarViewModel.tabs.first(where: { $0.isActive }) else { return }
            surfaceId = tab.surfaceId
        case .splitBottom:
            tc.splitDown(nil)
            guard let tab = tc.tabBarViewModel.tabs.first(where: { $0.isActive }) else { return }
            surfaceId = tab.surfaceId
        }

        // 2. 注册 session
        var session = AgentSession(
            id: UUID(),
            surfaceId: surfaceId,
            definition: definition,
            workspaceId: workspaceId,
            cwd: cwd
        )
        session.respawnMode = respawnMode
        AgentService.shared.sessionManager.register(session)

        // 3. 注入 hook 配置（仅 .full capability）
        if definition.hookCapability == .full {
            AgentService.shared.injectHooks(for: cwd)
        }

        // 4. 写入启动命令到 PTY
        tc.writeToSurface(text: "\(definition.command)\n", surfaceId: surfaceId)

        Self.logger.info("Launched \(definition.name) [\(location.displayName)] in workspace \(workspaceId)")
    }
}
```

**注意：** `tc.newTab(nil)`, `tc.splitRight(nil)`, `tc.splitDown(nil)` 需根据 Task 3.1 的实际方法名调整。

- [ ] **Step 3：编译检查**

```bash
cd .worktrees/workspace-ai-agent && make check
```

根据报错修正 API 调用方式。

- [ ] **Step 4：Commit**

```bash
cd .worktrees/workspace-ai-agent
git add macos/Sources/Features/Agent/Launcher/AgentLauncher.swift \
        macos/Sources/Features/Terminal/TerminalController.swift \
        macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "feat(agent): add AgentLauncher and TerminalController agent support"
```

---

### Task 3.3：AgentLaunchMenu SwiftUI 两步菜单

**Files:**
- Create: `macos/Sources/Features/Agent/Launcher/AgentLaunchMenu.swift`

- [ ] **Step 1：创建 AgentLaunchMenu.swift**

```swift
// macos/Sources/Features/Agent/Launcher/AgentLaunchMenu.swift
import SwiftUI

struct AgentLaunchMenu: View {
    @ObservedObject private var registry = AgentRegistry.shared
    @State private var step: Step = .selectAgent
    @State private var selectedAgent: AgentDefinition?
    @State private var location: AgentLaunchLocation = .newTab
    @State private var respawnMode: RespawnMode = .manual
    @State private var searchText = ""

    let workspaceId: UUID
    let cwd: String
    let onLaunch: (AgentDefinition, AgentLaunchLocation, RespawnMode) -> Void
    let onCancel: () -> Void

    enum Step { case selectAgent, selectLocation }

    private var filtered: [AgentDefinition] {
        guard !searchText.isEmpty else { return registry.definitions }
        return registry.definitions.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.command.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case .selectAgent:   agentSelection
            case .selectLocation: locationSelection
            }
        }
        .frame(width: 340)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 16)
    }

    // MARK: - Step 1

    private var agentSelection: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search agents...", text: $searchText).textFieldStyle(.plain)
            }
            .padding(10)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { agent in
                        AgentRow(agent: agent).contentShape(Rectangle())
                            .onTapGesture { pick(agent) }
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    private func pick(_ agent: AgentDefinition) {
        selectedAgent = agent
        if registry.definitions.count == 1 {
            onLaunch(agent, location, respawnMode)
        } else {
            step = .selectLocation
        }
    }

    // MARK: - Step 2

    private var locationSelection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { step = .selectAgent } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                Text("Launch \(selectedAgent?.name ?? "")").font(.system(size: 13, weight: .semibold))
            }
            .padding(12)
            Divider()
            VStack(spacing: 0) {
                ForEach(AgentLaunchLocation.allCases, id: \.self) { loc in
                    HStack {
                        Image(systemName: location == loc ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(location == loc ? Color.accentColor : .secondary)
                        Text(loc.displayName).font(.system(size: 13))
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .contentShape(Rectangle())
                    .onTapGesture { location = loc }
                }
            }
            .padding(.vertical, 4)
            Divider()
            HStack(spacing: 4) {
                Text("Respawn:").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                ForEach(RespawnMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).font(.system(size: 11))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(respawnMode == mode ? Color.accentColor.opacity(0.2) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .onTapGesture { respawnMode = mode }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            HStack {
                Button("Cancel") { onCancel() }.keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button("Launch") {
                    if let a = selectedAgent { onLaunch(a, location, respawnMode) }
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
    }
}

private struct AgentRow: View {
    let agent: AgentDefinition
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            Text(agent.icon).font(.system(size: 16)).frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(agent.name).font(.system(size: 13))
                Text(agent.command).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            hookBadge
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(hovered ? Color(.selectedContentBackgroundColor).opacity(0.3) : .clear)
        .onHover { hovered = $0 }
    }

    @ViewBuilder private var hookBadge: some View {
        switch agent.hookCapability {
        case .full:
            Text("hooks").font(.system(size: 10)).padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.green.opacity(0.15)).foregroundStyle(.green)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        case .commandOnly:
            Text("cmd").font(.system(size: 10)).padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.yellow.opacity(0.15)).foregroundStyle(.yellow)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        case .none:
            EmptyView()
        }
    }
}
```

- [ ] **Step 2：注册 Cmd+Shift+A 快捷键**

在 `TerminalController.swift` 中找到快捷键处理位置（搜索 `keyDown` 或 `performAction`），添加：

```swift
// 在处理快捷键的适当位置（根据 TerminalController 现有模式）
// Cmd+Shift+A → launchAgentAction()
```

具体位置需阅读 TerminalController 的快捷键注册方式后确定。

- [ ] **Step 3：编译检查**

```bash
cd .worktrees/workspace-ai-agent && make check
```

- [ ] **Step 4：手动测试**

```bash
make run-dev
# 触发 launchAgentAction()，确认两步菜单正常显示
# 选择 Claude Code → New Tab → 确认命令写入 PTY
```

- [ ] **Step 5：Commit**

```bash
cd .worktrees/workspace-ai-agent
git add macos/Sources/Features/Agent/Launcher/AgentLaunchMenu.swift \
        macos/Sources/Features/Terminal/TerminalController.swift \
        macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "feat(agent): add AgentLaunchMenu two-step SwiftUI dropdown with Cmd+Shift+A"
```

---

## Phase 4：状态可视化

### Task 4.1：Tab Bar Agent 状态圆点

**Files:**
- Modify: `macos/Sources/Features/Workspace/TabBar/TabBarViewModel.swift`
- Modify: `macos/Sources/Features/Workspace/TabBar/TerminalTabItem.swift`
- Modify: `macos/Sources/Features/Workspace/TabBar/TerminalTabBar.swift`

- [ ] **Step 1：在 TabBarViewModel 添加 agent 查询**

在 `TabBarViewModel.swift` 末尾添加：

```swift
// MARK: - Agent 状态查询

func agentState(for surfaceId: UUID) -> AgentState? {
    AgentService.shared.sessionManager.session(for: surfaceId)?.state
}

func agentCostDisplay(for surfaceId: UUID) -> String? {
    guard let cost = AgentService.shared.sessionManager.session(for: surfaceId)?.tokenUsage.cost,
          cost > 0 else { return nil }
    return String(format: "$%.2f", NSDecimalNumber(decimal: cost).doubleValue)
}
```

- [ ] **Step 2：在 TerminalTabItem 添加 agentState 属性和 AgentStateDot 视图**

在 `TerminalTabItem.swift` 的 `TerminalTabItem` 结构体属性列表中添加（找到 `let onCloseOthers` 后）：

```swift
var agentState: AgentState? = nil
```

在显示 `Text(tab.title)` 的 HStack 中，在标题后插入：

```swift
if let state = agentState {
    AgentStateDot(state: state)
}
```

在文件末尾添加 AgentStateDot：

```swift
struct AgentStateDot: View {
    let state: AgentState
    @State private var pulse = false

    var color: Color {
        switch state {
        case .launching: return .blue
        case .working:   return .green
        case .idle:      return .yellow
        case .error:     return .red
        case .done:      return .secondary
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(state == .working ? (pulse ? 1.0 : 0.35) : 1.0)
            .animation(state == .working
                ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                : .default,
                value: pulse)
            .onAppear { pulse = true }
    }
}
```

- [ ] **Step 3：在 TerminalTabBar 传入 agentState**

找到 `TerminalTabBar.swift` 中创建 `TerminalTabItem` 的位置，添加 `agentState` 参数：

```swift
TerminalTabItem(
    tab: tab,
    // ... 现有参数 ...
    agentState: viewModel.agentState(for: tab.surfaceId),
    // ...
)
```

- [ ] **Step 4：编译检查**

```bash
cd .worktrees/workspace-ai-agent && make check
```

- [ ] **Step 5：Commit**

```bash
cd .worktrees/workspace-ai-agent
git add macos/Sources/Features/Workspace/TabBar/TabBarViewModel.swift \
        macos/Sources/Features/Workspace/TabBar/TerminalTabItem.swift \
        macos/Sources/Features/Workspace/TabBar/TerminalTabBar.swift
git commit -m "feat(agent): add agent status dot to tab bar"
```

---

### Task 4.2：Agent Monitor Panel

**Files:**
- Create: `macos/Sources/Features/Agent/Monitor/AgentMonitorViewModel.swift`
- Create: `macos/Sources/Features/Agent/Monitor/AgentMonitorPanel.swift`
- Create: `macos/Sources/Features/Agent/Monitor/SubagentListView.swift`
- Modify: `macos/Sources/Features/Workspace/PolterttyRootView.swift`

- [ ] **Step 1：创建 AgentMonitorViewModel.swift**

```swift
// macos/Sources/Features/Agent/Monitor/AgentMonitorViewModel.swift
import Foundation
import Combine

@MainActor
final class AgentMonitorViewModel: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var width: CGFloat = 280

    let workspaceId: UUID
    private var cancellables = Set<AnyCancellable>()

    init(workspaceId: UUID) {
        self.workspaceId = workspaceId
        AgentService.shared.sessionManager.$sessions
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var sessions: [AgentSession] {
        AgentService.shared.sessionManager.sessions.values
            .filter { $0.workspaceId == workspaceId }
            .sorted { $0.startedAt < $1.startedAt }
    }

    func toggle() { isVisible.toggle() }
}
```

- [ ] **Step 2：创建 SubagentListView.swift**

```swift
// macos/Sources/Features/Agent/Monitor/SubagentListView.swift
import SwiftUI

struct SubagentListView: View {
    let subagents: [SubagentInfo]
    @State private var expanded = Set<String>()

    var body: some View {
        if subagents.isEmpty {
            Text("No subagents").font(.system(size: 11)).foregroundStyle(.tertiary)
                .padding(.horizontal, 12).padding(.vertical, 4)
        } else {
            ForEach(subagents) { agent in
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        AgentStateDot(state: agent.state)
                        Text(agent.name).font(.system(size: 11))
                        Text(agent.agentType).font(.system(size: 10)).foregroundStyle(.tertiary)
                        Spacer()
                        Image(systemName: expanded.contains(agent.id) ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if expanded.contains(agent.id) { expanded.remove(agent.id) }
                        else { expanded.insert(agent.id) }
                    }
                    if expanded.contains(agent.id) {
                        Text("Transcript unavailable")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                            .padding(.horizontal, 12).padding(.bottom, 6)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 3：创建 AgentMonitorPanel.swift**

```swift
// macos/Sources/Features/Agent/Monitor/AgentMonitorPanel.swift
import SwiftUI

struct AgentMonitorPanel: View {
    @ObservedObject var viewModel: AgentMonitorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Text("Agents").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { viewModel.toggle() } label: {
                    Image(systemName: "xmark").font(.system(size: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(.windowBackgroundColor))
            Divider()

            if viewModel.sessions.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Text("No active agents").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("⌘⇧A to launch").font(.system(size: 11)).foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.sessions) { session in
                            AgentSessionRow(session: session)
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(width: viewModel.width)
        .background(Color(.windowBackgroundColor))
    }
}

private struct AgentSessionRow: View {
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(session.definition.icon)
                Text(session.definition.name).font(.system(size: 12, weight: .medium))
                Spacer()
                AgentStateDot(state: session.state)
                Text(stateLabel).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.top, 10)

            if session.tokenUsage.contextUtilization > 0 {
                ContextBar(utilization: session.tokenUsage.contextUtilization)
                    .padding(.horizontal, 12)
            }

            if !session.subagents.isEmpty {
                Text("Subagents (\(session.subagents.count))")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                SubagentListView(subagents: Array(session.subagents.values))
            }

            HStack {
                Text(session.respawnMode.displayName).font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                if session.tokenUsage.cost > 0 {
                    Text(String(format: "$%.2f", NSDecimalNumber(decimal: session.tokenUsage.cost).doubleValue))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 10)
        }
    }

    private var stateLabel: String {
        switch session.state {
        case .launching:      return "Starting..."
        case .working:        return "Working"
        case .idle:           return "Idle"
        case .done:           return "Done"
        case .error(let m):   return "Error: \(m)"
        }
    }
}

private struct ContextBar: View {
    let utilization: Float

    var color: Color {
        utilization < 0.55 ? .green : utilization < 0.75 ? .yellow : .red
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Color(.separatorColor)).frame(height: 4)
                RoundedRectangle(cornerRadius: 2).fill(color)
                    .frame(width: geo.size.width * CGFloat(utilization), height: 4)
            }
        }
        .frame(height: 4)
    }
}
```

- [ ] **Step 4：将 AgentMonitorPanel 集成到 PolterttyRootView**

先阅读当前 PolterttyRootView.swift 中 FileBrowserPanel 的集成方式：

```bash
cat .worktrees/workspace-ai-agent/macos/Sources/Features/Workspace/PolterttyRootView.swift
```

然后参考 FileBrowserPanel 的模式，在右侧添加 AgentMonitorPanel：
- 在 PolterttyRootView 中添加 `@StateObject private var agentMonitorVM: AgentMonitorViewModel`
- 在布局 HStack 中，在主内容区右侧添加 `if agentMonitorVM.isVisible { AgentMonitorPanel(viewModel: agentMonitorVM) }`
- 注册 `Cmd+Shift+M` 快捷键（`.keyboardShortcut("m", modifiers: [.command, .shift])`）

- [ ] **Step 5：编译检查**

```bash
cd .worktrees/workspace-ai-agent && make check
```

- [ ] **Step 6：Commit**

```bash
cd .worktrees/workspace-ai-agent
git add macos/Sources/Features/Agent/Monitor/ \
        macos/Sources/Features/Workspace/PolterttyRootView.swift \
        macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "feat(agent): add Agent Monitor Panel with Cmd+Shift+M toggle"
```

---

## Phase 5：RespawnController

### Task 5.1：RespawnMode 完整配置

**Files:**
- Create: `macos/Sources/Features/Agent/Respawn/RespawnMode.swift`
- Modify: `macos/Sources/Features/Agent/AgentSession.swift`（删除简单 RespawnMode 定义，改为 import）

- [ ] **Step 1：创建 RespawnMode.swift**

```swift
// macos/Sources/Features/Agent/Respawn/RespawnMode.swift
import Foundation

struct RespawnConfig {
    let idleThresholdSeconds: TimeInterval?  // nil = 不自动 respawn
    let maxRuntimeMinutes: Int?              // nil = 无限制
    let compactThreshold: Float?            // context 使用率触发 /compact
    let clearThreshold: Float?              // compact 后仍超阈值触发 /clear（overnight 专用）
}

extension RespawnMode {
    var config: RespawnConfig {
        switch self {
        case .soloWork:  return RespawnConfig(idleThresholdSeconds: 3,   maxRuntimeMinutes: 60,  compactThreshold: 0.55, clearThreshold: nil)
        case .teamLead:  return RespawnConfig(idleThresholdSeconds: 90,  maxRuntimeMinutes: 480, compactThreshold: 0.55, clearThreshold: nil)
        case .overnight: return RespawnConfig(idleThresholdSeconds: 10,  maxRuntimeMinutes: nil, compactThreshold: 0.55, clearThreshold: 0.70)
        case .manual:    return RespawnConfig(idleThresholdSeconds: nil,  maxRuntimeMinutes: nil, compactThreshold: nil,  clearThreshold: nil)
        }
    }
}
```

- [ ] **Step 2：编译检查**

```bash
cd .worktrees/workspace-ai-agent && make check
```

- [ ] **Step 3：Commit**

```bash
cd .worktrees/workspace-ai-agent
git add macos/Sources/Features/Agent/Respawn/RespawnMode.swift \
        macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "feat(agent): add RespawnMode config for all preset modes"
```

---

### Task 5.2：RespawnController

**Files:**
- Create: `macos/Sources/Features/Agent/Respawn/RespawnController.swift`

- [ ] **Step 1：创建 RespawnController.swift**

```swift
// macos/Sources/Features/Agent/Respawn/RespawnController.swift
import Foundation
import OSLog

@MainActor
final class RespawnController {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "RespawnController"
    )

    struct CircuitBreaker {
        var noProgressCount: Int = 0
        var isOpen: Bool = false      // ≥5 次无进展，停止 respawn
        var isHalfOpen: Bool = false  // ≥3 次无进展，降低频率

        mutating func record(hadToolUse: Bool) {
            if hadToolUse {
                noProgressCount = 0; isHalfOpen = false; isOpen = false
            } else {
                noProgressCount += 1
                if noProgressCount >= 5 { isOpen = true }
                else if noProgressCount >= 3 { isHalfOpen = true }
            }
        }

        mutating func reset() { noProgressCount = 0; isOpen = false; isHalfOpen = false }
    }

    private var breakers: [UUID: CircuitBreaker] = [:]
    private var hadToolUse: [UUID: Bool] = [:]      // 两次 idle 之间是否有 toolUse
    private let sessionManager: AgentSessionManager

    init(sessionManager: AgentSessionManager) {
        self.sessionManager = sessionManager
    }

    func recordToolUse(surfaceId: UUID) {
        hadToolUse[surfaceId] = true
    }

    func handleIdle(surfaceId: UUID) {
        guard let session = sessionManager.session(for: surfaceId),
              let threshold = session.respawnMode.config.idleThresholdSeconds else { return }

        var breaker = breakers[surfaceId] ?? CircuitBreaker()
        breaker.record(hadToolUse: hadToolUse[surfaceId] ?? false)
        hadToolUse[surfaceId] = false
        breakers[surfaceId] = breaker

        if breaker.isOpen {
            Self.logger.warning("Circuit breaker OPEN for surface \(surfaceId)")
            postUserNotification(surfaceId: surfaceId)
            return
        }

        let delay = breaker.isHalfOpen ? 30.0 : threshold
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run { self.sendContinue(surfaceId: surfaceId) }
        }
    }

    func resetBreaker(surfaceId: UUID) {
        breakers[surfaceId]?.reset()
    }

    // MARK: - PTY 写入（通过 Notification 发给 TerminalController）

    private func sendContinue(surfaceId: UUID) {
        postWrite(surfaceId: surfaceId, text: "\n")
        Self.logger.info("RespawnController: sent continue to \(surfaceId)")
    }

    func sendCompact(surfaceId: UUID) { postWrite(surfaceId: surfaceId, text: "/compact\n") }
    func sendClear(surfaceId: UUID)   { postWrite(surfaceId: surfaceId, text: "/clear\n/init\n") }

    private func postWrite(surfaceId: UUID, text: String) {
        NotificationCenter.default.post(
            name: .agentWriteToSurface,
            object: nil,
            userInfo: ["surfaceId": surfaceId, "text": text]
        )
    }

    private func postUserNotification(surfaceId: UUID) {
        // TODO: UNUserNotificationCenter 发系统通知
    }
}

extension Notification.Name {
    static let agentWriteToSurface = Notification.Name("AgentWriteToSurface")
}
```

- [ ] **Step 2：在 AgentService 初始化 RespawnController，在 AgentSessionManager 调用它**

在 `AgentService.swift` 添加：

```swift
var respawnController: RespawnController?
// 在 start() 中
respawnController = RespawnController(sessionManager: sessionManager)
```

在 `AgentSessionManager.processHookEvent` 的 toolUse 和 idle case 中添加：

```swift
case .preToolUse, .postToolUse:
    updateFromClaudeSession(payload.sessionId) { $0.state = .working }
    if let sid = claudeSessionIndex[payload.sessionId] {
        AgentService.shared.respawnController?.recordToolUse(surfaceId: sid)
    }
case .notification:
    if payload.notificationType == "idle_prompt" {
        updateFromClaudeSession(payload.sessionId) { $0.state = .idle }
        if let sid = claudeSessionIndex[payload.sessionId] {
            AgentService.shared.respawnController?.handleIdle(surfaceId: sid)
        }
    }
```

- [ ] **Step 3：在 TerminalController 中监听 agentWriteToSurface 通知**

在 TerminalController 的初始化/awakeFromNib 中注册：

```swift
NotificationCenter.default.addObserver(
    forName: .agentWriteToSurface,
    object: nil,
    queue: .main
) { [weak self] note in
    guard let surfaceId = note.userInfo?["surfaceId"] as? UUID,
          let text = note.userInfo?["text"] as? String else { return }
    self?.writeToSurface(text: text, surfaceId: surfaceId)
}
```

- [ ] **Step 4：编译检查**

```bash
cd .worktrees/workspace-ai-agent && make check
```

- [ ] **Step 5：Commit**

```bash
cd .worktrees/workspace-ai-agent
git add macos/Sources/Features/Agent/Respawn/RespawnController.swift \
        macos/Sources/Features/Agent/AgentService.swift \
        macos/Sources/Features/Agent/AgentSessionManager.swift \
        macos/Sources/Features/Terminal/TerminalController.swift \
        macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "feat(agent): add RespawnController with idle detection and circuit breaker"
```

---

## Phase 6：TokenTracker

### Task 6.1：TokenUsage + ModelPricing + TokenTracker

**Files:**
- Create: `macos/Sources/Features/Agent/TokenTracker/TokenUsage.swift`
- Create: `macos/Sources/Features/Agent/TokenTracker/ModelPricing.swift`
- Create: `macos/Sources/Features/Agent/TokenTracker/TokenTracker.swift`
- Modify: `macos/Sources/Features/Agent/AgentSession.swift`（用完整 TokenUsage 替换占位版）

- [ ] **Step 1：创建 TokenUsage.swift**

```swift
// macos/Sources/Features/Agent/TokenTracker/TokenUsage.swift
import Foundation

struct TokenSnapshot: Codable {
    let timestamp: Date
    let inputTokens: Int
    let outputTokens: Int
    let cost: Decimal
}

struct TokenUsage: Codable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cost: Decimal = 0
    var compactCount: Int = 0
    var contextUtilization: Float = 0
    var history: [TokenSnapshot] = []

    var totalTokens: Int { inputTokens + outputTokens }

    mutating func add(input: Int, output: Int, model: String) {
        inputTokens += input
        outputTokens += output
        cost += ModelPricing.calculate(inputTokens: input, outputTokens: output, model: model)
        history.append(TokenSnapshot(
            timestamp: Date(), inputTokens: inputTokens,
            outputTokens: outputTokens, cost: cost
        ))
    }
}
```

- [ ] **Step 2：创建 ModelPricing.swift**

```swift
// macos/Sources/Features/Agent/TokenTracker/ModelPricing.swift
import Foundation

struct ModelPricing {
    struct Price {
        let inputPerMillion: Decimal
        let outputPerMillion: Decimal
    }

    static let table: [String: Price] = [
        "claude-opus-4":     Price(inputPerMillion: 15.00, outputPerMillion: 75.00),
        "claude-sonnet-4":   Price(inputPerMillion: 3.00,  outputPerMillion: 15.00),
        "claude-sonnet-3-5": Price(inputPerMillion: 3.00,  outputPerMillion: 15.00),
        "claude-haiku-3-5":  Price(inputPerMillion: 0.80,  outputPerMillion: 4.00),
        "claude-haiku-3":    Price(inputPerMillion: 0.25,  outputPerMillion: 1.25),
        "gemini-2.0-flash":  Price(inputPerMillion: 0.10,  outputPerMillion: 0.40),
        "gemini-1.5-pro":    Price(inputPerMillion: 1.25,  outputPerMillion: 5.00),
    ]

    static func calculate(inputTokens: Int, outputTokens: Int, model: String) -> Decimal {
        let lower = model.lowercased()
        let price = table.first { lower.contains($0.key) }?.value
                 ?? Price(inputPerMillion: 3.00, outputPerMillion: 15.00)
        let inCost  = Decimal(inputTokens)  / 1_000_000 * price.inputPerMillion
        let outCost = Decimal(outputTokens) / 1_000_000 * price.outputPerMillion
        return inCost + outCost
    }
}
```

- [ ] **Step 3：创建 TokenTracker.swift**

```swift
// macos/Sources/Features/Agent/TokenTracker/TokenTracker.swift
import Foundation
import OSLog

@MainActor
final class TokenTracker {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "TokenTracker"
    )

    private let sessionManager: AgentSessionManager
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .prettyPrinted
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(sessionManager: AgentSessionManager) {
        self.sessionManager = sessionManager
    }

    /// 收到 Stop hook 时调用，解析 transcript 更新 token 用量
    func processStopEvent(surfaceId: UUID, transcriptPath: String, model: String) {
        Task.detached(priority: .utility) { [weak self] in
            let usage = await self?.parseTranscript(at: transcriptPath, model: model) ?? TokenUsage()
            await MainActor.run {
                self?.sessionManager.sessions[surfaceId]?.tokenUsage = usage
                // 持久化
                if let wsId = self?.sessionManager.sessions[surfaceId]?.workspaceId {
                    self?.persist(usage: usage, workspaceId: wsId)
                }
            }
        }
    }

    private func parseTranscript(at path: String, model: String) async -> TokenUsage {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return TokenUsage() }
        var usage = TokenUsage()
        var totalInput = 0, totalOutput = 0
        for line in content.components(separatedBy: .newlines) {
            guard let data = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let u = event["usage"] as? [String: Any] else { continue }
            totalInput  = (u["input_tokens"]  as? Int) ?? totalInput
            totalOutput = (u["output_tokens"] as? Int) ?? totalOutput
        }
        if totalInput > 0 || totalOutput > 0 {
            usage.add(input: totalInput, output: totalOutput, model: model)
        }
        return usage
    }

    func persist(usage: TokenUsage, workspaceId: UUID) {
        let dir = WorkspaceManager.shared.workspaceDir(for: workspaceId)
        let path = (dir as NSString).appendingPathComponent("llm_token_metering.json")
        guard let data = try? encoder.encode(usage) else { return }
        let tmp = path + ".tmp"
        try? data.write(to: URL(fileURLWithPath: tmp))
        try? FileManager.default.moveItem(atPath: tmp, toPath: path)
    }

    func load(for workspaceId: UUID) -> TokenUsage? {
        let dir = WorkspaceManager.shared.workspaceDir(for: workspaceId)
        let path = (dir as NSString).appendingPathComponent("llm_token_metering.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? decoder.decode(TokenUsage.self, from: data)
    }
}
```

- [ ] **Step 4：删除 AgentSession.swift 中的占位 TokenUsage 定义**

找到 `AgentSession.swift` 中的 `struct TokenUsage: Codable { ... }` 占位块，删除它（现在由 `TokenUsage.swift` 提供）。

- [ ] **Step 5：在 AgentService 初始化 TokenTracker，在 AgentSessionManager 的 stop case 中调用**

```swift
// AgentService.swift
var tokenTracker: TokenTracker?
// 在 start() 中
tokenTracker = TokenTracker(sessionManager: sessionManager)
```

```swift
// AgentSessionManager.processHookEvent 的 .stop case
case .stop:
    updateFromClaudeSession(payload.sessionId) { $0.state = .idle }
    if let sid = claudeSessionIndex[payload.sessionId],
       let path = payload.transcriptPath {
        AgentService.shared.tokenTracker?.processStopEvent(
            surfaceId: sid,
            transcriptPath: path,
            model: "claude-sonnet-4"  // TODO: 从 AgentDefinition 读取
        )
    }
```

- [ ] **Step 6：编译检查**

```bash
cd .worktrees/workspace-ai-agent && make check
```

- [ ] **Step 7：手动验证**

```bash
make run-dev
# 启动 Claude Code agent
# 完成一个任务后检查：
# ls ~/.config/poltertty/workspaces/{UUID}/
# 应看到 llm_token_metering.json
# Monitor Panel 应显示 token 用量和费用
```

- [ ] **Step 8：Commit**

```bash
cd .worktrees/workspace-ai-agent
git add macos/Sources/Features/Agent/TokenTracker/ \
        macos/Sources/Features/Agent/AgentSession.swift \
        macos/Sources/Features/Agent/AgentService.swift \
        macos/Sources/Features/Agent/AgentSessionManager.swift \
        macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "feat(agent): add TokenTracker with transcript parsing and billing"
```

---

## 验证清单

**Phase 1 完成后：**
- [ ] `make check` 通过
- [ ] `make run-dev` 启动，现有 workspace 正常加载
- [ ] `~/.config/poltertty/workspaces/` 出现 `{UUID}/workspace.json` 目录结构
- [ ] 旧的 `{UUID}.json` 文件自动迁移

**Phase 2 完成后：**
- [ ] `~/.config/poltertty/hook-server.json` 写入正确端口和 PID
- [ ] workspace 目录下 `.claude/settings.local.json` 包含 poltertty hook 条目
- [ ] app 日志中能看到 hook 事件（`log stream --predicate 'subsystem == "com.mitchellh.ghostty"'`）

**Phase 3 完成后：**
- [ ] `Cmd+Shift+A` 弹出两步菜单
- [ ] 菜单显示三个内置 agent
- [ ] 选择后 agent 命令写入 PTY，session 在 AgentSessionManager 中注册

**Phase 4 完成后：**
- [ ] 有 agent 的 tab 显示状态圆点，working 时有脉冲动画
- [ ] `Cmd+Shift+M` 显示/隐藏 Monitor Panel
- [ ] Monitor Panel 实时反映 session 状态变化

**Phase 5 完成后：**
- [ ] solo-work 模式 idle 3s 后自动写入 `\n`
- [ ] 连续 5 次无 toolUse 的 idle 后 circuit breaker 触发，停止 respawn

**Phase 6 完成后：**
- [ ] Stop hook 后 Monitor Panel 显示 token 用量和费用
- [ ] `llm_token_metering.json` 正确写入
- [ ] 费用按模型价格表计算

---

## 重要注意事项

### Task 3.1 必须先执行
Task 3.2 中 `AgentLauncher` 调用 `tc.newTab(nil)` / `tc.splitRight(nil)` / `tc.splitDown(nil)` 是假设名称，**必须先读取 TerminalController.swift 的实际 API**，否则会编译失败。

### workspaceDir API 可见性
`WorkspaceManager.workspaceDir(for:)` 在 Task 1.5 中新增，声明为 `func`（非 `private`），供 `TokenTracker` 使用。

### TokenUsage 类型冲突
Task 6.1 Step 4 中删除 `AgentSession.swift` 的占位 `TokenUsage` 时，确保先完成 `TokenUsage.swift` 并加入 Xcode 项目，避免编译时类型找不到。

### 明确推迟的功能（本计划不包含）

| 功能 | 原因 |
|------|------|
| **Gemini CLI hook bridge**（`poltertty-hook-bridge` 脚本 + `.gemini/settings.json` 注入）| Spec 标注"Gemini CLI 是否支持项目级覆盖待验证"，先实现核心功能，验证后补充 |
| **FileWatcher fallback**（`~/.claude/projects/{hash}/` 目录监听）| Spec 标注 Claude Code 内部目录结构可能随版本变化，MVP 先用 Hook + ProcessMonitor 两层即可 |
| **Token 上下文自动 compact/clear**（达到阈值自动写命令）| RespawnMode 已有 threshold 配置，等 TokenTracker 稳定后补充触发逻辑 |
| **Subagent transcript 文件内容读取**（`~/.claude/projects/*/subagents/` 监听）| 同 FileWatcher，MVP 先显示 "transcript unavailable" |
