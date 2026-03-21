# Status Bar Agent 按钮设计

## 概述

在 per-pane status bar 右侧（git 信息旁）添加一个 agent 启动按钮，支持在当前 pane 启动 AI agent。按钮根据当前 pane 是否有 agent session 运行，切换为选择菜单或状态指示器两种模式。

## 新增文件

```
Features/Workspace/AgentButton/
  ├── AgentButtonView.swift      // 按钮视图，根据 session 状态切换外观
  ├── AgentPickerPopover.swift   // 无 session 时的选择菜单
  └── AgentSessionPopover.swift  // 有 session 时的状态详情
```

## 修改文件

- `BottomStatusBarView.swift` — 右侧 HStack 添加 `AgentButtonView`
- `TerminalSplitTreeView.swift` — 向 `BottomStatusBarView` 传入 `surfaceId`

## 数据流

```
TerminalSplitLeafContainer
  └── BottomStatusBarView(surfaceId:)
        └── AgentButtonView(surfaceId:)
              ├── 观察 AgentSessionManager.sessions[surfaceId]
              ├── 无 session → AgentPickerPopover
              │     ├── 读取 AgentRegistry.allDefinitions
              │     ├── 用户选择 agent + 权限模式
              │     └── 调用 AgentLauncher.launch(location: .currentPane)
              └── 有 session → AgentSessionPopover（只读状态详情）
```

不新增 ViewModel，直接观察已有的 `AgentSessionManager`（`ObservableObject`）。

## 按钮外观

### 无 agent 状态

- 图标：`⬡`（空心六边形）
- 颜色：`secondary`，hover 时高亮为 `primary`
- 点击：弹出 `AgentPickerPopover`

### 有 agent 运行时

- 图标：替换为该 agent 的 `definition.icon`（如 Claude 的 `◆`）
- 颜色：`definition.iconColor`（如 `#CC785C`）
- 状态动画：
  - `.working` — 图标缓慢闪烁（脉冲动画）
  - `.idle` — 稳定常亮
  - `.done` — 变灰
- 点击：弹出 `AgentSessionPopover`

## AgentPickerPopover 布局

```
┌──────────────────────┐
│ Claude Code      ◆   │  ← agent 列表，点击选中高亮
│ Gemini CLI       ✦   │
│ OpenCode         ⬡   │
├──────────────────────┤
│ Permission  [Auto ▾] │  ← Picker 下拉框选择权限模式
│                      │
│      [Launch]        │  ← 确认启动按钮
└──────────────────────┘
```

- Agent 列表来自 `AgentRegistry.allDefinitions`（内置 + 自定义）
- 权限模式使用 SwiftUI `Picker` 下拉框，选项来自 `ClaudePermissionMode.allCases`
- 默认选中第一个 agent，权限模式默认 `auto`
- 点击 Launch 按钮调用 `AgentLauncher.launch(definition:location:.currentPane, permissionMode:workspaceId:cwd:)`

## AgentSessionPopover 布局

```
┌──────────────────────┐
│ ◆ Claude Code        │  ← agent 图标 + 名称
│ Status: Working      │  ← AgentState 显示
│ Started: 2m ago      │  ← 相对时间
│ Tokens: 12.3k       │  ← token 用量
└──────────────────────┘
```

只读信息展示，无操作按钮。

## 与现有代码的集成

### AgentLauncher 复用

启动流程完全复用现有 `AgentLauncher.launch()` 方法，`location` 固定为 `.currentPane`。AgentLauncher 已实现：
- 获取 `tc.focusedSurface` 作为目标 pane
- 创建 `AgentSession` 并注册到 `sessionManager`
- 注入 hooks（`.full` capability）
- 构建启动命令并通过 `surfaceModel.sendText()` 写入 PTY

### AgentSessionManager 观察

`AgentButtonView` 通过 `@ObservedObject` 观察 `AgentService.shared.sessionManager`，以 `surfaceId` 为 key 查询当前 pane 的 session 状态，驱动按钮外观切换。

### BottomStatusBarView 改动

在现有右侧 HStack 中，git 信息之后添加 `AgentButtonView(surfaceId: surfaceId)`。需要从 `TerminalSplitLeafContainer` 向 `BottomStatusBarView` 传入 `surfaceView.id`。

## 约束

- 按钮尺寸需适配 status bar 22px 高度
- 图标字体大小与现有 status bar 保持一致（11pt）
- Popover 宽度约 200pt，不超过 pane 宽度
