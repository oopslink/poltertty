# App Launcher 设计文档

**日期**: 2026-03-21
**功能**: 双击 Shift 唤起悬浮命令 Launcher
**状态**: 已批准，待实现

---

## 概述

用户在 Poltertty 窗口处于前台时，双击 Shift 键唤起一个居中悬浮的命令输入框。输入任意字符后，下拉列表显示基于编辑距离排序的可用命令。选中命令后按回车执行。

---

## 需求

- 触发方式：双击 Shift（间隔 ≤ 350ms），仅 App 内有效（App 处于前台）
- 命令来源：macOS 菜单栏命令 + Poltertty 本地 actions
- 搜索算法：Levenshtein 编辑距离排序，前 8 条结果
- 空状态：不显示结果，仅显示 placeholder 提示文字
- UI 风格：居中浮层 + 半透明背景遮罩（Spotlight 风格）

---

## 架构

### 目录结构

```
macos/Sources/Features/App Launcher/
├── AppLauncherView.swift          # 主 UI
├── AppCommandRegistry.swift       # 命令注册表
├── EditDistanceFilter.swift       # 编辑距离排序
└── ShiftDoubleTapDetector.swift   # 双击 Shift 检测
```

### 触发流程

1. `ShiftDoubleTapDetector` 通过 `NSEvent.addLocalMonitorForEvents` 监听 App 内键盘事件
2. 两次 Shift 间隔 ≤ 350ms 且不含其他修饰键 → 发送 `Notification(.toggleAppLauncher)`
3. `PolterttyRootView` 收到通知 → 设置 `launcherVisible = true`，显示 `AppLauncherView` overlay
4. 用户输入 → `AppCommandRegistry.commands` 经 `EditDistanceFilter.rank` 排序后展示
5. 用户回车 / 点击 → 执行 action → 关闭 launcher

---

## 模块设计

### AppCommandRegistry

单例，提供 `commands: [CommandOption]` 属性。

**命令来源 1 — macOS 菜单项**
递归遍历 `NSApp.mainMenu`，跳过 separator 和无 action 的分组项。
- `title`：菜单标题
- `symbols`：`keyEquivalent` 转义为符号字符串
- `action`：`NSApp.sendAction(_:to:from:)`

每次打开 launcher 时重新扫描，保证反映当前菜单状态。扫描必须在主线程（`@MainActor`）执行，在 `AppLauncherView.onAppear` 中触发，不在 `ShiftDoubleTapDetector` 回调里同步执行。

**命令来源 2 — Poltertty 本地 actions**
手动注册，对应现有 Notifications：
- 切换侧边栏（`toggleWorkspaceSidebar`）
- 打开/关闭文件浏览器（`toggleFileBrowser`）
- 切换 Workspace（`toggleWorkspaceQuickSwitcher`）
- 打开 Agent Monitor（`toggleAgentMonitor`）
- 显示 tmux Session Picker（`showTmuxSessionPicker`）
- 等其他 Poltertty 功能

每条配有合适的 `leadingIcon`（SF Symbol）。

### EditDistanceFilter

```swift
static func rank(_ query: String, in options: [CommandOption]) -> [CommandOption]
```

算法：
1. query 为空 → 返回空数组
2. 对每个 option 计算 `levenshteinDistance(query.lowercased(), option.title.lowercased())`
3. contains 匹配优先：若 `option.title.lowercased().contains(query.lowercased())` 为 true，则对该 option 的距离值减 3（最低为 0）作为排序用的有效距离
4. 按有效距离升序排列，过滤有效距离超过 `max(query.count, 3)` 的结果
5. 返回前 8 条

Levenshtein 实现：标准 DP 矩阵，O(n×m)。

### ShiftDoubleTapDetector

```swift
class ShiftDoubleTapDetector {
    private var lastShiftTime: Date?
    private let threshold: TimeInterval = 0.35
    func start()   // 注册 NSEvent local monitor
    func stop()    // 移除 monitor
}
```

