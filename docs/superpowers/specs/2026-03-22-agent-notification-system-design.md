# Agent 通知系统设计文档

**日期：** 2026-03-22
**状态：** 草稿 v3（review 修订）

---

## 背景

用户在终端中运行 AI Agent（如 Claude Code）时，agent 完成任务、需要授权、遇到错误等关键时刻，用户可能已切换到其他窗口。本方案通过 PATH 劫持 + hooks 注入 + HTTP 通信，将 agent 状态变化及时推送给用户。

**设计目标：**
- **零侵入**：不修改用户的 agent 配置文件，退出终端后无残留
- **优雅降级**：终端 app 未运行或 HTTP server 不可达时，agent 正常工作不受影响
- **低延迟**：不影响 agent 的键盘输入和执行性能

---

## 整体架构

```
用户输入 "claude"
      │
      ▼
~/.poltertty/bin/claude  (PATH 劫持，优先命中)
      │
      ├─ 不在 poltertty 内? → exec 真实 claude（透传）
      ├─ HTTP server 不可达? → exec 真实 claude（透传）
      ├─ 检测到嵌套? → exec 真实 claude（透传）
      │
      ├─ poltertty-cli prepare-session（HTTP 调用 App）
      │   ├─ App 创建 ~/.poltertty/sessions/<pts-id>/
      │   ├─ App 合并 4 层 claude settings + 用户 --settings → session/settings.json
      │   ├─ App 生成 token → session/meta.json
      │   └─ App 返回 session dir 路径 + token
      │
      └─ exec claude --settings <session>/settings.json
              │
              ├─ SessionStart hook  → poltertty-cli hook session-start
              ├─ PreToolUse hook   → poltertty-cli hook pre-tool-use (async)
              ├─ PostToolUse hook  → poltertty-cli hook post-tool-use (async)
              ├─ Notification hook → poltertty-cli hook notification
              ├─ PromptSubmit hook → poltertty-cli hook prompt-submit
              ├─ Stop hook        → poltertty-cli hook stop
              ├─ SubagentStart    → poltertty-cli hook subagent-start (async)
              ├─ SubagentStop     → poltertty-cli hook subagent-stop (async)
              ├─ PreCompact hook  → poltertty-cli hook pre-compact (async)
              ├─ PostCompact hook → poltertty-cli hook post-compact (async)
              └─ SessionEnd hook  → poltertty-cli hook session-end
                      │
                      ▼ (每个 hook 都是)
              POST http://localhost:$POLTERTTY_HTTP_PORT/hooks/<event>
              Authorization: Bearer <token>
                      │
                      ▼
              HookServer（复用现有）
                      │
              ┌────────────────────────────┐
              ▼        ▼                   ▼
         macOS 通知  Sidebar 角标      Dock Badge
                  Status Bar 状态
```

---

## 模块一：CLI Wrapper（PATH 劫持）

### 部署位置

```
~/.poltertty/
  ├── bin/
  │   ├── poltertty-agent-wrapper   # wrapper 实际逻辑
  │   ├── poltertty-cli             # CLI 工具（hook 子命令、prepare-session 等）
  │   ├── claude                    # symlink → poltertty-agent-wrapper
  │   └── codex                     # symlink → poltertty-agent-wrapper
  └── shell/
      ├── poltertty.bash            # bash shell integration
      ├── poltertty.zsh             # zsh shell integration
      └── poltertty.fish            # fish shell integration
```

- **App 启动时**：从 bundle 复制 `poltertty-agent-wrapper`、`poltertty-cli`、shell integration 脚本到 `~/.poltertty/`；根据 Supported Agents 列表生成/更新 symlinks
- **App 退出时**：不清理（wrapper 在非 poltertty 环境下是纯透传，不影响正常使用）
- **App 更新时**：覆盖 `poltertty-agent-wrapper`、`poltertty-cli` 和 shell 脚本，symlinks 自动跟随

### PATH 注入机制（双保险）

**第一层：PTY spawn 时设置**

