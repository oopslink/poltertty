# Workspace AI Agent 管理系统设计

> Poltertty 原生支持 AI 编程 agent 的启动、管理、状态监控和自动化能力。

## 背景

Codeman 等工具通过 tmux + Web UI 管理 AI agent 会话。Poltertty 作为终端模拟器，天然拥有 PTY、Surface、Split、Tab，可以跳过 tmux 和 Web 中间层，直接在终端内原生支持这些能力。

## 功能范围

1. Agent 启动/管理（快捷键 + 下拉菜单）
2. PTY 输出监听 + 状态可视化
3. 自动 respawn + token 管理 + 计费
4. Subagent 可视化

## 架构：AgentService 中心化

新增 `AgentService` 单例（`@MainActor`），作为所有 agent 管理的中枢。随 app 启动初始化，作为 `WorkspaceManager.shared` 的属性持有。未来功能增多后可抽出为 plugin 架构。

**生命周期：**
- `AppDelegate.applicationDidFinishLaunching()` 时初始化 `AgentService`，启动 HookServer
- `TerminalController.close()` / `WorkspaceManager.delete()` 时，通过 `AgentService.cleanupForWorkspace(id:)` 清理相关 agent session
- `AppDelegate.applicationWillTerminate()` 时关闭 HookServer，清理所有注入的 hook 配置

**线程安全：**
- `AgentService` 及其子模块标记为 `@MainActor`，UI 绑定通过 `@Published` 自然在主线程
- `HookServer` 在后台线程接收 HTTP 请求，通过 `MainActor.run {}` 将事件分发到主线程更新状态
- `FileWatcher` 使用 `DispatchSource`，回调同样 dispatch 到主线程

### 子模块

| 模块 | 职责 |
|------|------|
| **AgentRegistry** | Agent 类型定义 & 预设（Claude Code / Gemini CLI / OpenCode / 自定义） |
| **AgentSessionManager** | 活跃 session 跟踪，surfaceId ↔ AgentSession 映射，@Published 驱动 UI |
| **HookServer** | 内嵌 HTTP server (localhost)，接收 Claude Code / Gemini hook 事件 |
| **FileWatcher** | Fallback：监听 ~/.claude/ 等目录，用于无 hook 的 agent |
| **RespawnController** | 自动续命逻辑，预设模式 + circuit breaker |
| **SubagentTracker** | Subagent 生命周期 & parent ↔ child 关系树 |
| **TokenTracker** | Token 用量追踪 & 计费 |

### 数据流

```
快捷键 → AgentLauncher → AgentSessionManager → 创建 Surface + 写入启动命令到 PTY
Agent CLI → HTTP Hook → HookServer → AgentSessionManager 更新状态 → UI 自动刷新
Idle 事件 → RespawnController → 写入 continue 到 PTY stdin
SubagentStart → SubagentTracker → AgentMonitorPanel 显示 / 弹出 split
Stop hook → TokenTracker → 解析 transcript 更新 token 数 & 费用
```

### 与已有组件集成

| 组件 | 集成方式 |
|------|---------|
| **WorkspaceManager** | 持有 AgentService 引用，workspace 关闭时清理 agent |
| **TerminalController** | 转发快捷键事件，管理 agent split/tab 创建 |
| **TabBarViewModel** | 显示 agent 状态徽标，surface 创建时注册 agent |

## 功能一：Agent 启动/管理

### Agent Registry

内置预设 agent 类型，每个定义包含：

```
AgentDefinition
├── id: String               — 唯一标识
├── name: String             — 显示名称
├── command: String          — 启动命令模板（如 "claude"）
├── icon: String             — 图标/颜色
├── hookCapability: enum     — .full (HTTP) / .commandOnly / .none
└── hookConfig: HookConfig?  — 自动注入的 hook 配置
```

用户可通过 `~/.config/poltertty/agents.json` 添加自定义 agent：

