# Poltertty

> Ghostty 终端模拟器的 macOS fork，专为 AI 辅助开发工作流设计

Poltertty 基于 [Ghostty](https://ghostty.org) 构建，在保留其全部核心终端能力的同时，增加了 **Workspace 工作区管理**、**文件浏览器**、**AI Agent 监控**和 **tmux 深度集成**等功能。

[English README](README.en.md)

---

## 特性

### Workspace 工作区管理

多项目终端管理的核心能力：

- **创建与管理**：为每个项目建立独立的 Workspace，自定义名称、颜色、图标、根目录和描述
- **分组**：将相关 Workspace 整理到分组中，保持侧边栏整洁有序
- **持久化**：配置与窗口快照自动保存至 `~/.config/poltertty/workspaces/`，重启后自动恢复
- **临时 Workspace**：直接打开目录时创建临时 Workspace，退出后自动清理，不写入磁盘
- **快速切换**：`Cmd+K` 打开 Quick Switcher，在 Workspace 间快速跳转
- **侧边栏**：支持展开/折叠，双击空白区域快速新建临时 Workspace；右键菜单支持重命名、删除（带二次确认）等操作

### 文件浏览器

内置轻量文件树面板，无需离开终端即可管理项目文件：

- **树形视图**：显示 Workspace 根目录下的文件结构，单击展开/折叠目录
- **多选操作**：`Cmd+A` 全选、`Shift+Click` 范围选择，支持批量删除和移动
- **拖拽**：多文件拖拽移动，支持跨目录操作
- **文件过滤**：顶部搜索框实时过滤文件名
- **文件预览**：点击文件在右侧预览内容，支持 `.zig`、常见文本及代码格式
- **Git 状态徽标**：在文件旁实时展示 git 变更状态（`M`/`A`/`?` 等）
- **键盘导航**：方向键浏览文件树，`Enter` 展开目录，`Space` 注入路径到当前终端
- **右键菜单**：在 Finder 中显示、复制路径、内联重命名等操作
- **快捷键**：`Cmd+\` 切换显示/隐藏

### AI Agent 监控

原生管理 AI 编程 Agent 会话，无需借助外部工具：

- **启动面板**：一键启动 Claude Code、Gemini CLI、OpenCode 等 Agent，支持自定义命令
- **会话监控**：实时监控 Agent 工作状态，通过内嵌 HTTP Hook Server 接收 Claude Code hook 事件
- **Subagent 跟踪**：可视化 Agent 调用树，实时跟踪 Subagent 启动与完成状态
- **外部会话发现**：自动发现并展示系统中正在运行的 Claude Code（`.jsonl`）、OpenCode（SQLite）、Gemini 会话
- **侧边栏入口**：侧边栏 Agent 按钮快速访问监控面板

### tmux 深度集成

将 tmux 会话管理直接带入终端 UI：

- **tmux 管理面板**：以 Tab 形式 attach tmux 会话，在专属面板中管理会话窗口
- **窗口栏**：展示 tmux 所有窗口，支持切换、新建和关闭窗口（带确认）
- **快速 Attach/Detach**：一键 attach 或 detach tmux session，无需手动输入命令

### 底部状态栏

终端底部的实时上下文信息：

- **Git 状态**：监控当前 Workspace 根目录的 git 变更，实时展示分支和修改数量
- **集成显示**：状态栏与 shell 区域对齐，显示在终端内容区域下方

---

## 与 Ghostty 的关系

Poltertty 直接 fork 自 [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty)，持续跟踪上游。

| 层面 | 说明 |
|------|------|
| **底层终端** | 终端模拟、渲染（Metal）、字体（CoreText）、键绑定、配置系统均来自 Ghostty，无任何改动 |
| **新功能** | 全部以 Swift/SwiftUI 实现，位于 `macos/Sources/Features/` 下的独立模块 |
| **配置兼容** | Ghostty 的所有配置项均可使用，配置文件路径为 `~/.config/poltertty/config` |

如需了解终端模拟相关文档，请参阅 [Ghostty 官方文档](https://ghostty.org/docs)。

---

## 构建

```bash
# 初始化本地 Git Hooks（新克隆仓库后执行一次）
make init-git-hooks

# 开发构建并运行
make run-dev

# Release 构建
make release

# 查看所有命令
make help
```

详细构建说明见 [docs/build-rules.md](docs/build-rules.md)。
