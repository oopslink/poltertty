# Workspace 功能开发规则

开发 Workspace 相关功能时必须遵守以下规则。

## NotificationCenter 窗口定向规则

**多窗口场景下，面向特定窗口的通知必须通过 `object` 参数传递目标窗口，接收方必须过滤。**

### 发送方（AppDelegate / CtrlToolHandler / AppCommandRegistry 等）

```swift
// ✅ 正确：传入目标窗口
let targetWindow = NSApp.keyWindow?.parent ?? NSApp.keyWindow
NotificationCenter.default.post(name: .toggleFileBrowser, object: targetWindow)

// ❌ 错误：object: nil 会让所有窗口同时响应
NotificationCenter.default.post(name: .toggleFileBrowser, object: nil)
```

- `AppDelegate` 菜单 action：使用 `NSApp.keyWindow?.parent ?? NSApp.keyWindow`
- `AppCommandRegistry` 闭包：使用 `NSApp.keyWindow ?? NSApp.mainWindow`
- `CtrlToolHandler`（已知 workspaceId）：使用 `WorkspaceManager.shared.windowForWorkspace(workspaceId)`
- 全局广播（不针对窗口，如 Agent Monitor）：允许 `object: nil`，但接收方不能做窗口过滤

### 接收方（PolterttyRootView 等每个窗口实例）

```swift
// ✅ 正确：过滤非本窗口的通知
.onReceive(NotificationCenter.default.publisher(for: .toggleFileBrowser)) { notification in
    guard notification.object as? NSWindow == windowProvider() else { return }
    handleToggleLeftPanel(for: .yazi)
}

// ❌ 错误：忽略 notification 参数，所有窗口都响应
.onReceive(NotificationCenter.default.publisher(for: .toggleFileBrowser)) { _ in
    handleToggleLeftPanel(for: .yazi)
}
```

### 检查清单

新增或修改窗口定向通知时：
1. 搜索所有 `NotificationCenter.default.post(name: .xxx` 调用点，确认每处都传了正确的 `object`
2. 搜索对应的 `.onReceive` 监听，确认有 `guard notification.object as? NSWindow == windowProvider()` 过滤
3. 参考已有正确实现：`toggleGitPanel`、`toggleWorkspaceSidebar`

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

## 快捷键规范

Workspace 功能菜单项的快捷键统一使用 `Option+Cmd` 前缀：

| 功能 | 快捷键 |
|------|--------|
| Toggle Sidebar | ⌥⌘P |
| Toggle File Browser | ⌥⌘F |
| Toggle Git Tab | ⌥⌘G |

**新增功能快捷键必须使用 `[.command, .option]` 修饰符**，避免与 Ghostty 原生 `⌘` / `⌘⇧` 快捷键冲突。