```json
{
  "agents": [
    {
      "id": "aider",
      "name": "Aider",
      "command": "aider --model sonnet",
      "icon": "🔧",
      "hookCapability": "none"
    }
  ]
}
```

自定义 agent 与内置预设合并显示在启动菜单中。`hookCapability` 决定可用的状态感知层级。

### 启动流程

两步下拉菜单，快捷键触发（如 `Cmd+Shift+A`）：

**Step 1：选择 Agent**
- 弹出类 Claude Code 风格的下拉菜单
- 支持模糊搜索过滤
- 显示 agent 名称、命令、hook 能力等级
- 如果只有一个 agent，自动跳过此步

**Step 2：选择打开位置**
- Current pane — 在当前 shell 中直接执行 agent 命令（shell 仍在，agent 退出后回到 shell）
- New tab — 新 tab 打开
- Split right — 右侧 split
- Split bottom — 底部 split
- 底部显示 respawn 模式，Tab 键切换，默认 `manual`

**启动后动作：**
1. 在目标位置创建新 Surface（或使用当前 pane 的 Surface）
2. 向 PTY stdin 写入启动命令（如 `claude`）
3. AgentSessionManager 注册 session（surfaceId ↔ { agentType, cwd, pid, state: .launching }）
4. 如果 agent 支持 hook，检查并注入项目级 hook 配置（`.claude/settings.local.json`）

**Agent 状态机：**
```
launching → working → idle → working（循环）
                  ↘ error
launching/working/idle → done（进程退出）
```
`launching` 是初始状态，收到第一个 hook 事件后转为 `working`。

### 多 Agent 支持

一个 tab 内可通过 split pane 运行多个不同 agent。Agent 状态绑定在 surfaceId 上而非 tab 上。Tab bar 上的聚合显示：
- 状态取优先级最高的：launching > error > working > idle > done
- 费用显示 tab 内所有 agent 总和

## 功能二：状态感知（三层策略）

不侵入 PTY 输出流，通过外部机制感知 agent 状态。

### 第一层：Hook（首选）

**HookServer 管理策略：**

HookServer 启动时绑定 localhost 固定端口（可配置，默认 `19198`），将端口号和 PID 写入 `~/.config/poltertty/hook-server.json`。多个 Poltertty 窗口共享同一个 HookServer 实例（第一个启动的 window 创建，后续窗口复用）。

**多实例协调：**
1. 启动时检查 `hook-server.json` 是否存在
2. 如果存在，检查记录的 PID 是否仍存活（`kill(pid, 0)`）
3. PID 存活 → 复用（通过 HTTP health check `GET /health` 确认可用）
4. PID 不存活（崩溃残留）→ 删除旧文件，创建新 HookServer
5. 端口冲突 → 尝试下一个端口（19198 → 19199 → ...，最多尝试 10 次）

**Hook 配置注入（非侵入式）：**

不修改用户全局的 `~/.claude/settings.json`。而是利用项目级 hook 配置（`.claude/settings.local.json`），在 agent 的 `cwd`（即 workspace 的 rootDir）下写入：

```
{workspaceRootDir}/.claude/settings.local.json
```

```json
{
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "http", "url": "http://localhost:19198/hook", "_poltertty": true }] }],
    "SessionEnd": [{ "hooks": [{ "type": "http", "url": "http://localhost:19198/hook", "_poltertty": true }] }],
    "Notification": [{ "hooks": [{ "type": "http", "url": "http://localhost:19198/hook", "_poltertty": true }] }],
    "PreToolUse": [{ "hooks": [{ "type": "http", "url": "http://localhost:19198/hook", "_poltertty": true }] }],
    "PostToolUse": [{ "hooks": [{ "type": "http", "url": "http://localhost:19198/hook", "_poltertty": true }] }],
    "Stop": [{ "hooks": [{ "type": "http", "url": "http://localhost:19198/hook", "_poltertty": true }] }],
    "SubagentStart": [{ "hooks": [{ "type": "http", "url": "http://localhost:19198/hook", "_poltertty": true }] }],
    "SubagentStop": [{ "hooks": [{ "type": "http", "url": "http://localhost:19198/hook", "_poltertty": true }] }],
    "PreCompact": [{ "hooks": [{ "type": "http", "url": "http://localhost:19198/hook", "_poltertty": true }] }],
    "PostCompact": [{ "hooks": [{ "type": "http", "url": "http://localhost:19198/hook", "_poltertty": true }] }]
  }
}
```

