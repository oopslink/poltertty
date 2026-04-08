# Poltertty

Ghostty 终端模拟器的 fork，添加 Workspace 管理功能。macOS only，Swift/SwiftUI，跟踪上游。

```bash
# 初始化本地 Git Hooks（新克隆仓库后执行一次）
make init-git-hooks
```

## 规则

- **语言**: 所有回复必须使用中文，**严禁使用韩文**，包括注释、说明、任何输出
- **构建和发布**: 必须遵循 [docs/rules/build-rules.md](docs/rules/build-rules.md) 规范
- **特性开发**: 必须遵循 [docs/rules/development-rules.md](docs/rules/development-rules.md) 规范
- **Workspace 开发**: 必须先阅读 [docs/rules/workspace-rules.md](docs/rules/workspace-rules.md)
- **Titlebar 定制**: 必须先阅读 [docs/rules/macos-titlebar-rules.md](docs/rules/macos-titlebar-rules.md)
- **UI/UX 设计**: 必须遵循 [docs/rules/ui-ux-rules.md](docs/rules/ui-ux-rules.md) 原则
- **Ctrl API 开发**: 必须遵循 [docs/rules/ctrl-api-rules.md](docs/rules/ctrl-api-rules.md) 规范
- **快捷键分配**: 新增快捷键前必须先查阅 [docs/rules/keybindings-map.md](docs/rules/keybindings-map.md)，避免与 Zig 层或 App 层冲突
