# Poltertty

**为 AI 原生开发时代设计的 Agent 友好型终端。**

Poltertty 是 [Ghostty](https://ghostty.org) 的 macOS fork，在完整保留 Ghostty 终端核心与配置兼容性的基础上，增加了对 AI Agent 工作流的一流支持：Workspace 工作区管理、内置文件浏览器、实时 Agent 会话监控，以及深度 tmux 集成。

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
- **Agent 需要 Hook 接入点。** 内嵌的 HTTP Hook Server 直接接收 Claude Code 生命周期事件，无需任何胶水代码即可构建响应式工作流。
- **人类需要保持专注。** 文件浏览器、tmux 集成和状态栏让所有信息一目了然，无需离开终端。

---

## 功能特性

### Workspace 工作区管理

持久化的、按项目隔离的终端环境：

- **创建与管理** — 每个 Workspace 拥有独立的名称、颜色、图标、根目录和描述
- **分组** — 将相关 Workspace 整理到可折叠分组中，保持侧边栏整洁
- **持久化** — 配置与窗口快照自动保存至 `~/.config/poltertty/workspaces/`，重启后自动恢复
- **临时 Workspace** — 打开目录时创建临时 Workspace，退出后自动清理，不写入磁盘
- **快速切换** — `Cmd+K` 在 Workspace 间瞬间跳转
- **侧边栏** — 右键菜单支持重命名和删除；双击空白区域快速新建临时 Workspace

### AI Agent 监控

对 AI 编程 Agent 会话的原生可视化支持：

- **启动面板** — 一键启动 Claude Code、Gemini CLI、OpenCode 及自定义命令
- **会话监控** — 通过内置 HTTP Hook Server 接收 Claude Code hook 事件，实时展示 Agent 工作状态
- **Subagent 跟踪** — 可视化 Agent 调用树，实时追踪 Subagent 的启动与完成
- **外部会话发现** — 自动发现并展示系统中正在运行的 Claude Code（`.jsonl`）、OpenCode（SQLite）和 Gemini 会话
- **侧边栏集成** — 专属侧边栏按钮快速访问监控面板

### 文件浏览器

直接集成在终端内的轻量文件树面板：

- **树形视图** — 浏览 Workspace 根目录下的文件结构，单击展开/折叠目录
- **多选操作** — `Cmd+A` 全选、`Shift+Click` 范围选择，支持批量删除和移动
- **拖拽** — 多文件拖拽，支持跨目录移动
- **实时过滤** — 顶部搜索框即时过滤文件名
- **文件预览** — 点击文件在右侧预览内容，支持 `.zig`、常见文本及代码格式
- **Git 状态徽标** — 文件旁实时展示 git 变更状态（`M`/`A`/`?` 等）
- **键盘导航** — 方向键浏览文件树，`Enter` 展开目录，`Space` 将路径注入当前终端
- **右键菜单** — 在 Finder 中显示、复制路径、内联重命名
- **快捷键** — `Cmd+\` 切换显示/隐藏

### tmux 深度集成

将 tmux 会话管理直接呈现于终端 UI：

- **会话面板** — 以 Tab 形式 attach tmux 会话，在专属面板中管理窗口
- **窗口栏** — 展示所有 tmux 窗口，支持切换、新建和关闭（带确认）
- **快速 Attach/Detach** — 一键操作，无需手动输入命令

### 底部状态栏

始终可见的上下文信息：

- **Git 状态** — 实时展示当前 Workspace 根目录的分支名称和变更数量
- **内联渲染** — 与 shell 区域对齐，显示在终端内容区域下方

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
- [Zig](https://ziglang.org/)（所需版本见 [build-rules.md](docs/build-rules.md)）

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

详细构建说明见 [docs/build-rules.md](docs/build-rules.md)。

---

## 贡献

Poltertty 采用分支保护工作流：

1. 所有特性开发必须在 `.worktrees/` 下的 git worktree 中进行
2. 变更通过 Pull Request 合并到 `main`，禁止直接推送

完整贡献流程见 [docs/development-rules.md](docs/development-rules.md)。

---

## 许可证

Poltertty 继承 Ghostty 的 [MIT 许可证](LICENSE)。本项目新增代码同样采用 MIT 许可证。