优点：不修改全局配置，不影响其他项目的 Claude Code 使用，项目级 `.local.json` 本身就应在 `.gitignore` 中。如果已存在该文件且包含用户自定义 hook，采用合并策略（append 到已有事件的 hooks 数组，通过 `_poltertty` 标记识别 Poltertty 注入的条目）。

**Hook 配置文件操作的原子性：** 读取 → 合并 → 写入临时文件 → rename 覆盖。使用文件锁（`flock` 或 `NSFileCoordinator`）防止多个 workspace 同时操作同一 `.claude/settings.local.json`（多个 workspace 可能共享同一 rootDir）。

**清理策略：** workspace 关闭时移除 `_poltertty: true` 的 hook 条目。Poltertty 异常退出时，下次启动扫描所有已知 workspace rootDir，清理残留配置。

**Hook 事件到 Surface 的关联：**

Claude Code hook payload 包含 `session_id` 和 `cwd`。关联流程：
1. Agent 启动时，AgentSessionManager 记录 `surfaceId → { agentType, cwd, shellPid }`（shellPid 是 Surface 的 PTY 进程 PID，已由 Ghostty 管理）
2. 首次收到 `SessionStart` hook 时，通过 `cwd` 匹配候选 surface，再通过进程树验证（hook payload 的发送进程应是 shellPid 的子进程，使用 `sysctl` / `proc_listchildpids` 查询）
3. 匹配成功后绑定 `claudeSessionId`，后续 hook 事件通过 `session_id` 直接查找
4. 多个 agent 在同一 cwd 时，进程树关系确保唯一匹配

**"Current pane" 场景的 pid 获取：** 当在已有 shell 中执行 agent 命令时，不需要知道 agent 的 pid。shellPid 已知（Surface 创建时记录），agent 是 shell 的子进程，进程树查询即可建立关联。

**Gemini CLI（command hook）：**
Gemini 不支持 HTTP hook，仅支持 command 类型。提供一个桥接脚本 `poltertty-hook-bridge`，安装到 `~/.config/poltertty/bin/`，command hook 调用此脚本，脚本读取 `~/.config/poltertty/hook-server.json` 获取端口，转发到 HookServer HTTP 端点。项目级配置写入 `{workspaceRootDir}/.gemini/settings.json`（注：Gemini CLI 是否支持 `.local.json` 项目级覆盖待验证，实现时需确认，如不支持则写入标准的 `.gemini/settings.json` 并做好合并/清理）。

### 第二层：文件系统监听（Fallback）

对于无 hook 的 agent（如 OpenCode），FileWatcher 使用 `DispatchSource.makeFileSystemObjectSource` 监听：
- `~/.claude/projects/{projectHash}/` — Claude Code 项目状态
- `~/.claude/projects/{projectHash}/subagents/` — subagent 目录变化

注意：这些是 Claude Code 的内部目录结构，可能随版本变化。实现时做好防御性处理，目录不存在或格式变化时静默降级。

### 第三层：进程监控（兜底）

通过 `DispatchSource.makeProcessSource(identifier:, eventMask: .exit)` 监听 agent 进程退出事件。Agent 启动时记录 pid，进程退出时更新状态为 done/error。这是所有 agent 都适用的兜底方案，不依赖任何 hook 或文件系统约定。

### 关键 Hook 事件映射

