# Poltertty 开发路线图

> 基于竞品分析（2025 年 3 月 + 2026 年 4 月 cmux 深度调研），聚焦"Ghostty 原生体验 + Workspace 管理 + AI Agent 协作层"定位。

---

## 完成状态总览

```
Phase 1 ──── Session 持久化 ✅ · Yazi 集成 ✅ · 侧边栏元数据增强 ✅
Phase 2 ──── Agent 调度台（大部分 ✅）· Ctrl API 扩展（大部分 ✅）· 可观测性 ✅ · OSC 通知序列
Phase 3 ──── Layout-as-Code · Quick Terminal 融合 · Popup Overlay 窗口
```

---

## Phase 1：核心基础

### ✅ 1.1 Session 持久化与恢复

已在 #135 完整实现。每个 Workspace 关闭时自动保存快照，App 重启后可选择性恢复，创建表单支持"从快照创建"选项。

---

### ✅ 1.2 Yazi 替换内置文件管理器

已实现。侧边栏 File Browser 入口打开 yazi，Workspace 切换时 yazi 自动 cd 跟随，图片预览正常，release 构建自动打包 yazi/ya/delta 工具。

---

### ✅ 1.3 侧边栏 Workspace 元数据增强

已实现。侧边栏 Workspace 条目展示监听端口徽标（`:3000` `:8080`，点击可打开）、PR 状态徽标（Open/Draft/Merged）、Agent 活跃图标，未读通知角标已接入 `AgentNotificationStore`。不切换 Workspace 即可感知各实例运行状态。

---

## Phase 2：Agent 协作层

### ✅（大部分）2.1 Agent Monitor → 多 Agent 调度台

**已实现**：
- `AgentDashboardView`（独立浮窗，非侧边栏）：列出所有 Agent session，按 Workspace 分组，显示状态、运行时长，键盘导航
- `AgentSession` 状态机：`launching` / `working` / `idle` / `done` / `error`
- `AgentNotificationStore`：通知去重、持久化、macOS 系统通知（waiting/error 事件触发）
- 点击 Agent 条目 → `PaneLocator` 聚焦到对应 tab/pane（`#143` pane annotation 显示）
- Workspace 未读通知角标：侧边栏已接入
- `ExternalSessionDiscovery`：自动发现 Claude Code / Gemini / OpenCode session（无需集成 Ctrl API）

**尚未实现**：
- 侧边栏内嵌 Agents 区块（当前为独立浮窗，非侧边栏常驻）
- 调度台中向 pane 发送快捷指令（"继续"/"中止"）

**Ctrl API 配合**（见 2.2）：Agent 通过 `set_agent_label` 自报状态，Poltertty 订阅后更新 UI。

**OSC 通知序列兼容**（见 2.4）：Agent 也可通过标准 OSC 序列发送通知，无需集成 Ctrl API。

---

### ✅（大部分）2.2 Ctrl API 扩展

**已实现接口**：`ping`、`new_tab`、`send_text`、`list_panes`（含位置字段）、`focus_pane`、`split_pane`（支持 command 参数）、`list_worktrees`、`create_worktree`、`get_git_status`、`get_instance_info`（workspace name + rootDirectory）、`screenshot`

**尚未实现**：

| 接口 | 功能 |
|------|------|
| `create_workspace` | 创建新 Workspace，可指定名称、目录 |
| `set_agent_label` | Agent 设置自身标签与状态（供调度台展示） |
| `get_workspace_state` | 获取完整状态快照（布局 + 目录 + Agent 列表） |
| `notify` | 向用户发送带标题的 macOS 通知 |
| `open_in_file_browser` | 在 yazi pane 中定位到指定路径 |
| SSE 事件：`agent_status_changed` | 订阅 Agent 状态变更推送 |
| SSE 事件：`workspace_switched` | 订阅 Workspace 切换事件 |

---

### ✅ 2.3 Agent 可观测性增强（基于 Hook 系统）

已在 #141 实现。Monitor Panel 展示顶层工具调用耗时 timeline，PostCompact 打"上下文已压缩"标记，SubagentStart/Stop 追踪嵌套层级并显示角标，PermissionDenied 红色记录被拒工具调用。

---

### 2.4 OSC 通知序列支持（OSC 777 / OSC 99）

**价值**：低成本高价值。任何 shell 脚本、AI agent 或 CI 工具都可以通过简单的 `printf` 触发通知，无需集成 Ctrl API。

**功能范围**：
- **OSC 777 支持**（RXVT 兼容）：`printf '\e]777;notify;标题;内容\a'` 触发通知面板消息
- **OSC 99 支持**（Kitty 协议）：支持 `title`、`body`、`subtitle` 字段，通知 ID 用于去重和更新
- 通知自动关联到来源 Workspace：哪个 pane 发的 OSC 序列，通知就归属哪个 Workspace
- **抑制规则**：来源 Workspace 当前处于活跃/聚焦状态时，静默通知；Notification Panel 已打开时抑制
- **与现有通知系统复用**：OSC 触发的通知走同一条 `AgentNotificationStore` 队列，侧边栏角标自动更新

