# Poltertty

Poltertty 是 [Ghostty](https://ghostty.org) 终端模拟器的 macOS fork，在保留 Ghostty 全部核心能力的基础上，增加了 **Workspace 工作区管理**功能。

## 与 Ghostty 的关系

Poltertty 直接 fork 自 [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty)，并持续跟踪上游。

- **底层完全相同**：终端模拟、渲染（Metal）、字体（CoreText）、键绑定、配置系统均来自 Ghostty，无任何改动
- **仅扩展 macOS 层**：新功能全部以 Swift/SwiftUI 实现，位于 `macos/Sources/Features/Workspace/` 和相关集成点
- **配置兼容**：Ghostty 的所有配置项均可在 Poltertty 中使用，配置文件路径为 `~/.config/poltertty/config`

如需了解终端模拟相关的文档，请参阅 [Ghostty 官方文档](https://ghostty.org/docs)。

## 新增功能

### Workspace 工作区管理

以侧边栏为核心的多项目终端管理体验：

- **创建与管理**：为每个项目创建独立的 Workspace，设置名称、颜色、图标、根目录和描述
- **持久化**：Workspace 配置与窗口快照自动保存至 `~/.config/poltertty/workspaces/`，重启后自动恢复
- **临时 Workspace**：直接打开目录时创建临时 Workspace，退出后自动清理，不写入磁盘
- **快速切换**：通过 Quick Switcher（`Cmd+K`）在 Workspace 间快速跳转
- **侧边栏**：支持展开/折叠两种模式，展开态显示名称与描述，折叠态显示图标；右键菜单支持重命名、删除等操作

### 文件浏览器

内置轻量文件树面板，无需切换窗口即可浏览项目文件：

- **树形视图**：显示 Workspace 根目录下的文件结构，支持展开/折叠
- **文件过滤**：顶部搜索框实时过滤文件名
- **文件预览**：点击文件在右侧预览内容，支持 `.zig`、常见文本及代码格式
- **Git 状态徽标**：在文件旁展示 git 变更状态（`M`/`A`/`?` 等）
- **右键菜单**：支持在 Finder 中显示、复制路径、内联重命名等操作
- **键盘注入**：选中文件后可将路径直接注入到当前终端 session
- **快捷键**：`Cmd+\` 切换文件浏览器显示/隐藏

## 构建

```bash
# 开发构建并运行
make run-dev

# Release 构建
make release

# 查看所有命令
make help
```

详细构建说明见 [docs/build-rules.md](docs/build-rules.md)。
