# Poltertty tmux 管理面板设计文档

**日期**: 2026-03-20
**状态**: 草稿 v4

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
- 支持完整的 session/window/pane 管理操作（新建、重命名、关闭、分屏等）
- 双击 window 跳转到对应 tmux window
- 定时轮询（2s）+ 操作后即时刷新保持状态同步

## 非目标

- 不渲染 pane 内容
- 不与 Workspace 数据模型耦合
- 不使用 tmux control mode
- 不修改任何上游 Zig 文件
- v1 不支持 send-keys（需要 UI 输入交互设计，留待后续迭代）
- v1 不支持 window 拖拽移动（`move-window`）

---

## 数据模型

```swift
// TmuxWindow.id 用复合 ID 确保跨 session 全局唯一（避免 SwiftUI identity 冲突）
struct TmuxSession: Identifiable {
    let id: String            // session name
    var windows: [TmuxWindow]
    var attached: Bool
}

struct TmuxWindow: Identifiable {
    let id: String            // 复合 ID："\(sessionName):\(windowIndex)"
    let sessionName: String
    let windowIndex: Int
    var name: String
    var panes: [TmuxPane]
    var active: Bool
}

// TmuxPane.id 存储解析后的纯数字（tmux 格式 "%N" → 去掉 % 前缀取整数）
struct TmuxPane: Identifiable {
    let id: Int               // pane_id 数字部分（tmux 原始格式 "%N"，解析时去掉 % 前缀）
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

**PATH 处理**：macOS 应用的 `Process()` 默认 PATH 不含 `/usr/local/bin`、`/opt/homebrew/bin` 等 Homebrew 路径。`TmuxCommandRunner` 构建 `Process.environment` 时，在默认 PATH 基础上追加 `/usr/local/bin:/opt/homebrew/bin:/opt/local/bin` 以覆盖常见 tmux 安装位置。

### 错误与状态

```swift
// 命令执行失败的具体原因
enum TmuxError {
    case notInstalled                     // tmux 不在 PATH 中（Process launch 失败）
    case serverNotRunning(stderr: String) // tmux 已安装但 server 未运行
    case timeout                          // 超过 3s 未返回，任务已取消
}