| 需求 | Hook 事件 | 数据 |
|------|----------|------|
| Agent 启动/结束 | `SessionStart` / `SessionEnd` | session_id, cwd |
| Agent idle | `Notification` (matcher: `idle_prompt`) | notification_type |
| Agent 在工作 | `PreToolUse` / `PostToolUse` | tool_name, tool_input |
| 需要审批 | `Notification` (matcher: `permission_prompt`) | — |
| Subagent 生命周期 | `SubagentStart` / `SubagentStop` | agent_name, agent_type |
| 上下文压缩 | `PreCompact` / `PostCompact` | — |
| Token 计数 | `Stop` | transcript_path |

## 功能三：状态可视化

### Tab Bar 徽标

每个 agent tab 显示：
- **状态圆点：** 🟢 working（脉冲动画）/ 🟡 idle / 🔴 error / ⚫ done
- **费用标签：** 当前 session 累计费用（如 $2.41）
- **Subagent 角标：** 右上角数字，显示活跃 subagent 数量

多 agent tab 聚合显示最高优先级状态（launching > error > working > idle > done）和总费用。

### Agent Monitor Panel

右侧面板，类似现有 File Browser 的定位。`Cmd+Shift+M` 切换显示/隐藏。

**内容：**
- Lead Session 状态 + token 进度条（使用率变色：绿 → 黄 → 红）+ 费用
- Subagent 折叠列表
- 底部 respawn 模式 + 运行时长 + 总费用

## 功能四：Subagent 可视化

### 三层渐进式展示

**1. 折叠列表（Monitor Panel 内）：**
每个 subagent 一行：状态圆点、名称、模型、耗时。

**2. 展开详情（点击展开）：**
- 任务描述
- 实时 transcript：工具调用记录 + 文本输出
- 底部统计：tokens / tools 调用次数 / 耗时 / 费用

**3. 弹出 Split Pane（点击 ⧉）：**
- 独立 split pane，只读 transcript 视图
- 带时间戳、自动滚动
- 顶栏显示 subagent 信息 + token 费用
- `⇲` 收回 Monitor Panel，`✕` 关闭

### 数据来源

- `SubagentStart` / `SubagentStop` hook → 生命周期事件（首选，agent 有 hook 支持时使用）
- FileWatcher 监听 `~/.claude/projects/*/subagents/{id}/` → 实时 transcript 内容（始终启用，作为 transcript 的唯一数据源；hook 只提供生命周期事件，transcript 内容必须从文件系统读取）

注意：subagent 目录结构是 Claude Code 的内部实现细节，可能随版本变化。实现时做好防御性处理，目录不存在或格式变化时静默降级（Monitor Panel 显示"transcript unavailable"）。

## 功能五：Respawn Controller

### 预设模式

| 模式 | idle 阈值 | 最大运行时间 | 自动 compact | 场景 |
|------|-----------|-------------|-------------|------|
| `solo-work` | 3s | 60min | 55% context window | 日常开发，短任务 |
| `team-lead` | 90s | 480min | 55% context window | 多 subagent 编排 |
| `overnight` | 10s | 无限制 | 55% compact + 70% auto-clear | 无人值守长任务 |
| `manual` | 不自动 | — | — | 完全手动 |

Token 阈值使用上下文窗口的百分比而非绝对数值，以适配不同模型（128k / 200k / 1M）。模型的上下文窗口大小从 AgentRegistry 内置的模型定义中获取，用户可覆盖。

**Respawn 模式管理：**
- 默认模式：`manual`（不自动 respawn）
- 启动时在菜单 Step 2 底部选择，Tab 键切换
- 启动后可通过 Monitor Panel 随时更改
- 模式存储在 AgentSession 上（per-session），不持久化

### 工作流程

1. `Notification` hook 推送 `idle_prompt` 事件
2. RespawnController 检查当前模式 idle 阈值
3. 达到阈值 → 向 PTY stdin 写入 continue
4. Circuit breaker 防无限循环

### Circuit Breaker

**"进展"定义：** 两次 idle 事件之间，至少有一次 `PostToolUse` 事件（即 agent 成功执行了至少一个工具调用）。如果 agent 反复 idle 但没有调用任何工具，视为无进展。

