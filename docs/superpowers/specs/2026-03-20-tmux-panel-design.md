# Poltertty tmux 管理面板设计文档

**日期**: 2026-03-20
**状态**: 草稿 v1

---

## 概述

为 Poltertty 新增一个独立的 **tmux 管理面板**，与现有文件树面板并排，风格一致。面板通过执行 `tmux` CLI 命令（轮询 + 操作后即时刷新）展示系统中所有 tmux sessions/windows/panes 的树形结构，支持完整的管理操作。

**不涉及**：
- tmux control mode（`-CC`）
- Zig bridge 或上游代码修改
- Workspace 联动（面板完全独立）
- pane 内容渲染

---

## 目标

- 在侧边栏提供树形视图浏览所有 tmux sessions → windows → panes
- 支持完整的 session/window/pane 管理操作（新建、重命名、关闭、分屏、send-keys 等）
- 双击 window 跳转到对应 tmux session
- 定时轮询（2s）+ 操作后即时刷新保持状态同步

## 非目标

- 不渲染 pane 内容
- 不与 Workspace 数据模型耦合
- 不使用 tmux control mode
- 不修改任何上游 Zig 文件

---

## 数据模型

```swift
struct TmuxSession: Identifiable {
    let id: String        // session name
    var windows: [TmuxWindow]
    var attached: Bool
}

struct TmuxWindow: Identifiable {
    let id: Int           // window index
    var name: String
    var panes: [TmuxPane]
    var active: Bool
}

struct TmuxPane: Identifiable {
    let id: Int           // pane id (%N)
    var title: String
    var active: Bool
    var width: Int
    var height: Int
}
```

---

## 数据获取

所有数据通过执行 `tmux` CLI 子命令获取，使用 `-F` 格式化输出：

```
tmux list-sessions -F "#{session_name}|#{session_attached}"
tmux list-windows  -t <session> -F "#{window_index}|#{window_name}|#{window_active}"
tmux list-panes    -t <session> -F "#{pane_id}|#{pane_title}|#{pane_active}|#{pane_width}|#{pane_height}"
```

`TmuxCommandRunner` 用 `async/await` 封装 `Process` 执行，避免阻塞主线程。`TmuxParser` 为纯函数，接收字符串返回数据模型。

### 刷新机制

`TmuxPanelViewModel` 持有一个 2 秒 Timer（在后台调度，结果在主线程更新 UI）：

- **定时轮询**：每 2 秒自动刷新一次
- **操作后即时刷新**：每次用户操作执行后立即触发额外一次刷新
- **空状态处理**：tmux 未安装时显示"tmux 未安装"提示；无 session 时显示"无活跃 session"提示

---

## UI 结构

### 面板布局

```
┌─────────────────────────┐
│ [🖥] tmux               │  ← 标题栏 + 刷新按钮 + 新建 session 按钮
├─────────────────────────┤
│ ▼ my-project  ● attached│  ← session（可展开/折叠）
│   ▼ 1: vim              │  ← window（active 高亮）
│     % 1  nvim           │  ← pane
│     % 2  zsh            │
│   ▷ 2: server           │
│   ▷ 3: logs             │
│                         │
│ ▷ dotfiles              │  ← 另一个 session（折叠）
└─────────────────────────┘
```

- **Session 行**：attached 状态徽标，右键菜单（attach、重命名、kill）
- **Window 行**：active 标记，右键菜单（跳转、重命名、kill）
- **Pane 行**：active 标记，右键菜单（select、send-keys、kill）
- **双击 window**：在当前终端执行 `tmux switch-client -t <session>:<window>`

---

## 操作清单

| 层级 | 操作 | tmux 命令 |
|------|------|-----------|
| 全局 | 新建 session | `tmux new-session -d -s <name>` |
| Session | attach | `tmux switch-client -t <session>` |
| Session | 重命名 | `tmux rename-session -t <old> <new>` |
| Session | kill | `tmux kill-session -t <name>` |
| Window | 跳转 | `tmux switch-client -t <session>:<index>` |
| Window | 新建 | `tmux new-window -t <session>` |
| Window | 重命名 | `tmux rename-window -t <session>:<index> <name>` |
| Window | kill | `tmux kill-window -t <session>:<index>` |
| Window | 移动 | `tmux move-window -s <src> -t <dst>` |
| Pane | select | `tmux select-pane -t %<id>` |
| Pane | 水平分屏 | `tmux split-window -h -t %<id>` |
| Pane | 垂直分屏 | `tmux split-window -v -t %<id>` |
| Pane | send-keys | `tmux send-keys -t %<id> "<cmd>" Enter` |
| Pane | kill | `tmux kill-pane -t %<id>` |

---

## 文件结构

### 新增文件

```
macos/Sources/Features/Tmux/
  TmuxModels.swift             ← TmuxSession / TmuxWindow / TmuxPane 结构体
  TmuxCommandRunner.swift      ← 封装 Process 执行 tmux 命令（async/await）
  TmuxParser.swift             ← 解析 -F 格式化输出 → 数据模型（纯函数）
  TmuxPanelViewModel.swift     ← @MainActor ObservableObject，Timer + 数据管理
  TmuxPanelView.swift          ← 面板根视图，树形列表
  TmuxSessionRow.swift         ← Session 行视图 + 右键菜单
  TmuxWindowRow.swift          ← Window 行视图 + 右键菜单
  TmuxPaneRow.swift            ← Pane 行视图 + 右键菜单
```

### 修改文件（仅追加，不改现有逻辑）

```
macos/Sources/Features/Workspace/
  PanelTabView.swift（或同等面板切换文件）  ← 增加 tmux 面板 tab icon
```

### 测试文件

```
macos/Tests/Tmux/
  TmuxParserTests.swift        ← 解析逻辑单元测试（纯函数，无副作用）
```

---

## 上游跟踪策略

| 文件 | 策略 | 冲突风险 |
|------|------|---------|
| `src/terminal/tmux/*.zig` | 完全不动 | 零 |
| `include/ghostty.h` | 不修改 | 零 |
| `macos/Sources/Features/Tmux/` | 全新目录，纯新增 | 零 |
| 面板切换文件 | 仅追加 tab icon 条目 | 低 |

---

## 实现阶段

1. **阶段一（数据层）**：`TmuxModels` + `TmuxCommandRunner` + `TmuxParser` + 单元测试
2. **阶段二（面板 UI）**：`TmuxPanelViewModel` + `TmuxPanelView` + 三个 Row 视图 + 空状态
3. **阶段三（面板接入）**：将面板 tab 接入现有侧边栏切换机制