// ViewModel 完整状态机
enum TmuxPanelState {
    case loading                // 首次加载中
    case empty                  // 正常运行但无 session
    case loaded([TmuxSession])
    case error(TmuxError)
}
```

超时后定时 Timer 继续运行，下一个 2s 轮询周期自动重试。

### 刷新机制

`TmuxPanelViewModel` 为 **per-window 实例**（与 `agentMonitorVM` 模式一致，在 `PolterttyRootView.init()` 中直接初始化），各窗口独立轮询同一 tmux server：

- **定时轮询**：每 2 秒自动刷新一次
- **操作后即时刷新**：每次用户操作执行后立即触发额外一次刷新
- **并发控制**：用 `Task` + `Task.cancel()` 确保同一时间只有一个刷新任务在运行
- **生命周期**：面板隐藏时调用 `pause()` 暂停 Timer，显示时调用 `resume()` 恢复，与 `FileBrowserViewModel` 的 `pause()`/`resume()`/`stop()` 模式一致

---

## UI 结构

### 面板布局

```
┌─────────────────────────┐
│ tmux               ↺  + │  ← 标题栏 + 刷新按钮 + 新建 session 按钮
├─────────────────────────┤
│ ▼ my-project  ● attached│  ← session（可展开/折叠）
│   ▼ 1: vim              │  ← window（active 高亮）
│     %1  nvim            │  ← pane
│     %2  zsh             │
│   ▷ 2: server           │
│   ▷ 3: logs             │
│                         │
│ ▷ dotfiles              │  ← 另一个 session（折叠）
└─────────────────────────┘
```

- **Session 行**：attached 状态徽标，右键菜单（attach、重命名、kill）
- **Window 行**：active 标记，右键菜单（跳转、重命名、kill）
- **Pane 行**：active 标记，右键菜单（select、kill）
- **双击 window**：执行 `tmux switch-client -t <session>:<index>`；若命令失败（无 attached client），面板顶部显示短暂 banner："无 tmux client，请在终端运行 `tmux attach-session -t <session>`"，不尝试向 surface 注入命令

---

## 操作清单

| 层级 | 操作 | tmux 命令 |
|------|------|-----------|
| 全局 | 新建 session | `tmux new-session -d -s <name>` |
| Session | attach | `tmux switch-client -t <session>`（失败时显示 banner） |
| Session | 重命名 | `tmux rename-session -t <old> <new>` |
| Session | kill | `tmux kill-session -t <name>` |
| Window | 跳转 | `tmux switch-client -t <session>:<index>`（失败时显示 banner） |
| Window | 新建 | `tmux new-window -t <session>` |
| Window | 重命名 | `tmux rename-window -t <session>:<index> <name>` |
| Window | kill | `tmux kill-window -t <session>:<index>` |
| Pane | select | `tmux select-pane -t %<id>` |
| Pane | 水平分屏 | `tmux split-window -h -t %<id>` |
| Pane | 垂直分屏 | `tmux split-window -v -t %<id>` |
| Pane | kill | `tmux kill-pane -t %<id>` |

---

## PolterttyRootView 集成

tmux 面板插入在文件树面板之后、terminal area 之前，两者可同时显示（不互斥）。布局结构如下：

```
HStack {
  // 1. 左侧固定宽度 sidebar（icon 按钮）
  SidebarView()
  Divider()

  // 2. 文件树面板（若可见）
  if fileBrowserVM.isVisible && !fileBrowserVM.isPreviewFullscreen {
    FileBrowserPanel(...)
      .frame(maxWidth: fileBrowserVM.panelWidth)
    Divider()  // draggable fileBrowserDivider
  }

  // 3. tmux 面板（若可见）—— 新增
  if tmuxPanelVM.isVisible {
    TmuxPanelView(viewModel: tmuxPanelVM)
      .frame(width: tmuxPanelVM.panelWidth)  // 默认 240pt，可拖拽调整
    tmuxDivider  // 与 fileBrowserDivider 同风格的可拖拽分割线
  }

  // 4. terminal 区域（始终存在，除非 fileBrowser 全屏）
  terminalAreaView

  // 5. Agent Monitor（右侧）
  if agentMonitorVM.isVisible { ... }
}
```

`TmuxPanelViewModel` 在 `PolterttyRootView.init()` 中直接初始化：

```swift
self._tmuxPanelVM = ObservedObject(wrappedValue: TmuxPanelViewModel())
```

（不依赖 WorkspaceManager，不共享单例——各窗口独立实例，各自轮询 tmux server）

---

## 文件结构

### 新增文件

```
macos/Sources/Features/Tmux/
  TmuxModels.swift             ← TmuxSession / TmuxWindow / TmuxPane / TmuxError / TmuxPanelState
  TmuxCommandRunner.swift      ← 封装 Process 执行 tmux 命令（async/await + Task 取消 + PATH 扩展）
  TmuxParser.swift             ← 解析 -F 格式化输出 → 数据模型（纯函数）
  TmuxPanelViewModel.swift     ← @MainActor ObservableObject，per-window 实例，Timer + 状态管理
  TmuxPanelView.swift          ← 面板根视图，树形列表 + 错误/空状态视图 + banner
  TmuxSessionRow.swift         ← Session 行视图 + 右键菜单
  TmuxWindowRow.swift          ← Window 行视图 + 右键菜单
  TmuxPaneRow.swift            ← Pane 行视图 + 右键菜单
```

测试文件（与 `macos/Tests/Splits/`、`macos/Tests/Workspace/` 同级）：

```
macos/Tests/Tmux/
  TmuxParserTests.swift        ← 解析逻辑单元测试（纯函数，无副作用，优先实现）
```

v1 仅测试 `TmuxParser`（纯函数，最高性价比）。`TmuxCommandRunner` 涉及 `Process` 副作用，留待后续迭代补充 mock 测试。

### 修改文件

| 文件 | 变更 |
|------|------|
| `macos/Sources/Features/Workspace/PolterttyRootView.swift` | 新增 `@ObservedObject private var tmuxPanelVM: TmuxPanelViewModel`，在 HStack 中 fileBrowserDivider 和 terminalAreaView 之间插入 tmux 面板分支及可拖拽 divider |
| `macos/Ghostty.xcodeproj/project.pbxproj` | 将 `macos/Sources/Features/Tmux/` 下所有新文件及 `macos/Tests/Tmux/TmuxParserTests.swift` 注册到对应 Xcode target |

---

## 上游跟踪策略

| 文件 | 策略 | 冲突风险 |
|------|------|---------|
| `src/terminal/tmux/*.zig` | 完全不动 | 零 |
| `include/ghostty.h` | 不修改 | 零 |
| `macos/Sources/Features/Tmux/` | 全新目录，纯新增 | 零 |
| `PolterttyRootView.swift` | 插入新分支，不修改现有逻辑 | 低 |

---

## 实现阶段

1. **阶段一（数据层）**：`TmuxModels` + `TmuxCommandRunner`（含错误状态、Task 取消、PATH 扩展）+ `TmuxParser` + `TmuxParserTests`
2. **阶段二（面板 UI）**：`TmuxPanelViewModel`（Timer、pause/resume、TmuxPanelState）+ `TmuxPanelView` + 三个 Row 视图 + 错误/空状态视图 + banner
3. **阶段三（面板接入）**：修改 `PolterttyRootView.swift` 接入侧边栏 + Xcode project 注册新文件
