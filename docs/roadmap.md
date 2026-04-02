# Poltertty 开发路线图

> 基于竞品分析（2025 年 3 月 + 2026 年 4 月 cmux 深度调研），聚焦"Ghostty 原生体验 + Workspace 管理 + AI Agent 协作层"定位。

---

## 总览

```
Phase 1 ──── Session 持久化 · Yazi 集成 · Worktree 绑定 · 侧边栏元数据增强
Phase 2 ──── Agent 调度台 · Ctrl API 扩展 · 可观测性 · OSC 通知序列
Phase 3 ──── Layout-as-Code · Quick Terminal 融合 · Popup Overlay 窗口
```

---

## Phase 1：核心基础

### 1.1 Session 持久化与恢复

**价值**：Ghostty 社区 #1 未满足需求（561 upvote），tmux 用户迁移的最后心理障碍。

**功能范围**：
- 每个 Workspace 在关闭时自动保存快照：pane 布局、工作目录、tab 名称
- App 重启后提示恢复上次 Session，支持选择性恢复
- Workspace 创建表单新增"从快照创建"选项
- 快速切换器中显示每个 Workspace 的上次保存时间与活跃 pane 数

**技术基础**：`saveSnapshot`/`RestoreView` 已存在，需扩展为持久化到磁盘的完整 layout 序列化。

**成功标准**：关闭并重开 App，工作目录与 pane 布局完整恢复，无需任何手动操作。

---

### 1.2 Yazi 替换内置文件管理器

**价值**：Yazi 是 2024-2025 年增长最快的 TUI 文件管理器（Rust，Ghostty/Kitty 图像协议支持），社区主流偏向"终端模拟器作为平台，文件管理交给专业工具"。当前内置文件浏览器维护成本高且功能难以追上专业工具。

**功能范围**：
- **启动方式**：点击侧边栏 File Browser 图标，在右侧 panel 中打开 yazi，而非原生 SwiftUI 树
- **图像预览**：Ghostty 已支持 Kitty 图像协议，yazi 图片预览开箱即用
- **双向联动**：
  - yazi 中打开文件 → 在新 tab 中启动 `$EDITOR`
  - Workspace 切换时，yazi 自动 `cd` 到对应 workspace 目录（通过 `ya pub-sub` 事件）
- **快捷键**：侧边栏 File Browser 按钮 / 可配置快捷键 直接聚焦到 yazi pane
- **降级处理**：若系统未安装 yazi，面板显示安装引导，提供 `brew install yazi` 一键提示

**迁移策略**：
- 移除 `FileBrowser/` 目录下的 SwiftUI 实现（`FileBrowserPanel`、`FileBrowserViewModel`、`FileNodeRow` 等）
- 保留 `GitStatusService`（Git Panel 仍需使用）
- 保留 `SyntaxHighlightView`（可复用于 Git diff 预览）

**成功标准**：侧边栏 File Browser 入口打开 yazi，图片预览正常，切换 Workspace 时 yazi 目录自动跟随。

---

### 1.3 Workspace ↔ Git Worktree 绑定

**价值**：多 Agent 并行工作流的基础设施——每个 Agent 在独立 worktree，Poltertty 提供跨 worktree 的统一视图，这是 lazygit 无法覆盖的场景。

**功能范围**：
- Workspace 创建时新增"绑定 Git Worktree"选项：选择已有 worktree 或新建
- 侧边栏 Workspace 条目右侧显示 branch 名 + dirty 状态指示点（红点 = 有未提交修改）
- Git Panel 新增"所有 Workspace 变更汇总"标签页：一行一个 worktree，展示变更文件数与 branch
- 切换 Workspace 时，yazi（1.2 落地后）自动 cd 到该 worktree 根目录

**成功标准**：同时运行三个 AI Agent 于三个 worktree，Poltertty 侧边栏能一眼看出哪个有变更、哪个 branch 落后于 main。

---

### 1.4 侧边栏 Workspace 元数据增强

