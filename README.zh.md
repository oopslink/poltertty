# Poltertty

**为 AI 原生开发时代设计的 Agent 友好型终端。**

Poltertty 是 [Ghostty](https://ghostty.org) 的 macOS fork，在完整保留 Ghostty 终端核心与配置兼容性的基础上，增加了对 AI Agent 工作流的一流支持：Workspace 工作区管理、内置文件浏览器、完整 Git 面板、实时 Agent 会话监控、内嵌 MCP 服务器，以及深度 tmux 集成。

[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)](https://github.com/oopslink/poltertty)
[![Swift](https://img.shields.io/badge/language-Swift%2FSwiftUI-orange)](https://github.com/oopslink/poltertty)
[![Based on Ghostty](https://img.shields.io/badge/based%20on-Ghostty-purple)](https://ghostty.org)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

[English README](README.md)

---

## 为什么选择 Poltertty？

现代 AI 编程 Agent——Claude Code、Gemini CLI、OpenCode——运行在终端里。但终端是为人类设计的，不是为 Agent 设计的。Poltertty 弥合了这个差距：

- **Agent 需要项目上下文。** Workspace 为每个项目提供独立的终端环境，布局与配置自动持久化。
- **Agent 需要可观测性。** 内置 Agent Monitor 实时追踪运行中的会话、Subagent 调用树和工作状态，无需外部仪表盘。
- **Agent 需要控制权。** 内嵌 MCP 服务器将终端操作（发送文本、分割 Pane、截图）直接暴露给任何支持 MCP 的 Agent。
- **人类需要保持专注。** 文件浏览器、Git 面板、tmux 集成和 per-pane 状态栏让所有信息一目了然，无需离开终端。

---

## 功能特性

### Workspace 工作区管理

持久化的、按项目隔离的终端环境：

- **按需启用** — Workspace 模式默认关闭；通过菜单或按 `⌥⌘P` 切换侧边栏来启用
- **创建与管理** — 每个 Workspace 拥有独立的名称、颜色、图标、根目录和描述
- **分组** — 将相关 Workspace 整理到可折叠分组中，侧边栏拖拽重新排序
- **持久化** — 配置与窗口快照自动保存至 `~/.config/poltertty/workspaces/`，重启后自动恢复
- **快速切换** — `Cmd+K` 在 Workspace 间瞬间跳转
- **侧边栏** — 右键菜单支持重命名、删除和移入分组
- **单窗口限制** — 每个 Workspace 独占一个窗口；`⌘N` 在 Workspace 模式下打开一个独立的普通终端窗口

### Git Worktree 管理

在侧边栏中直接管理 `git worktree`：

- **Worktree 列表** — 所有关联的 worktree 显示在 Workspace 条目下，实时文件系统监控
- **创建与删除** — 通过 sheet 界面选择分支创建 worktree；删除时弹出确认
- **缺失检测** — 在应用外被删除的 worktree 会以视觉方式标记
- **文件浏览器联动** — 单击即可将文件浏览器根目录切换到任意 worktree

### Git 面板

嵌入终端侧边栏的完整 Git 界面（`f`/`g` 切换）：

- **变更视图** — staged 和 unstaged 文件列表；支持对单个文件执行 stage、unstage 和 discard
- **提交历史** — 浏览带作者、日期和提交信息的历史记录
- **Diff 查看器** — 内联 diff 并带语法高亮；全屏模式下保留提交侧边栏
- **文件历史** — 在 sheet 中查看单个文件的提交历史
- **跟随 Worktree** — 自动反映当前活跃 worktree 的 Git 状态

### AI Agent 监控

对 AI 编程 Agent 会话的原生可视化支持（`Cmd+Opt+M`）：

- **启动面板** — 一键启动 Claude Code、Gemini CLI、OpenCode 及自定义命令；支持所有 6 种 Claude 权限模式
- **会话监控** — 通过内置 Hook Server 接收 Claude Code 生命周期事件，实时展示 Agent 工作状态
- **Subagent 跟踪** — 可视化 Agent 调用树，横向图视图实时追踪工具调用、起止时间和 Token 用量
- **会话历史** — 持久化历史会话，按会话汇总 Token 计费
- **通知** — 三级通知系统（等待中 / 出错 / 完成）；目标 Pane 处于焦点时自动抑制系统通知
- **外部会话发现** — 自动发现并展示系统中正在运行的 Claude Code（`.jsonl`）、OpenCode（SQLite）和 Gemini 会话

### Agent Dashboard

跨所有会话、所有工作区的全局视图（`Cmd+Opt+D`）：

- **表格与卡片模式** — 在紧凑表格和卡片网格之间切换
- **跨工作区聚合** — 在一个地方查看所有活跃和历史会话
- **跳转到 Pane** — 双击任意行即可导航并脉冲高亮目标 Pane

### Ctrl API — 终端 MCP 服务器

内嵌 MCP HTTP 服务器，让 AI Agent 以编程方式控制终端：

- **MCP 工具** — `list_panes`、`focus_pane`、`split_pane`、`send_text`、`new_tab`、`screenshot`、`set_pane_annotation`、`get_pane_annotation`、`list_worktrees`、`create_worktree`、`get_git_status`
- **自动配置** — `SettingsMerger` 在启动时自动将 MCP 服务器 URL 注入 Claude Code settings，无需手动设置
- **SSE 事件流** — Agent 可通过 Server-Sent Events 订阅实时终端事件
- **REST API** — 版本化路由（`/v1/`），语义化 HTTP 状态码
- **Ctrl API Monitor** — 内置面板（`⌥⌘C`），展示所有 API 调用并带 JSON 语法高亮和可调整大小的详情面板

### Pane 注释

为分割 Pane 附加标签，提升 Agent 的情境感知：

- **内联编辑** — 点击状态栏中的注释按钮打开 Popover 编辑器
- **浮动卡片** — 在终端内容上方以细微的悬浮卡片显示注释
- **MCP 可访问** — Agent 可通过 `get/set_pane_annotation` 读写注释

### 快速分割 Pane 焦点

键盘优先的 Pane 间导航：

- **双击 Cmd** — 触发 Pane 选择器覆盖层；按数字键即可立即跳转到对应 Pane
- **编号徽标** — 选择器激活时，每个 Pane 会显示带短暂闪烁动画的编号徽标

### 文件浏览器

直接集成在终端内的轻量文件树面板（`⌥⌘F`）：

- **树形视图** — 浏览 Workspace 根目录；单击展开/折叠目录
- **多选操作** — `Cmd+A` 全选、`Shift+Click` 范围选择，支持批量删除和移动
- **拖拽** — 多文件跨目录拖拽
- **智能过滤** — 快速过滤 Chip（如"仅显示未提交文件"）；面包屑导航
- **文件预览** — 点击任意文件预览内容，带语法高亮和行号
- **Git 状态徽标** — 文件旁实时展示变更状态（`M`/`A`/`?`）；直接在文件浏览器中执行 stage/unstage/diff
- **键盘导航** — 方向键浏览，`Enter` 展开，`Space` 将路径注入当前终端，`?` 查看快捷键帮助
- **右键菜单** — 在 Finder 中显示、复制路径、内联重命名、查看文件历史、Discard 变更

### App Launcher

双击 `Shift` 触发的模糊命令面板：

- **Levenshtein 排名** — 基于编辑距离的搜索，覆盖所有菜单项和 Poltertty 专属操作
- **菜单路径副标题** — 每个结果显示完整菜单路径，便于定位命令位置
- **按窗口隔离** — 仅作用于当前 key window，不影响其他 Poltertty 窗口

### tmux 深度集成

将 tmux 会话管理直接呈现于终端 UI：

- **会话面板** — 在专属面板中浏览和管理 session、window 和 pane（`Cmd+Shift+X`）
- **Tab Attach** — 将 tmux 会话作为终端 Tab attach（`Cmd+Opt+T`）；Tab 内的窗口栏支持切换 tmux 窗口、新建和 detach
- **状态栏按钮** — 直接从分割 Pane 状态栏一键 attach tmux
- **关闭确认** — 关闭含 tmux 会话的 Tab 时弹出确认

### 底部状态栏

始终可见的上下文信息，per split pane：

- **Git 状态** — 分支名和变更数，实时更新；追踪前台进程的 CWD，`cd` 后状态自动跟随
- **Agent 状态** — per-pane Agent 指示器；点击查看会话详情或切换到其他会话
- **Worktree 徽标** — 当 Pane 位于关联 worktree 内时显示标识
- **tmux Attach 按钮** — 一键 attach tmux
- **焦点感知** — 非焦点 Pane 时自动变暗

---

## 与 Ghostty 的关系

Poltertty 直接 fork 自 [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty)，持续跟踪上游。

| 层面 | 说明 |
|------|------|
| **底层终端** | 终端模拟、Metal 渲染、CoreText 字体、键绑定和配置系统均来自 Ghostty，原封不动 |
| **新功能** | 所有新增功能以 Swift/SwiftUI 实现，位于 `macos/Sources/Features/` 下的独立模块 |
| **配置兼容** | Ghostty 的所有配置项均可直接使用，配置文件路径为 `~/.config/poltertty/config` |

终端模拟相关文档请参阅 [Ghostty 官方文档](https://ghostty.org/docs)。

---

## 快速开始

### 环境要求

- macOS 14 (Sonoma) 或更高版本
- Xcode 15 或更高版本
- [Zig](https://ziglang.org/)（所需版本见 [docs/rules/build-rules.md](docs/rules/build-rules.md)）

### 构建

```bash
# 克隆仓库
git clone https://github.com/oopslink/poltertty.git
cd poltertty

# 初始化本地 Git Hooks（新克隆仓库后执行一次）
make init-git-hooks

# 开发构建并运行
make run-dev

# Release 构建
make release

# 查看所有可用命令
make help
```

详细构建说明见 [docs/rules/build-rules.md](docs/rules/build-rules.md)。

---

## 贡献

Poltertty 采用分支保护工作流：

1. 所有特性开发必须在 `.worktrees/` 下的 git worktree 中进行
2. 变更通过 Pull Request 合并到 `main`，禁止直接推送

完整贡献流程见 [docs/rules/development-rules.md](docs/rules/development-rules.md)。

---

## 许可证

Poltertty 继承 Ghostty 的 [MIT 许可证](LICENSE)。本项目新增代码同样采用 MIT 许可证。