**标准 Hook 集成**：Claude Code `Stop` hook 可通过 OSC 序列通知 Poltertty，不需要 Ctrl API 集成：
```bash
# ~/.claude/hooks/stop.sh
printf '\e]777;notify;Claude 完成;%s\a' "$CLAUDE_SESSION_ID"
```

**技术路径**：在 Ghostty libghostty 的 OSC 处理层新增 777/99 case，解析 payload 后通过 `AgentNotificationStore` 分发。

**成功标准**：任意 shell 脚本执行 `printf '\e]777;notify;构建完成;main 分支 CI 通过\a'` 后，Poltertty 侧边栏对应 Workspace 出现未读通知角标，Notification Panel 中显示完整通知内容。

---

### 2.5 Agent Browser（内嵌浏览器面板）

**价值**：AI Agent 工作流中最常见的盲区——Agent 需要与 localhost 开发服务器、Web UI 交互，但终端里看不到浏览器状态。cmux 深度调研验证此功能对 AI-first 开发者高价值：无需 Playwright/Puppeteer 即可做 Web 自动化，且 DOM 快照 + 短引用的 API 设计对 LLM 极友好。

**功能范围**：

**一期：浏览器面板 UI**
- 侧边栏新增浏览器 pane 入口，在终端旁以分割面板方式嵌入 WKWebView
- 工具栏：地址栏、前进/后退/刷新、开发者工具快捷键
- 与 Workspace 绑定：切换 Workspace 时浏览器面板跟随保留
- 快捷键打开/关闭/聚焦浏览器面板

**二期：Scripting API（Agent 自动化）**
- Ctrl API 新增 `browser.*` 方法族，供 Agent 通过 Socket 或 CLI 控制浏览器
- 核心 API：

| API | 功能 |
|-----|------|
| `browser.snapshot` | 获取 ARIA 可访问性树快照，元素自动编号（e1/e2/e3...） |
| `browser.navigate` | 导航到 URL |
| `browser.click` / `browser.fill` | 点击元素 / 填充表单（支持快照引用或 CSS 选择器） |
| `browser.eval` | 执行任意 JavaScript |
| `browser.wait` | 等待选择器/URL/加载状态/文本出现 |
| `browser.screenshot` | 截图（返回文件路径或 base64） |
| `browser.get.text` | 获取元素文本内容 |
| `browser.open_split` | 在当前终端旁打开浏览器面板并导航 |

- CLI 接口：`poltertty browser <surface> <action> [args]`

**技术方案**：
- 浏览器引擎：**WKWebView**（macOS 原生，非 Electron，非系统浏览器调用）
- 面板类型：新增 `BrowserPanel`，与 `TerminalPanel`/`YaziPanel` 并列
- Snapshot 实现：通过注入 JavaScript 遍历 DOM，生成 ARIA 树 + CSS 选择器映射表
- 与现有 Ctrl API Socket 复用同一传输层（见 2.2）

**参考实现**：cmux 的 `BrowserPanel.swift`（WKWebView 管理）+ `TerminalController.swift`（browser.* API 实现），两者同为 Ghostty fork，架构完全兼容。注意 cmux 采用 GPL-3.0，实现需独立开发。

**依赖**：2.2 Ctrl API（Socket 传输层）；一期 UI 可独立先行

**成功标准**：
- 一期：侧边栏点击入口，终端旁出现 WKWebView 浏览器面板，支持手动浏览
- 二期：Agent 通过 `poltertty browser <surface> snapshot` 获取 DOM 快照，通过 `click`/`fill` 操作 localhost 上的 Web 表单，通过 `screenshot` 截图验证结果——全程无需离开终端环境

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

### 3.2 Quick Terminal + Workspace 切换融合

**价值**：Ghostty Quick Terminal（悬浮终端）是最受好评的功能之一；让它能直接看到 Workspace 状态，是独特的 macOS-native 体验。

**功能范围**：
- Quick Terminal 底部常驻 Workspace 切换条（紧凑版，仅显示名称 + 状态点）
- `Cmd+数字` 在 Quick Terminal 中直接切换到对应 Workspace
- Quick Terminal 中可查看 Agents 面板（只读，不操作）

**成功标准**：不离开当前 App，通过 Quick Terminal 快捷键切换到目标 Workspace 并立即开始工作。

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
✅ 1.1 Session 持久化（已完成）
✅ 1.2 Yazi 集成（已完成）
   1.3 侧边栏元数据增强（可立即开始，未读角标前置已满足）

✅ 2.1 Agent 调度台（大部分完成；侧边栏 Agents 区块 + 发送快捷指令待实现）
✅ 2.2 Ctrl API 扩展（大部分完成；set_agent_label / SSE 事件等待实现）
✅ 2.3 Agent 可观测性（已完成）
   2.4 OSC 通知序列（独立，可随时并行）
   2.5 Agent Browser（一期 UI 独立；二期依赖 2.2 Socket 传输层）

   3.1 Layout-as-Code（依赖 1.1 序列化方案，前置已满足）
   3.2 Quick Terminal 融合（依赖 2.1 Agents 面板）
   3.3 Popup Overlay 窗口（独立，可随时并行）
```