- 跟踪连续无进展的 respawn 次数
- 3 次无进展 → 半开状态（降低频率，间隔从即时变为 30s）
- 5 次 → 断开（停止 respawn，tab 徽标变红，弹 macOS 通知）
- 用户可手动重置 circuit breaker（Monitor Panel 中的操作按钮）

### Token 管理自动动作

- 接近上下文窗口限制 → 自动发送 `/compact`
- compact 后仍超阈值（overnight 模式）→ `/clear` + `/init`

## 功能六：Token 追踪 & 计费

### 数据获取

三个来源：
- `Stop` hook → 解析 `transcript_path` 拿精确 input/output token 数
- `PreCompact` / `PostCompact` hook → 感知压缩事件
- `SessionEnd` hook → 最终 token 汇总

### 数据模型

```
TokenUsage
├── inputTokens: Int          — 输入 token 累计
├── outputTokens: Int         — 输出 token 累计
├── totalTokens: Int          — 总计
├── cost: Decimal             — 按模型定价计算的费用（美元）
├── compactCount: Int         — 已 compact 次数
├── contextUtilization: Float — 当前上下文使用率 (0.0-1.0)
└── history: [TokenSnapshot]  — 时间序列，用于趋势图
```

### 计费逻辑

- 内置各模型价格表（Opus / Sonnet / Haiku / Gemini Pro 等）
- 用户可在配置中覆盖价格（自部署模型场景）
- 按 session 计费，也按 workspace 汇总
- 支持日/周/月维度统计

### UI 展示

- Tab bar agent 徽标旁显示费用
- Monitor Panel 详细 token 进度条 + 费用
- 上下文使用率变色预警（绿 → 黄 → 红）

### 持久化

存储路径：`~/.config/poltertty/workspaces/{UUID}/llm_token_metering.json`

同时将现有 workspace 存储从 `{UUID}.json` 迁移到目录结构：

```
~/.config/poltertty/workspaces/{UUID}/
├── workspace.json              — workspace 配置（从 {UUID}.json 迁移）
├── llm_token_metering.json     — token 用量 & 计费数据
└── ...                         — 后续其他 workspace 级数据
```

**存储迁移策略：**

1. `WorkspaceManager.loadAll()` 启动时同时检查旧格式（`{UUID}.json`）和新格式（`{UUID}/workspace.json`）
2. 如果发现旧格式文件，自动迁移：创建 `{UUID}/` 目录 → 移动文件为 `workspace.json` → 删除旧文件
3. 迁移是原子的：先写入新位置，确认成功后再删除旧位置
4. 如果新旧都存在（异常情况），以新格式为准
5. 无版本号机制——仅此一次迁移，后续新 workspace 直接使用目录格式

## 设计决策记录

| 决策 | 选择 | 理由 |
|------|------|------|
| 架构 | AgentService 中心化单例 | Agent 管理是独立领域，需要自己的状态，硬塞已有组件会混乱 |
| 状态感知 | Hook 优先，不侵入 PTY | 干净、解耦、agent 原生支持 |
| 启动入口 | 快捷键 + 下拉菜单 | 符合终端操作习惯 |
| Subagent 展示 | Monitor 面板 + 可弹出 split | 渐进式：不打扰 → 按需展开 → 独立视图 |
| Respawn | 预设模式 | 降低配置门槛，覆盖常见场景 |
| 存储结构 | 每个 workspace 一个目录 | 比单文件更好扩展 |
| 远程/手机访问 | 不做 | 不适合原生 macOS app 形态 |

## 不包含（明确排除）

- 远程/手机访问（Codeman Web UI 形态）
- PTY 输出流解析（侵入性太强）
- Agent 间通信/编排（cc-connect 的定位）
- Ralph/Todo 追踪（过于特定，非通用需求）
- Plugin 系统（未来再抽象，当前 YAGNI）
