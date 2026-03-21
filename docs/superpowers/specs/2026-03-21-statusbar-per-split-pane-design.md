# Status Bar 从窗口级改为 Split Pane 级设计文档

**日期:** 2026-03-21
**状态:** 草稿 v2（审查修订）

---

## 概述

将 `BottomStatusBarView` 从窗口级（所有 split pane 共享一个 status bar）改为 split pane 级（每个 pane 底部独立一个 status bar）。焦点 pane 的 status bar 不透明，非焦点 pane 半透明（opacity 0.45）。

---

## 目标

- 每个 split pane 底部显示独立的 status bar，显示该 pane 自己的 pwd / git 状态
- 焦点 pane status bar 不透明（opacity 1.0），非焦点 pane 半透明（opacity 0.45）
- 单 pane 时行为与现有一致（仅一个不透明 status bar）
- 不改动任何上游 Ghostty 文件

## 非目标

- 不改变 status bar 的内容（仍显示 pwd + git 分支/脏状态）
- 不支持 per-pane 独立隐藏/折叠
- 不修改 `GitStatusMonitor` 或 `BottomStatusBarView` 的核心逻辑

---

## 视觉设计

```
┌──────────────────────┬──────────────────────┐
│  terminal pane A     │  terminal pane B     │
│  (focused)           │                      │
│                      │                      │
│──────────────────────│──────────────────────│
│ ~/proj/a  ⎇ main +1  │ ~/proj/b  ⎇ dev      │ ← pane A 不透明, pane B 半透明
└──────────────────────┴──────────────────────┘
```

- 每个 pane 底部各一个 22px status bar
- 焦点 pane：`opacity(1.0)`
- 非焦点 pane：`opacity(0.45)`
- 布局通过 `.safeAreaInset(edge: .bottom, spacing: 0)` 挂在每个 `TerminalSplitLeaf` 底部

---

## 架构

```
TerminalSplitSubtreeView
  └── .leaf case → TerminalSplitLeafContainer  ← 新增包装层
                    ├── @StateObject statusMonitor: GitStatusMonitor
                    ├── @Environment(\.showStatusBar) showStatusBar
                    ├── @FocusedValue(\.ghosttySurfaceView) focusedSurface
                    ├── TerminalSplitLeaf（现有逻辑不变）
                    └── .safeAreaInset(edge: .bottom) {
                          BottomStatusBarView(monitor, pwd, isFocused)
                        }
```

**数据流：**

1. `surfaceView.$pwd`（`@Published`）→ `.onReceive` → `statusMonitor.updatePwd()`
2. `@FocusedValue(\.ghosttySurfaceView)` 与 `surfaceView` 引用比较 → `isFocused`
3. `@Environment(\.showStatusBar)` 从 `PolterttyRootView` 传入，控制是否渲染 status bar

---

## 组件详细设计

### 新增：`TerminalSplitLeafContainer`

位置：`macos/Sources/Features/Splits/TerminalSplitTreeView.swift`（`private struct`）

```swift
private struct TerminalSplitLeafContainer: View {
    let surfaceView: Ghostty.SurfaceView
    let isSplit: Bool
    let action: (TerminalSplitOperation) -> Void

    @StateObject private var statusMonitor = GitStatusMonitor(pwd: "")
    @Environment(\.showStatusBar) private var showStatusBar
    @FocusedValue(\.ghosttySurfaceView) private var focusedSurface

    private var isFocused: Bool {
        // focusedSurface 为 nil 时（窗口失焦），默认视为 focused，避免所有 pane 同时变半透明
        guard let focused = focusedSurface else { return true }
        return focused === surfaceView
    }

    var body: some View {
        TerminalSplitLeaf(surfaceView: surfaceView, isSplit: isSplit, action: action)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showStatusBar {
                    BottomStatusBarView(
                        monitor: statusMonitor,
                        pwd: surfaceView.pwd ?? "",
                        isFocused: isFocused
                    )
                }
            }
            .onReceive(surfaceView.$pwd.compactMap { $0 }.removeDuplicates()) { pwd in
                statusMonitor.updatePwd(pwd)
            }
    }
}
```

### 新增：`ShowStatusBarKey`（EnvironmentKey）

位置：`macos/Sources/Features/Splits/TerminalSplitTreeView.swift`（文件末尾追加，与消费方同文件）

```swift
private struct ShowStatusBarKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var showStatusBar: Bool {
        get { self[ShowStatusBarKey.self] }
        set { self[ShowStatusBarKey.self] = newValue }
    }
}
```

### 修改：`BottomStatusBarView`

新增 `isFocused: Bool` 参数，在最外层 `VStack` 上应用 opacity：

```swift
struct BottomStatusBarView: View {
    @ObservedObject var monitor: GitStatusMonitor
    let pwd: String
    let isFocused: Bool          // 新增

    var body: some View {
        let status = monitor.status
        VStack(spacing: 0) {
            // ... 现有内容不变 ...
        }
        .font(.system(size: 11))
        .opacity(isFocused ? 1.0 : 0.45)   // 新增
    }
}
```

---

## 集成点变更

### `TerminalSplitTreeView.swift`