**价值**：cmux 调研中最受用户好评的功能（侧边栏信息密度）——不切换到对应 Workspace，仅看侧边栏就能感知每个 Workspace 的运行状态。当前 Poltertty 侧边栏仅显示 Workspace 名称，信息密度严重不足。

**功能范围**：
- **监听端口列表**：扫描各 Workspace 前台进程占用的 TCP 端口，以小徽标形式展示（如 `:3000` `:8080`）；点击端口标签可在浏览器或新 tab 打开
- **PR 状态徽标**：若 Workspace 绑定了 Git Worktree（1.3 落地后），通过 `gh pr status` 查询当前 branch 的 PR 编号与状态（Open / Draft / Merged），显示在 branch 名旁
- **Agent 活跃指示**：若该 Workspace 有注册的 Agent session（2.1 落地后），显示小 bot 图标 + 当前状态色
- **未读通知角标**：结合 2.1 通知系统，有未读通知的 Workspace 显示蓝色圆点

**技术路径**：
- 端口扫描：`lsof -iTCP -sTCP:LISTEN -P` 解析前台进程 PID 对应的端口；每 5 秒轮询一次
- PR 状态：后台线程异步调用 `gh` CLI，缓存结果（60 秒 TTL），避免阻塞 UI
- UI 布局：Workspace 条目高度微增，元数据以小字号横排，不遮挡核心操作区

**依赖**：1.3 Worktree 绑定（PR 状态需要绑定 branch），2.1 通知系统（未读角标）

**成功标准**：侧边栏中 5 个 Workspace 并列时，不点击任何条目，能看出哪个有 agent 在跑、哪个服务在 :3000 上、哪个 branch 有未合并 PR。

---

## Phase 2：Agent 协作层

### 2.1 Agent Monitor → 多 Agent 调度台

**价值**：2025 年开发者最大痛点——管理并行 AI Agent 时没有统一视图（Claude Squad、Agent Deck 等外部工具的出现即是证明）。Poltertty 在终端内做比外部工具更有整合优势。

**功能范围**：
- 侧边栏新增 **Agents** 区块，列出所有已注册 Agent session，每条显示：
  - Agent 名称（可自定义标签）
  - 状态徽标：`运行中` / `等待输入` / `已完成` / `出错`
  - 所属 Workspace / Worktree
- 点击 Agent 条目 → 立即聚焦到对应 tab/pane
- Agent 任务完成时触发 macOS 通知（标题 = Agent 标签，内容 = 最后一行输出）
- 支持在调度台中发送快捷指令（如"继续"/"中止"）到对应 pane

**Ctrl API 配合**（见 2.2）：Agent 通过 `set_agent_label` 自报状态，Poltertty 订阅后更新 UI。

**OSC 通知序列兼容**（见 2.4）：Agent 也可通过标准 OSC 序列发送通知，无需集成 Ctrl API。

**成功标准**：同时跑 5 个 Claude Code session，不打开任何一个 tab，能从 Agents 面板知道每个的进度并在出错时立即定位。

---

### 2.2 Ctrl API 扩展

**价值**：巩固 Poltertty 作为 AI Agent 协作层的护城河，让 Agent 能以编程方式操控完整的开发环境。

**现有接口**：`ping`、`new_tab`、`send_text`、`list_panes`、`focus_pane`、`split_pane`

**新增接口**：

| 接口 | 功能 |
|------|------|
| `create_workspace` | 创建新 Workspace，可指定名称、目录、绑定 worktree |
| `set_agent_label` | Agent 设置自身标签与状态（供调度台展示） |
| `get_workspace_state` | 获取完整状态快照（布局 + 目录 + Agent 列表） |
| `notify` | 向用户发送带标题的 macOS 通知 |
| `open_in_file_browser` | 在 yazi pane 中定位到指定路径 |
| SSE 事件：`agent_status_changed` | 订阅 Agent 状态变更推送 |
| SSE 事件：`workspace_switched` | 订阅 Workspace 切换事件 |

**成功标准**：外部 Agent 可通过 MCP 工具完整创建 Workspace、绑定 worktree、注册自身标签、完成后通知用户——无需用户手动操作任何 UI。

---

