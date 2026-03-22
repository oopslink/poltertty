# Tmux Attach Status Bar 按钮设计

## 概述

在 split pane 底部状态栏中添加 tmux attach 按钮，提供与菜单 "Attach tmux Session" 完全相同的功能，仅入口不同。

## 设计

### 按钮位置

状态栏右侧布局顺序：

```
路径 | Spacer | [tmux按钮] [agent按钮] | git状态
```

tmux 按钮位于 Agent 按钮左侧。

### 图标

使用 tmux 官方 16x16 icon（`https://github.com/tmux/tmux/blob/master/logo/icons/16x16/tmux.png`），存入 Xcode asset catalog `TmuxIcon.imageset`。

### 显示时机

- **默认显示**：始终渲染在状态栏中
- **已 attach 时隐藏**：当前 pane 的 `surfaceId` 在 `tabBarVM.tmuxStates` 中已存在时隐藏按钮（此时 TmuxWindowBar overlay 已提供操作入口）

### 点击行为

发送 `.showTmuxSessionPicker` 通知，`userInfo: ["attachInCurrentPane": true]`。

复用现有流程：
1. `PolterttyRootView` 收到通知 → 打开 `TmuxSessionPicker` sheet
2. 用户选择 session → 发送 `.tmuxAttachInCurrentPane` 通知
3. `TerminalController` 收到通知 → 设置 `tmuxStates`、注入 `tmux attach-session` 命令、启动 `tmuxMonitor`

### 改动文件

1. **`macos/Sources/Resources/Assets.xcassets/TmuxIcon.imageset/`** — 新增 icon 资源（1x: 16x16 png）
2. **`macos/Sources/Features/Workspace/BottomStatusBarView.swift`** — 添加 tmux 按钮，需要注入 `tabBarVM` 以读取 `tmuxStates`

### 按钮样式

- `.buttonStyle(.plain)`，与 AgentButtonView 一致
- 图标尺寸适配状态栏高度（22pt 栏高，icon 保持 12-14pt）
