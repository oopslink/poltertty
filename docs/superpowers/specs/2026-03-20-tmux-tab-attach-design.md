# Tmux Tab Attach 设计文档

> **目标**：通过 File 菜单快速创建 attach 到 tmux session 的 tab，提供原生 window 切换 UI 和 detach 操作，逐步替代现有 tmux 侧边栏面板。

## 1. 数据模型

### TmuxAttachState（新增，TmuxModels.swift）

```swift
struct TmuxAttachState: Equatable {
    let sessionName: String
    var activeWindowIndex: Int
    var activeWindowName: String
    var windows: [WindowInfo]

    /// 轻量 window 信息，仅用于 overlay 显示。
    /// 不复用 TmuxWindow 是因为后者包含 panes 数组和 sessionName 冗余字段，
    /// 且 TmuxWindow 的 id 是 "sessionName:windowIndex" 复合格式，
    /// 而 WindowInfo 只需 index 作为 id。
    struct WindowInfo: Equatable, Identifiable {
        let index: Int
        let name: String
        let active: Bool
        var id: Int { index }
    }
}
```

### TabItem 扩展（TabBarViewModel.swift）

`TabItem`（顶层结构体，定义在 TabBarViewModel.swift 中）新增属性：

```swift
var tmuxState: TmuxAttachState?  // nil = 普通 tab
```

## 2. File 菜单 + Session 选择对话框

### 菜单项

- **位置**：MainMenu.xib 的 File 菜单中，`New Tab` 之后
- **标题**：`New Tab with tmux Session...`
- **快捷键**：`Cmd+Option+T`（`Cmd+Shift+T` 已被 New Temporary Workspace 占用）
- **AppDelegate outlet**：`menuNewTabTmux`
- **Action**：`newTabWithTmuxSession(_:)`

### Action 流程

```
AppDelegate.newTabWithTmuxSession(_:)
  → 获取 keyWindow 的 TerminalController
  → post .showTmuxSessionPicker 通知
  → PolterttyRootView 接收通知，显示 TmuxSessionPicker sheet
```

### TmuxSessionPicker（新文件）

SwiftUI Sheet 对话框，包含：

- **RadioButton 切换**：Attach to existing / Create new
- **Existing session list**：`List` 单选，显示 session name + attached 状态绿点
  - 数据来源：复用 `TmuxCommandRunner` + `TmuxParser.parseSessions()`（与 TmuxPanelViewModel 使用相同的解析逻辑，避免重复）
- **New session**：TextField 输入 session name（可空，tmux 自动命名）
- **按钮**：Cancel / Open

### TmuxSessionPickerViewModel（新文件）

```swift
@MainActor
final class TmuxSessionPickerViewModel: ObservableObject {
    enum Mode { case attachExisting, createNew }

    @Published var mode: Mode = .attachExisting
    @Published var sessions: [TmuxSession] = []  // 复用现有 TmuxSession 模型
    @Published var selectedSession: String? = nil
    @Published var newSessionName: String = ""
    @Published var isLoading: Bool = true

    /// 使用 TmuxCommandRunner + TmuxParser（与 TmuxPanelViewModel 共享解析逻辑）
    func loadSessions() async { ... }
    func canOpen() -> Bool { ... }
}
```

### Open 执行逻辑

1. 如果是新建：执行 `tmux new-session -d -s <name>`（name 为空时省略 `-s`，用 `TmuxCommandRunner.runSilent`）
2. 调用 `TerminalController.addNewTabWithTmux(sessionName:)`
   - 调用 `addNewTab()` 创建新 tab
   - 通过 `tabBarViewModel.activeTabId` 获取新创建 tab 的引用
   - 设置新 tab 的 `tmuxState`（初始值，windows 列表由 TmuxTabMonitor 首次轮询填充）
   - 使用 `Ghostty.Shell.escape(sessionName)` 转义 session name
   - 向新 tab 的 surface 注入 `tmux attach-session -t <escapedName>\n`
   - 注意：新 tab 的 shell 可能尚未就绪，使用 `DispatchQueue.main.asyncAfter(deadline: .now() + 0.3)` 延迟注入
   - 启动 `TmuxTabMonitor` 追踪