```swift
func configureShellEnvironment(for surface: Surface) {
    var env = ProcessInfo.processInfo.environment
    let home = NSHomeDirectory()
    let binDir = "\(home)/.poltertty/bin"

    env["PATH"] = binDir + ":" + (env["PATH"] ?? "")
    env["POLTERTTY_BIN_DIR"] = binDir
    env["POLTERTTY_WORKSPACE_ID"] = surface.tab.workspace.id.uuidString
    env["POLTERTTY_SURFACE_ID"] = surface.id.uuidString
    env["POLTERTTY_HTTP_PORT"] = String(hookServer.port)

    // shell integration 脚本路径，供 ghostty shell integration 加载
    let shell = surface.terminal.shellType  // bash / zsh / fish
    env["POLTERTTY_SHELL_INTEGRATION"] = "\(home)/.poltertty/shell/poltertty.\(shell)"

    surface.terminal.spawn(environment: env)
}
```

**第二层：Shell Integration 脚本补强**

Ghostty 的 shell integration 脚本末尾加一行（fork diff，每种 shell 各一行，最小上游冲突面）：

```bash
# ghostty shell integration 尾部追加（zsh 版）
[[ -f "$POLTERTTY_SHELL_INTEGRATION" ]] && source "$POLTERTTY_SHELL_INTEGRATION"
```

`~/.poltertty/shell/poltertty.zsh` 内容：

```zsh
# Poltertty shell integration — PATH 补强
# 防止用户 source ~/.zshrc 后 PATH 被重置导致 wrapper 失效
if [[ -n "$POLTERTTY_BIN_DIR" ]] && [[ ":$PATH:" != *":$POLTERTTY_BIN_DIR:"* ]]; then
    export PATH="$POLTERTTY_BIN_DIR:$PATH"
fi
```

bash / fish 各有对应版本。去重检查避免 PATH 越来越长。

### 完整 Wrapper 脚本

```bash
#!/usr/bin/env bash
set -euo pipefail

AGENT_NAME="$(basename "$0")"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── 找到真实 binary（跳过自身目录）──
find_real_binary() {
    local IFS=':'
    for dir in $PATH; do
        [[ "$dir" == "$SELF_DIR" ]] && continue
        [[ -x "$dir/$AGENT_NAME" ]] && echo "$dir/$AGENT_NAME" && return 0
    done
    echo "poltertty-wrapper: $AGENT_NAME not found in PATH" >&2
    exit 127
}

REAL_BINARY="$(find_real_binary)"

# ── 子命令白名单：直接透传 ──
case "${1:-}" in
    mcp|config|doctor|update|--help|--version|-v)
        exec "$REAL_BINARY" "$@" ;;
esac

# ── 降级条件 ──
if [[ -z "${POLTERTTY_SURFACE_ID:-}" ]] \
    || [[ "${POLTERTTY_HOOKS_DISABLED:-}" == "1" ]] \
    || [[ -n "${POLTERTTY_SESSION_ID:-}" ]]; then
    exec "$REAL_BINARY" "$@"
fi

# ── HTTP server 存活检测（750ms 超时）──
if ! poltertty-cli ping \
        --port "${POLTERTTY_HTTP_PORT:-}" \
        --timeout 750 2>/dev/null; then
    exec "$REAL_BINARY" "$@"
fi

# ── 提取并移除用户的 --settings（纳入 merge）──
USER_SETTINGS_FLAG=""
FILTERED_ARGS=()
SKIP_NEXT=false
for arg in "$@"; do
    if $SKIP_NEXT; then
        USER_SETTINGS_FLAG="$arg"
        SKIP_NEXT=false
        continue
    fi
    if [[ "$arg" == "--settings" ]]; then
        SKIP_NEXT=true
        continue
    fi
    FILTERED_ARGS+=("$arg")
done
set -- "${FILTERED_ARGS[@]}"

# ── 解析 Claude Code session id ──
CC_SESSION_ARGS=()
CC_SID=""
if [[ " $* " == *" --resume "* ]]; then
    : # 用户用 --resume，让 CC 自己选 session
elif CC_SID=$(poltertty-cli extract-flag --session-id "$@") \
        && [[ -n "$CC_SID" ]]; then
    : # 用户自带 --session-id，尊重
else
    CC_SID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
    CC_SESSION_ARGS=("--session-id" "$CC_SID")
fi

# ── 通过 HTTP 调用 App 创建 session（合并步骤）──
# prepare-session 向 App 发送 HTTP 请求：
#   - App 生成 token
#   - App 读取 4 层 claude settings + 用户 --settings，合并 hooks
#   - App 创建 session 目录，写入 meta.json + settings.json
#   - App 返回 session dir 路径
PTS_ID="pts-$(uuidgen | tr '[:upper:]' '[:lower:]')"
PREPARE_ARGS=(
    --session-id       "$PTS_ID"
    --agent            "$AGENT_NAME"
    --agent-session-id "${CC_SID:-unknown}"
    --cwd              "$(pwd)"
    --workspace-id     "$POLTERTTY_WORKSPACE_ID"
    --surface-id       "$POLTERTTY_SURFACE_ID"
    --port             "$POLTERTTY_HTTP_PORT"
    --pid              $$
)
if [[ -n "$USER_SETTINGS_FLAG" ]]; then
    PREPARE_ARGS+=(--user-settings "$USER_SETTINGS_FLAG")
fi

SESSION_DIR=$(poltertty-cli prepare-session "${PREPARE_ARGS[@]}") || {
    # prepare 失败，降级透传
    exec "$REAL_BINARY" "$@"
}

# ── exec agent ──
export POLTERTTY_SESSION_ID="$PTS_ID"
export POLTERTTY_AGENT_PID=$$
unset CLAUDECODE 2>/dev/null || true   # 防止 CC 误判为嵌套 session（已验证变量名）

exec "$REAL_BINARY" \
    "${CC_SESSION_ARGS[@]}" \
    --settings "$SESSION_DIR/settings.json" \
    "$@"
```

