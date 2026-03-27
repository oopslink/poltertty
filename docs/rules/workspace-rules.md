# Workspace 功能开发规则

开发 Workspace 相关功能时必须遵守以下规则。

## 侧边栏一致性

侧边栏有**展开态**（`expandedContent`）和**折叠态**（`collapsedContent`）两种模式。任何功能变更必须同时覆盖两种模式：

- 右键菜单项必须在 `ExpandedWorkspaceItem` 和 `CollapsedWorkspaceIcon` 中同步添加
- 新增的回调参数必须同时传递给两种组件的所有调用点
- 视觉状态（active/inactive/hover）的变更必须在两种模式下保持语义一致

**检查清单**：每次修改侧边栏交互时，搜索 `ExpandedWorkspaceItem(` 和 `CollapsedWorkspaceIcon(` 确认所有调用点都已更新。

## 文件位置

所有 Workspace Swift 代码位于 `macos/Sources/Features/Workspace/`，集成点在：

- `macos/Sources/Features/Terminal/TerminalController.swift` — 窗口生命周期、PolterttyRootView 构建
- `macos/Sources/App/macOS/AppDelegate.swift` — 启动流程、菜单、退出清理

## 初始化时序

`TerminalController` 的属性（`workspaceId`、`startupMode`）必须通过 `init` 参数传入，不能在 `newWindow` 返回后设置。因为 `windowDidLoad` 在 `init` 期间触发，此时已创建 `PolterttyRootView`，事后设置的属性不会生效。

## 临时 Workspace

- 临时 Workspace 不持久化到磁盘（`save()` 和 `saveSnapshot()` 中有 guard）
- App 退出时 `destroyAllTemporary()` 必须在 snapshot 保存循环之前调用
- 创建临时 Workspace 使用随机颜色（从 `temporaryColors` 数组随机选取）
