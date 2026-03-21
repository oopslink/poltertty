# Per-Pane Status Bar 设计

## 概述

将 status bar 从 window 级别（per-window）改为 pane 级别（per-pane），使每个 pane 拥有独立的状态展示和操作入口，实现全局感知。

## 动机

- 使用 split pane 时，不同 pane 可能在不同目录/项目下工作
- 需要同时看到所有 pane 的 pwd 和 git 状态，而非只看聚焦 pane
- 后续需要在 status bar 上放置 per-pane 的操作按钮（tmux、AI agent 等）

## 架构

Status bar 作为 SplitTree 每个 leaf node 的一部分，嵌入在 surface view 底部。每个 pane 拥有独立的 status bar 实例。

```
SplitTree leaf node:
┌─────────────────────────────────────────┐
│  Terminal Surface View                  │
│                                         │
├─────────────────────────────────────────┤
│ 📁 ~/project  main +2 ~1  │  🤖  ⚡  │  ← 22px status bar
└─────────────────────────────────────────┘
```

### 视图组合（伪代码）

```swift
// In TerminalSplitTreeView leaf 渲染:
VStack(spacing: 0) {
    Ghostty.InspectableSurface(...)
    if showStatusBar {
        PaneStatusBarView(surfaceView: surfaceView)
    }
}
```

## 布局

- **高度**：22px，保持紧凑
- **左侧**：pwd（折叠显示，`~` 缩写）+ git branch + status counts（added/modified）
- **右侧**：操作按钮（小图标，hover 显示 tooltip），预留 AI agent launch、tmux 等入口
- **右侧按钮区域**：设计为可扩展的 HStack，后续添加新按钮只需往里加 icon button

## 行为规则

1. **每个 pane 独立**：各自的 `GitStatusMonitor`，各自的 pwd 跟踪
2. **Zoom 模式保留**：pane 被 zoom 时依然显示 status bar，提供当前 pane 的上下文信息
3. **窄 pane 自适应**：pane 宽度不足时，优先截断 pwd 路径，按钮保留图标
4. **非 git 仓库**：不显示 git 信息部分，仅显示 pwd 和按钮
5. **临时 workspace**：临时 workspace 不显示 status bar，保持现有规则

## 数据流

### pwd 来源

`PaneStatusBarView` 直接观察所属 `SurfaceView` 的 `@Published var pwd: String?`，不使用 `@FocusedValue`。这样每个 pane 的 status bar 独立显示自己的 pwd，而非聚焦 pane 的 pwd。

### GitStatusMonitor 生命周期

- `PaneStatusBarView` 通过 `@StateObject` 持有自己的 `GitStatusMonitor`
- Monitor 的生命周期跟随 SwiftUI view 的生命周期，pane 关闭时自动 deinit 清理 dispatch source
- 同一 git repo 下的多个 pane 各自独立运行 `git status`（可接受，通常 2-4 个 pane）

## 主要改动

1. **新建 `PaneStatusBarView`**：替代现有的 `BottomStatusBarView`，per-pane 实例化
2. **每个 leaf node 持有独立的 `GitStatusMonitor`**：通过 `@StateObject` 在 view 内创建
3. **`TerminalSplitTreeView` 渲染 leaf 时**：在 surface view 底部附加 `PaneStatusBarView`
4. **移除 `PolterttyRootView` 底部的 `BottomStatusBarView`**：status bar 不再是 window 级组件
5. **清理 `PolterttyRootView` 中的 `onChange` pwd 监听**：不再需要 window 级 pwd 跟踪
6. **清理 `TerminalController` 中的 `statusMonitor` 属性和相关初始化代码**

## 涉及文件

### 新建

- `macos/Sources/Features/Workspace/PaneStatusBarView.swift` — per-pane status bar 视图

### 修改

- `macos/Sources/Features/Splits/TerminalSplitTreeView.swift` — leaf 渲染时附加 status bar
- `macos/Sources/Features/Workspace/PolterttyRootView.swift` — 移除底部 `BottomStatusBarView`、移除 `onChange` pwd 监听、移除 `statusMonitor` init 参数
- `macos/Sources/Features/Terminal/TerminalController.swift` — 移除 window 级 `GitStatusMonitor` 创建和传递

### 删除（或废弃）

- `macos/Sources/Features/Workspace/BottomStatusBarView.swift` — 被 `PaneStatusBarView` 替代

## 后续扩展

- 右侧按钮：AI agent launch、tmux session 管理等，逐步添加
- 初期只实现 pwd + git 信息展示，按钮功能后续独立迭代
- 性能优化：如果 pane 数量增多，可按 git root 共享 monitor