### 多 Agent 支持

通过 `$0`（basename）判断 agent 类型，同一套 wrapper 逻辑支持 claude、codex 等。`meta.json` 的 `agentType` 字段存储类型，App 侧针对不同 agent 做差异化的 payload 解析。

---

## 模块二：Session Store（会话持久化）

### 目录结构

```
~/.poltertty/sessions/
  └── pts-abc-123/
      ├── meta.json        # session 元数据 & 两个 session 的映射
      ├── settings.json    # 合并后的 hooks 配置，传给 --settings
      └── ...              # 后续扩展（日志、上下文备份等）
```

### meta.json

```json
{
  "version": 1,
  "polterttySessionId": "pts-abc-123",
  "agentSessionId": "cc-def-456",
  "agentType": "claude-code",
  "workspaceId": "ws-1",
  "surfaceId": "sf-1",
  "pid": 12345,
  "cwd": "/Users/x/project",
  "token": "base64-random-32-bytes",
  "startedAt": 1711000000,
  "updatedAt": 1711000060,
  "endedAt": null
}
```

**两个 Session 的关系：**

| 字段 | 说明 |
|------|------|
| `polterttySessionId` | Poltertty 创建，代表本次监控周期 |
| `agentSessionId` | Claude Code 自身的 session id |
| 关系 | 1:1 包装，poltertty session 是外层，每次调用 wrapper 都创建新的 poltertty session |

用户 `--resume` 恢复旧 CC session 时，poltertty session 仍新建（新的监控周期），`agentSessionId` 指向被恢复的旧 CC session。

### 清理策略

| 场景 | 处理 |
|------|------|
| `session-end` hook 正常触发 | 标记 `endedAt` |
| Agent 崩溃 / `kill -9` | App 定时检测 `pid` 是否存活（`kill -0`），不存活则标记 `endedAt` |
| App 启动时 | 扫描所有 session 目录，清理 pid 已死亡的残留 |
| 过期清理 | `endedAt` 超过 7 天的目录删除 |

---

## 模块三：Settings 合并（prepare-session）

### 合并流程

`prepare-session` 通过 HTTP 调用 App 主进程完成。App 侧负责：

1. 读取四层 Claude Code 配置的 hooks：
   - `~/.claude/settings.json`
   - `~/.claude/settings.local.json`
   - `<cwd>/.claude/settings.json`
   - `<cwd>/.claude/settings.local.json`
2. 如果用户传了 `--settings`（通过 `--user-settings` 参数传入），也读取其中的 hooks
3. 合并所有 hooks + 注入 poltertty hooks
4. 生成 token（`SecRandomCopyBytes`，32 bytes）
5. 创建 session 目录，写入 `meta.json`（含 token）+ `settings.json`（仅 hooks 字段）
6. 返回 session 目录路径

### `--settings` 覆盖范围

Claude Code 的 `--settings` 参数只覆盖它指定的顶层 key。因此 `session/settings.json` **只需要包含 `hooks` 字段**，不影响用户的其他配置（`permissions`、`model` 等仍从原始 settings 文件读取）。