`TerminalSplitSubtreeView` 的 `.leaf` case：

```swift
// 改前：
case .leaf(let leafView):
    TerminalSplitLeaf(surfaceView: leafView, isSplit: !isRoot, action: action)

// 改后：
case .leaf(let leafView):
    TerminalSplitLeafContainer(surfaceView: leafView, isSplit: !isRoot, action: action)
```

### `PolterttyRootView.swift`

**删除：**
- `let statusMonitor: GitStatusMonitor` 属性
- `let showStatusBar: Bool` 属性
- `init` 中对应参数
- `terminalAreaView` 中的 `BottomStatusBarView` 渲染块
- `.onChange(of: focusedPwd)` **整块**（包含 guard 和 `updatePwd` 调用，整体删除）
- `@FocusedValue(\.ghosttySurfacePwd) private var focusedPwd` 声明（删除 status bar 块后不再有引用）

**新增：**
- `.terminal` case 的 `HStack` 上追加 `.environment(\.showStatusBar, showStatusBar)`（`showStatusBar` 由 `TerminalController` 通过新方式传入，见下）

实际上 `showStatusBar` 逻辑（临时 workspace 判断）仍需要，可通过以下两种方式保留：
- 方式 1：`PolterttyRootView` 保留 `showStatusBar` 参数，但去掉 `statusMonitor`
- 方式 2：`PolterttyRootView` 内部自行计算（通过 `workspaceId` 查 `WorkspaceManager`）

**推荐方式 2**：`PolterttyRootView` 已有 `workspaceId`，可自行计算：

```swift
private var showStatusBar: Bool {
    guard let id = workspaceId,
          let ws = WorkspaceManager.shared.workspace(for: id) else { return false }
    return !ws.isTemporary
}
```

完全移除外部传入，`PolterttyRootView.init` 删除 `statusMonitor` 和 `showStatusBar` 两个参数。

> **注：** `PolterttyRootView` 已通过 `@ObservedObject var manager = WorkspaceManager.shared` 订阅 `WorkspaceManager`。只要 `WorkspaceManager.convertToFormal` 正确触发 `objectWillChange`（现有实现已满足），临时 workspace 转正式时 `showStatusBar` 会自动重新计算，status bar 会正确显示。

### `TerminalController.swift`

**删除：**
- `let statusMonitor: GitStatusMonitor` 属性
- `init` 中 `statusMonitor` 的初始化逻辑：`rootDir` 计算变量（专为 monitor 而存在）+ `GitStatusMonitor(pwd:)` 调用，**两行一起删除**
- 传给 `PolterttyRootView` 的 `statusMonitor:` 和 `showStatusBar:` 参数

**验证：** 删除后在 `TerminalController.swift` 中搜索 `statusMonitor` 和 `rootDir`，确认无残留引用。

---

## 文件清单

**修改（Poltertty 文件）：**
- `macos/Sources/Features/Splits/TerminalSplitTreeView.swift` — 新增 `TerminalSplitLeafContainer` + `ShowStatusBarKey`；`.leaf` case 改用 container
- `macos/Sources/Features/Workspace/BottomStatusBarView.swift` — 新增 `isFocused` 参数 + opacity
- `macos/Sources/Features/Workspace/PolterttyRootView.swift` — 删除 `statusMonitor`/`showStatusBar` 参数及 `focusedPwd` 声明；`terminalAreaView` 删除 status bar 块；删除 `.onChange(of: focusedPwd)` 整块；`showStatusBar` 改为内部计算属性；`.terminal` HStack 追加 `.environment`
- `macos/Sources/Features/Terminal/TerminalController.swift` — 删除 `statusMonitor` 属性及 `rootDir`/`statusMonitor` 初始化；删除传参

**新增：** 无（所有新代码均追加到现有文件）

**Call site 确认：** `PolterttyRootView.init` 目前只有 `TerminalController.swift` 一处调用，已覆盖。实施前用 `grep` 搜索 `PolterttyRootView(` 确认无其他调用点（含 PreviewProvider）。

**上游文件：零修改**

---

## 错误处理

| 场景 | 行为 |
|------|------|
| pane 关闭 | `TerminalSplitLeafContainer` 销毁 → `@StateObject` 自动 deinit → `GitStatusMonitor.stopWatching()` 自动调用 |
| 非 git repo | `isGitRepo = false`，`BottomStatusBarView` 返回 `EmptyView()`，opacity 不生效 |
| `surfaceView.pwd` 初始为 nil | `onReceive` 用 `compactMap { $0 }` 过滤，monitor 保持初始空状态；`GitStatusMonitor(pwd: "")` 空字符串初始化时内部不发起 git 检测 |
| pane 尚未聚焦过（pwd 为空）| monitor 以空 pwd 初始化，不运行 git 检测，status bar 不渲染（`isGitRepo = false`） |
| 临时 workspace 或 `workspaceId == nil` | `showStatusBar = false`（内部计算），`TerminalSplitLeafContainer` 不渲染 status bar |
| 窗口失焦（focusedSurface == nil）| `isFocused` 返回 `true`，所有 pane status bar 保持不透明，避免全部变暗 |