**事件类型**：监听 `NSEvent.EventType.flagsChanged`（不是 `.keyDown`）。单独按下 Shift 键产生 `flagsChanged` 事件，不产生 `keyDown`。

**触发条件**：
- `flagsChanged` 事件，`keyCode` 为 `kVK_Shift`（0x38，左 Shift）或 `kVK_RightShift`（0x3C，右 Shift），且 `modifierFlags.contains(.shift)` 为 true（按下瞬间，松开时该值为 false，松开事件忽略）
- 两次 Shift 按下（满足上述条件）间隔 ≤ 350ms
- 左右 Shift 混合触发视为有效（一次左 Shift + 一次右 Shift 也算双击）

**计时器重置条件**（以下任一情况发生时重置 `lastShiftTime`）：
- 收到 `.keyDown` 事件（有其他普通键被按下）
- 收到 `flagsChanged` 事件，但 `keyCode` 不是 Shift（说明 Cmd、Option、Ctrl 等修饰符发生变化）

**已打开时的行为**：若 launcher 已处于显示状态，再次双击 Shift 则关闭（toggle 语义）。

在 `AppDelegate` 启动时调用 `start()`，同时注册 `.keyDown` 和 `.flagsChanged` 两个 local monitor 用于计时器重置检测。

### AppLauncherView

```
ZStack (全屏覆盖)
├── Color.black.opacity(0.4)       # 遮罩，点击关闭
└── VStack (居中偏上 1/4 屏)
    ├── TextField (自动获焦，placeholder: "输入想找的功能…")
    ├── Divider (有结果时显示)
    └── ScrollView → CommandRow × N（复用现有组件）
```

尺寸：宽 500pt，最大高 350pt（含输入框 48pt + 最多 8 条结果）。

样式：与现有 `CommandPaletteView` 一致——`.ultraThinMaterial` + 窗口背景色 blend，圆角 10pt，`shadow(radius: 32, y: 12)`。

键盘导航：
- `↑` / `↓`、`Ctrl+P` / `Ctrl+N` — 移动选中
- `Return` — 执行并关闭
- `Escape` / 失焦 — 关闭

### CommandRow 复用策略

`CommandPalette.swift` 中的 `CommandRow` 是 `private struct`，无法跨文件使用。策略：将 `CommandRow`、`CommandTable`、`ShortcutSymbolsView` 的访问控制从 `private` 改为 `internal`（去掉 `private`），使 `AppLauncherView` 可以直接复用这三个纯展示组件。

`CommandPaletteQuery` **不复用**：其初始化器接受 `FocusState<Bool>` 参数，跨 view 传递会导致焦点状态交叉污染。`AppLauncherView` 的输入框部分在内部独立实现（与 `CommandPaletteQuery` 逻辑相似但各自管理自己的 `@FocusState`）。

### PolterttyRootView 集成

`PolterttyRootView` 是 per-window 组件，每个窗口有独立实例。Launcher 应只在 key window 中显示，避免多窗口同时弹出。

```swift
@State private var launcherVisible = false

// ZStack 内添加：
if launcherVisible {
    AppLauncherView(isPresented: $launcherVisible)
}

// onReceive：只在当前窗口是 key window 时响应
.onReceive(NotificationCenter.default.publisher(for: .toggleAppLauncher)) { _ in
    guard NSApp.keyWindow != nil else { return }
    launcherVisible.toggle()
}
```

注意：SwiftUI View 没有直接的 `window` 引用，用 `NSApp.keyWindow != nil` 做粗略判断。更精确的方案是在 `TerminalController`（NSWindowController 层）检查 `self.window?.isKeyWindow` 后再 post notification，使 notification 只被 key window 处理。

同时在 `Notification.Name` 扩展中添加 `.toggleAppLauncher`。

---

## 不在范围内

- 全局触发（App 不在前台时唤起）
- 命令历史记录
- 自定义命令注册接口（未来可扩展）
- 空状态下显示常用/最近命令