### cwd 确定时机

Wrapper 执行时 `--cwd $(pwd)` 传入，即用户在哪个目录敲 `claude`，就读哪个目录的项目级配置。切换 worktree 后重新执行，自然读取新 worktree 的配置。

### Merge 策略

同一 hook 事件下的 hooks 数组**追加合并**，poltertty 的 hooks 附加在用户已有 hooks 后面：

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [{ "...用户原有 hook..." }]
      },
      {
        "matcher": "",
        "hooks": [{
          "type": "command",
          "command": "/Users/oopslink/.poltertty/bin/poltertty-cli hook notification --session pts-abc-123",
          "timeout": 10
        }]
      }
    ]
  }
}
```

### 完整注入的 Hook 事件

Hook command 使用 **poltertty-cli 的绝对路径**。hooks 以 agent 子进程运行，不经过 shell integration，PATH 里可能没有 `~/.poltertty/bin/`，因此必须用绝对路径。App 生成 `settings.json` 时展开 `$HOME`。

以下示例中 `<CLI>` = `/Users/oopslink/.poltertty/bin/poltertty-cli`（实际路径在生成时展开）：

```json
{
  "hooks": {
    "SessionStart":     [{ "matcher": "", "hooks": [{ "type": "command", "command": "<CLI> hook session-start --session <PTS_ID>",  "timeout": 10 }] }],
    "Notification":     [{ "matcher": "", "hooks": [{ "type": "command", "command": "<CLI> hook notification --session <PTS_ID>",   "timeout": 10 }] }],
    "UserPromptSubmit": [{ "matcher": "", "hooks": [{ "type": "command", "command": "<CLI> hook prompt-submit --session <PTS_ID>",  "timeout": 10 }] }],
    "PreToolUse":       [{ "matcher": "", "hooks": [{ "type": "command", "command": "<CLI> hook pre-tool-use --session <PTS_ID>",   "timeout": 5, "async": true }] }],
    "PostToolUse":      [{ "matcher": "", "hooks": [{ "type": "command", "command": "<CLI> hook post-tool-use --session <PTS_ID>",  "timeout": 5, "async": true }] }],
    "Stop":             [{ "matcher": "", "hooks": [{ "type": "command", "command": "<CLI> hook stop --session <PTS_ID>",            "timeout": 10 }] }],
    "SubagentStart":    [{ "matcher": "", "hooks": [{ "type": "command", "command": "<CLI> hook subagent-start --session <PTS_ID>",  "timeout": 5, "async": true }] }],
    "SubagentStop":     [{ "matcher": "", "hooks": [{ "type": "command", "command": "<CLI> hook subagent-stop --session <PTS_ID>",   "timeout": 5, "async": true }] }],
    "PreCompact":       [{ "matcher": "", "hooks": [{ "type": "command", "command": "<CLI> hook pre-compact --session <PTS_ID>",     "timeout": 5, "async": true }] }],
    "PostCompact":      [{ "matcher": "", "hooks": [{ "type": "command", "command": "<CLI> hook post-compact --session <PTS_ID>",    "timeout": 5, "async": true }] }],
    "SessionEnd":       [{ "matcher": "", "hooks": [{ "type": "command", "command": "<CLI> hook session-end --session <PTS_ID>",     "timeout": 3 }] }]
  }
}
```

---

## 模块四：Hook 子命令（poltertty-cli hook）

### 通信协议

复用现有 HookServer（HTTP），不新增 socket 协议。

```
POST http://localhost:$POLTERTTY_HTTP_PORT/hooks/<event>
Authorization: Bearer <token>
Content-Type: application/json