## 3. TmuxWindowBar（Window 切换 Overlay）

### 位置与显示条件

- 仅当当前 active tab 的 `tmuxState != nil` 时显示
- 悬浮在终端 pane 右上角，ZStack overlay
- 集成在 `terminalAreaView` 的 `terminalView` 上

### 布局

```
┌──────────────────────────────────────────────────┐
│                                 1:zsh [2:vim] 3:top ··· ⏏ │
│                                                            │
│                      Terminal Content                      │
│                                                            │
└──────────────────────────────────────────────────┘
```

### UI 规格

- **Window 标签**：药丸形，格式 `index:name`
  - Active window：高亮背景（accent color，半透明）
  - Inactive window：普通背景（`Material.ultraThin`）
- **最多显示 4 个**：超出显示 `···` 药丸，点击弹出完整 window 列表 Popover
  - Popover 内容：垂直排列所有 window，格式同药丸标签，点击切换并关闭 Popover
  - Popover preferredEdge: `.bottom`
- **Detach 按钮**：`⏏` 图标，右侧
- **透明度行为**：鼠标不在区域时 opacity 0.4，hover 时 opacity 1.0
  - 动画：`.easeInOut(duration: 0.2)`
- **尺寸**：标签高 22pt，字体 system 10pt

### 交互

- **点击 window 标签**：通过 `TmuxCommandRunner.runSilent(args: ["select-window", "-t", "\(session):\(index)"])` 切换 window（使用子进程而非文本注入，避免在 vim 等全屏应用内失效）
- **点击 `···`**：弹出 Popover 显示完整 window 列表
- **点击 `⏏`**：detach 操作
  - 通过 `TmuxCommandRunner.runSilent(args: ["detach-client", "-s", sessionName])` 执行 detach（使用子进程，不依赖终端状态）
  - 清除当前 tab 的 `tmuxState`
  - Overlay 消失，tab 回到普通 shell

### 新文件

`macos/Sources/Features/Tmux/TmuxWindowBar.swift`

## 4. 关闭 Tab 确认

### 拦截点

所有可能关闭 tmux tab 的路径都需拦截：

1. `closePolterttyTab(_:)` — 自定义 tab bar 的关闭按钮
2. `closeTab(_:)` — IBAction / Cmd+W 快捷键
3. `closeSurface(_:)` — surface tree 移除（root node 关闭时）
4. `windowShouldClose(_:)` — 窗口关闭按钮（此时需检查所有 tab）

实现方式：抽取统一的检查方法 `tmuxTabRequiresConfirmation(_ tabId: UUID) -> TmuxAttachState?`，在上述 4 个路径中调用。

### 对话框

当 `tmuxState != nil` 时弹出 NSAlert（sheet 模式）：

- **标题**：`Tmux Session "<sessionName>"`
- **内容**：`该 tab 已 attach 到 tmux session，你想要：`
- **按钮**：
  - `Detach`（默认）：通过 `TmuxCommandRunner.runSilent(args: ["detach-client", "-s", sessionName])` detach，然后关闭 tab
  - `Kill Session`（destructive）：通过 `TmuxCommandRunner.runSilent(args: ["kill-session", "-t", sessionName])` kill，然后关闭 tab
  - `取消`

### 实现

在 `TerminalController` 中新增方法：

```swift
private func closeTmuxTab(_ tabId: UUID, sessionName: String) {
    // 显示 NSAlert sheet，根据用户选择执行对应操作
}
```

## 5. TmuxTabMonitor（状态轮询）

### 职责

追踪所有 tmux tab 的 window 列表状态，驱动 TmuxWindowBar 更新。

### 轮询策略

