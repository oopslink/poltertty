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

每次打开 launcher 时重新扫描，保证反映当前菜单状态。

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
3. contains 匹配优先（对距离加权降低）
4. 按距离升序排列，过滤距离超过 `max(query.count, 3)` 的结果
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

条件：两次 `keyCode == kVK_Shift`，modifierFlags 仅含 `.shift`，间隔 ≤ 350ms。

在 `AppDelegate` 启动时调用 `start()`。

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

### PolterttyRootView 集成

```swift
@State private var launcherVisible = false

// ZStack 内添加：
if launcherVisible {
    AppLauncherView(isPresented: $launcherVisible)
}

// onReceive：
.onReceive(NotificationCenter.default.publisher(for: .toggleAppLauncher)) { _ in
    launcherVisible.toggle()
}
```

同时在 `Notification.Name` 扩展中添加 `.toggleAppLauncher`。

---

## 不在范围内

- 全局触发（App 不在前台时唤起）
- 命令历史记录
- 自定义命令注册接口（未来可扩展）
- 空状态下显示常用/最近命令