{
  "sessionId": "pts-abc-123",
  "agentType": "claude-code",
  "timestamp": 1711000060,
  "payload": { /* agent 通过 stdin 传入的原始 JSON */ }
}
```

Token 从 `~/.poltertty/sessions/<pts-id>/meta.json` 读取。

### 降级处理

所有 `poltertty-cli hook` 命令内置超时，失败静默退出（`exit 0`），确保 agent 不被阻塞。

### 各事件处理

| 事件 | stdin payload | 动作 |
|------|-------------|------|
| `session-start` | `{ session_id, cwd }` | 向 App 注册会话激活 |
| `notification` | `{ title, message, notification_type }` | 推送通知，触发 UI 更新 |
| `prompt-submit` | `{ prompt }` | 清除 "Needs Input" 状态，改为 "Running" |
| `pre-tool-use` | `{ tool_name, tool_input }` | 更新状态为 "Using \<tool\>"（async） |
| `post-tool-use` | `{ tool_name, tool_result }` | 记录工具执行结果，用于进展判断 |
| `stop` | `{ transcript_path }` | Token 计数、transcript 解析 |
| `subagent-start` | `{ agent_name, agent_type }` | 注册 subagent 生命周期 |
| `subagent-stop` | `{ agent_name }` | 标记 subagent 结束 |
| `pre-compact` | `{}` | 标记上下文压缩开始 |
| `post-compact` | `{}` | 标记压缩完成，更新 context 使用率 |
| `session-end` | `{ session_id }` | 标记 session 结束，清除状态 |

---

## 模块五：HookServer 路由（App 侧）

在现有 HookServer 基础上新增路由：

```
POST /hooks/prepare-session    # wrapper 调用：创建 session、合并 settings、生成 token
POST /hooks/session-start      # agent SessionStart
POST /hooks/session-end        # agent SessionEnd
POST /hooks/notification       # agent Notification
POST /hooks/prompt-submit      # agent UserPromptSubmit
POST /hooks/pre-tool-use       # agent PreToolUse（async）
POST /hooks/post-tool-use      # agent PostToolUse（async）
POST /hooks/stop               # agent Stop
POST /hooks/subagent-start     # agent SubagentStart（async）
POST /hooks/subagent-stop      # agent SubagentStop（async）
POST /hooks/pre-compact        # agent PreCompact（async）
POST /hooks/post-compact       # agent PostCompact（async）
GET  /health                   # wrapper ping 检测
```

**注意：** `/hooks/prepare-session` 不需要 token（此时 token 尚未生成），通过请求来源为 localhost 保证安全。其余路由均需 token 校验：

```swift
func validateToken(sessionId: String, token: String) -> Bool {
    guard let session = sessionStore.get(sessionId) else { return false }
    return session.token == token
}
```

---

## 模块六：通知分发（App 侧）

### 通知数据模型

```swift
struct TerminalNotification: Identifiable {
    let id: UUID
    let polterttySessionId: String
    let workspaceId: UUID
    let surfaceId: UUID
    let title: String
    let subtitle: String
    let body: String
    let createdAt: Date
    var isRead: Bool
}
```

### 通知抑制逻辑

```swift
// 通知到达时实时检查，不依赖缓存值，避免切窗时序竞态
let shouldSuppress =
    AppFocusState.isAppFocused()       // app 有焦点
    && selectedTabId == workspaceId    // 正在看这个 tab
    && focusedSurfaceId == surfaceId   // 正在看这个 pane

if shouldSuppress {
    playSuppressedSound()
} else {
    scheduleSystemNotification(content)
}
```

### macOS 系统通知

```swift
let content = UNMutableNotificationContent()
content.title = notification.title
content.subtitle = notification.subtitle
content.body = notification.body
content.userInfo = [
    "polterttySessionId": sessionId,
    "workspaceId": workspaceId.uuidString,
    "surfaceId": surfaceId.uuidString,
    "notificationId": id.uuidString
]