### 2.3 Agent 可观测性增强（基于 Hook 系统）

**价值**：Claude Code hook 系统暴露了大量生命周期事件，目前 Poltertty 仅消费了其中少数。利用未接入的 hook 事件可以让用户对"agent 正在做什么"有更清晰的感知，无需额外工具。

**功能范围**：

| 优先级 | Hook 事件 | 功能 |
|--------|-----------|------|
| 高 | `PostToolUse` | 在 Monitor Panel 展示工具执行耗时 timeline，PreToolUse/PostToolUse 配对计算每个工具的耗时 |
| 高 | `PostCompact` | 在 session 时间线上打"上下文已压缩"标记，提示用户 agent 记忆清零点 |
| 中 | `SubagentStart` / `SubagentStop` | 追踪 subagent 嵌套层级，CtrlAPIRecord 新增 `agentDepth` 字段，statusbar agent 按钮显示子 agent 数量角标 |
| 中 | `PermissionDenied` | 在 Monitor Panel 中以红色记录被拒工具调用，显示拒绝计数角标，帮助用户判断 agent 是否被过度限制 |
| 低 | `SessionEnd` | 将 session 统计摘要（工具调用次数、失败次数、压缩次数、总耗时）持久化到磁盘，供事后审计 |

**技术路径**：`/hooks/prepare-session` 订阅阶段注册上述 hook 类型；CtrlAPIRecord 扩展字段；CtrlAPIMonitorPanel 新增 Timeline 视图。

**成功标准**：不打开任何外部工具，能在 Monitor Panel 中看到 agent 执行了哪些工具、每步耗时多少、上下文何时被压缩、哪些操作被权限拦截。

---

### 2.4 OSC 通知序列支持（OSC 777 / OSC 99）

**价值**：cmux 调研中发现的低成本高价值功能。OSC 777（RXVT）和 OSC 99（Kitty）是标准终端通知协议，任何 shell 脚本、AI agent 或 CI 工具都可以通过简单的 `printf` 触发通知，无需集成 Ctrl API。实现成本低，但能大幅扩大 Poltertty 通知系统的覆盖面。

**功能范围**：
- **OSC 777 支持**（RXVT 兼容）：`printf '\e]777;notify;标题;内容\a'` 触发通知面板消息
- **OSC 99 支持**（Kitty 协议）：支持 `title`、`body`、`subtitle` 字段，通知 ID 用于去重和更新
- 通知自动关联到来源 Workspace：哪个 pane 发的 OSC 序列，通知就归属哪个 Workspace
- **抑制规则**：来源 Workspace 当前处于活跃/聚焦状态时，静默通知（不弹桌面提示）；Notification Panel 已打开时抑制
- **与 2.1 通知系统复用**：OSC 触发的通知走同一条通知队列，在侧边栏显示未读角标（1.4 落地后）

**标准 Hook 集成**：Claude Code `Stop` hook 可通过 OSC 序列通知 Poltertty，不需要 Ctrl API 集成：
```bash
# ~/.claude/hooks/stop.sh
printf '\e]777;notify;Claude 完成;%s\a' "$CLAUDE_SESSION_ID"
```

**技术路径**：在 Ghostty libghostty 的 OSC 处理层新增 777/99 case，解析 payload 后通过 `NotificationService` 分发。

**成功标准**：任意 shell 脚本执行 `printf '\e]777;notify;构建完成;main 分支 CI 通过\a'` 后，Poltertty 侧边栏对应 Workspace 出现未读通知角标，Notification Panel 中显示完整通知内容。

---

## Phase 3：Power User 与体验打磨

### 3.1 Layout-as-Code

**价值**：Zellij 最受称道的功能，被 tmux 迁移者反复提及；Kitty 0.43 也刚加入。给 power user 提供自动化入口。

**功能范围**：
- 支持用 YAML/TOML 文件描述 Workspace 布局（tabs、splits、目录、初始命令）
- CLI 参数：`Poltertty --workspace-file ./my-project.yaml`
- 内置布局模板（`ai-parallel`：3 个并排 worktree + 1 个 Git Panel）
- Ctrl API：`load_workspace_file` 接口，Agent 可动态加载布局