- **频率**：每 2 秒（与现有 tmux 面板一致）
- **启动条件**：存在任何 `tmuxState != nil` 的 tab
- **停止条件**：所有 tmux tab 关闭或 detach
- **查询命令**：对每个 tmux tab 执行 `tmux list-windows -t <session> -F "#{window_index}|#{window_name}|#{window_active}"`
- **解析**：复用 `TmuxParser.parseWindows()`，然后映射为 `TmuxAttachState.WindowInfo`

### 与 TmuxPanelViewModel 的关系

两者独立轮询，互不干扰。原因：
- TmuxPanelViewModel 轮询所有 session + window + pane 的完整树，数据量大
- TmuxTabMonitor 仅轮询已 attach tab 对应 session 的 window 列表，查询轻量
- TmuxPanelViewModel 将在 Phase 2 废弃，不值得为短期共存做合并
- 两者同时活跃时，各自 2s 轮询对 tmux server 无压力

### 异常处理

- Session 不存在：自动清除该 tab 的 `tmuxState`
- tmux server 停止：清除所有 tab 的 `tmuxState`

### 生命周期

- 由 `TabBarViewModel` 持有
- `addNewTabWithTmux()` 时启动（如果尚未运行）
- 最后一个 tmux tab 消失时停止

### 新文件

`macos/Sources/Features/Tmux/TmuxTabMonitor.swift`

## 6. 文件结构

### 新增文件（4 个）

```
macos/Sources/Features/Tmux/
    TmuxSessionPicker.swift          — Session 选择对话框 UI
    TmuxSessionPickerViewModel.swift — 对话框状态管理
    TmuxWindowBar.swift              — 右上角 window 切换 overlay
    TmuxTabMonitor.swift             — tmux tab 状态轮询
```

### 修改文件（5 个）

```
macos/Sources/Features/Tmux/TmuxModels.swift            — 新增 TmuxAttachState
macos/Sources/Features/Workspace/TabBar/TabBarViewModel.swift — TabItem 增加 tmuxState
macos/Sources/Features/Terminal/TerminalController.swift  — addNewTabWithTmux + 关闭拦截
macos/Sources/Features/Workspace/PolterttyRootView.swift  — overlay 集成 + sheet
macos/Sources/App/macOS/AppDelegate.swift                 — 菜单项 + action
```

### XIB 修改（1 个）

```
macos/Sources/App/macOS/MainMenu.xib — File 菜单新增 menuItem
```

## 7. 通知定义

在 `PolterttyRootView.swift` 的现有 `Notification.Name` 扩展中添加（与 `.toggleTmuxPanel` 等保持一致）：

```swift
static let showTmuxSessionPicker = Notification.Name("poltertty.showTmuxSessionPicker")
```

## 8. 已知限制

- **Undo 不支持**：tmux tab 的创建/关闭不支持 undo。这是合理的，因为 tmux session 独立于 Poltertty 生命周期，undo 语义不明确。
- **初始 attach 使用文本注入**：新 tab 创建时通过注入 `tmux attach-session` 命令 attach，依赖 shell 已就绪（通过 300ms 延迟缓解）。这是 Phase 1 的已知限制，Phase 3 的 control mode 将完全替代。

## 9. 上游冲突风险

| 文件 | 风险 | 说明 |
|------|------|------|
| `Tmux/` 目录新文件 | 零 | 全新文件 |
| `TmuxModels.swift` | 零 | 新增结构体，不改现有 |
| `TabBarViewModel.swift` | 低 | 仅 TabItem 加属性 |
| `TerminalController.swift` | 低 | 新增方法 + 小改 closePolterttyTab |
| `PolterttyRootView.swift` | 低 | overlay + onReceive |
| `AppDelegate.swift` | 低 | 新增 outlet + action |
| `MainMenu.xib` | 低 | 新增 menuItem |

## 10. 后续计划

- **Phase 2**：逐步废弃 tmux 侧边栏面板（TmuxPanelView 及相关文件）
- **Phase 3**：tmux control mode (-CC) 深度集成（已有独立设计文档）