// 点击响应：聚焦窗口 → 切换 tab → 切换 pane → 标记已读
func userNotificationCenter(_:didReceive response:) {
    let workspaceId = response.notification.request.content.userInfo["workspaceId"]
    focusAndNavigate(to: workspaceId)
}
```

### Status Bar 状态映射

| Hook 事件 | Status Bar 显示 |
|-----------|----------------|
| `session-start` | 🟢 Agent Running |
| `pre-tool-use` (Bash) | 🔧 Running Bash |
| `pre-tool-use` (Write) | 📝 Writing File |
| `post-tool-use` | 更新工具执行结果 |
| `notification` (completion) | ✅ Completed |
| `notification` (permission) | ⏳ Needs Input |
| `notification` (error) | ❌ Error |
| `prompt-submit` | 🟢 Running |
| `stop` | 📊 Token: xxx（显示用量） |
| `subagent-start` | 🔀 Subagent: \<name\> |
| `pre-compact` | 🗜 Compacting... |
| `post-compact` | 更新 context 使用率 |
| `session-end` / PID 不存活 | （清除） |

---

## 模块七：Stale Session 清理

Agent 崩溃或 `kill -9` 时，`session-end` hook 不会触发。多重兜底：

1. **PID 检测**（主要）：App 每 30s 遍历活跃 session，检查 `kill -0 <pid>`
2. **App 启动扫描**：启动时扫描所有 session 目录，清理 pid 已死亡的 session
3. **过期清理**：`endedAt` 超过 7 天的目录删除

注：Wrapper 使用 `exec` 替换进程，`trap` 在 `exec` 后失效，因此 **不依赖 bash trap** 做清理。

---

## 环境变量契约

Poltertty 在每个 shell session 初始化时注入：

| 变量 | 用途 | 注入方式 |
|------|------|---------|
| `POLTERTTY_WORKSPACE_ID` | 当前 workspace/tab 标识 | PTY spawn |
| `POLTERTTY_SURFACE_ID` | 当前 pane/surface 标识 | PTY spawn |
| `POLTERTTY_HTTP_PORT` | HookServer 端口 | PTY spawn |
| `POLTERTTY_BIN_DIR` | wrapper 目录，shell integration 用于 PATH 补强 | PTY spawn |
| `POLTERTTY_SHELL_INTEGRATION` | shell integration 脚本绝对路径 | PTY spawn |
| `POLTERTTY_SESSION_ID` | Wrapper 创建后设置，用于嵌套检测 | Wrapper export |
| `POLTERTTY_AGENT_PID` | exec 后即 agent 进程 PID | Wrapper export |
| `POLTERTTY_HOOKS_DISABLED` | 为 1 时 wrapper 直接透传 | PTY spawn（用户开关） |

---

## 降级策略

| 场景 | 行为 |
|------|------|
| `POLTERTTY_SURFACE_ID` 为空（不在 poltertty 内） | wrapper exec 真实 binary，零开销 |
| HTTP server 不可达（超时 750ms） | wrapper exec 透传 |
| `POLTERTTY_HOOKS_DISABLED=1` | wrapper exec 透传 |
| 嵌套检测（`POLTERTTY_SESSION_ID` 已存在） | wrapper exec 透传 |
| `prepare-session` 失败 | wrapper exec 透传 |
| Hook command 执行超时 | timeout 限制，agent 不阻塞，exit 0 |
| HTTP 请求失败 | poltertty-cli 静默退出，exit 0 |

---

## Token 安全

Token 由 App 主进程在 `prepare-session` 时生成：

```swift
func generateSessionToken() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return Data(bytes).base64EncodedString()
}
```

- Token 写入 `meta.json`，文件权限 `chmod 600`
- `/hooks/prepare-session` 不需要 token（此时尚未生成），通过 localhost 来源保证安全
- 其余路由均需 `Authorization: Bearer <token>` + sessionId 绑定校验
- Token 随 session 目录生命周期管理，session 结束后自动失效

---

## 用户控制

Settings UI 提供以下开关：

| 设置项 | 默认值 | 说明 |
|--------|--------|------|
| Agent Integration | ON | 总开关，OFF 时设 `POLTERTTY_HOOKS_DISABLED=1` |
| System Notifications | ON | 是否弹 macOS banner |
| Notification Sound | ON | 抑制通知时是否播放声音 |
| Dock Badge | ON | 未读数显示在 Dock 角标 |
| Supported Agents | claude | 要接管的 agent 列表（控制 `~/.poltertty/bin/` 下的 symlinks） |

关闭总开关后，下次新开的 shell session 生效（已有 session 不打断）。

---

## 与现有架构的集成

| 现有组件 | 集成方式 |
|---------|---------|
| `HookServer` | 新增 `/hooks/*` 路由，复用现有 server |
| `AgentSessionManager` | 接收 hook 事件，更新 session 状态 |
| `BottomStatusBarView` | 订阅 per-surface agent 状态，显示工具调用信息 |
| `TabBarViewModel` | 订阅 workspace 级未读数，显示角标 |
| `NotificationStore`（新增） | 管理通知列表、未读状态、macOS 通知调度 |

---

## 不包含（明确排除）

- 修改用户全局 `~/.claude/settings.json`（零侵入原则）
- 支持远程/SSH 场景下的通知
- Codex 等其他 agent 的具体 payload 解析（按需扩展）
- Session 云端备份（后续独立讨论）