**布局文件示例**：
```yaml
name: my-api-project
worktree: ~/projects/api
tabs:
  - name: server
    dir: ~/projects/api
    command: cargo watch
  - name: agent
    split: vertical
    panes:
      - dir: ~/projects/api
      - dir: ~/projects/api/.worktrees/feat-auth
```

**成功标准**：一条命令从零启动包含 3 个 tab + 预设目录的完整开发环境。

---

### 3.3 Popup Overlay 窗口

**价值**：cmux 社区高票功能请求（源于 tmux `popup` 命令）。LazyGit、yazi、fzf 等 TUI 工具在分屏中长期占用 pane 位置，浪费屏幕空间；用 Popup 浮动窗口调用这类工具，用完即关，不破坏当前布局。

**功能范围**：
- 快捷键（默认 `⌘⇧P`）在当前 Workspace 上方弹出浮动终端 pane，居中显示，宽高可配置（默认 80%）
- Popup 内可运行任意命令：`lazygit`、`yazi`、`fzf`、`htop` 等
- 按 `ESC` 或 `q`（进程退出）自动关闭 Popup，回到原焦点
- 支持配置"命名 Popup"：特定 Popup 绑定预设命令，快捷键直接调用（如 `⌘G` → lazygit popup）
- Popup 关闭后不保留历史，下次打开是全新 shell（可选：保留同一 Popup 会话）

**典型用法**：
```
Cmd+G → lazygit popup（查看 diff，commit，按 q 关闭）
Cmd+Shift+P → 空 shell popup（临时命令）
```

**技术路径**：在当前 Window 上层添加一个浮动 `NSPanel`，内嵌 Ghostty Surface；焦点 trap 在 Panel 内，按 ESC/进程退出时 dismiss。

**成功标准**：`⌘G` 调出 lazygit，完成提交操作后按 `q`，Popup 关闭，焦点回到原来的 pane，原 pane 布局完全不变。

---

### 3.2 Quick Terminal + Workspace 切换融合

**价值**：Ghostty Quick Terminal（悬浮终端）是最受好评的功能之一；让它能直接看到 Workspace 状态，是独特的 macOS-native 体验。

**功能范围**：
- Quick Terminal 底部常驻 Workspace 切换条（紧凑版，仅显示名称 + 状态点）
- `Cmd+数字` 在 Quick Terminal 中直接切换到对应 Workspace
- Quick Terminal 中可查看 Agents 面板（只读，不操作）

**成功标准**：不离开当前 App，通过 Quick Terminal 快捷键切换到目标 Workspace 并立即开始工作。

---

## 不在路线图内

以下方向经竞品分析明确排除：

| 方向 | 排除原因 |
|------|---------|
| 内置 AI（云端） | Warp 最大教训：终端数据上传红线；Poltertty 定位是 Agent 控制台，不是 AI 终端 |
| 全功能 Git 客户端 | lazygit 生态成熟，Git Panel 只做"Agent 变更 review 辅助" |
| 订阅制/账号体系 | 用户对终端类产品的账号要求极度反感 |

---

## 依赖关系

```
1.2 Yazi 集成
    └── 1.3 Worktree 绑定（yazi cd 跟随需要 1.2 先落地）
            ├── 1.4 侧边栏元数据增强（PR 状态需要 branch 绑定）
            └── 2.1 Agent 调度台（跨 worktree 状态需要 1.3 数据）
                    └── 1.4 未读角标（需要 2.1 通知系统）

1.1 Session 持久化（独立，可并行）

2.2 Ctrl API 扩展（与 2.1 并行，互为前提）
2.3 Agent 可观测性（依赖 2.2 的 hook 接收基础，可与 2.1 并行）
2.4 OSC 通知序列（独立，可与 2.1 并行；通知合并到 2.1 的队列）

3.1 Layout-as-Code（依赖 1.1 的序列化方案）
3.2 Quick Terminal 融合（依赖 2.1 的 Agents 面板）
3.3 Popup Overlay 窗口（独立，可并行）
```
