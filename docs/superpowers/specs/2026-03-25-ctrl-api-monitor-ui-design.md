# Ctrl API Monitor UI 优化设计文档

**日期**: 2026-03-25
**分支**: feat/ctrl-api-monitor-ui
**范围**: 三处独立改动，不涉及 CtrlAPIStore / CtrlAPIRecord 数据层

---

## 背景

当前 Ctrl API Monitor 存在以下问题：

1. Status bar 有一个 `network` 图标按钮占用空间，与菜单栏入口重复
2. Detail pane 的 Request / Response 内容使用纯文本 `Text()`，无语法高亮
3. Agent 菜单中 Observability 工具分散，缺乏层次

---

## 改动一：移除 Status Bar 按钮

**文件**: `macos/Sources/Features/Workspace/BottomStatusBarView.swift`

删除以下两处代码（必须同时删除，否则编译器报 unused property 警告）：

```swift
// 删除属性声明
@ObservedObject private var ctrlAPIStore = CtrlAPIStore.shared

// 删除按钮代码块
Button(action: { ctrlAPIStore.isMonitorVisible.toggle() }) {
    Image(systemName: "network")
        .font(.system(size: 11))
        .foregroundStyle(ctrlAPIStore.isMonitorVisible ? Color.accentColor : Color.secondary)
}
.buttonStyle(.plain)
.help("Ctrl API Monitor")
```

---

## 改动二：JSON 语法高亮（复用现有 SyntaxHighlighter）

**方案**: 复用 `SyntaxHighlightView.swift` 中已有的 `SyntaxHighlighter`（JavaScriptCore + highlight.js），封装一个不带行号 gutter 的轻量 wrapper。`prettyJSON()` 函数已存在于 `CtrlAPIMonitorPanel.swift`，无需改动。

**新增文件**: `macos/Sources/Features/Agent/CtrlServer/JSONHighlightView.swift`

实现要点：
- `NSViewRepresentable` 包装 `NSScrollView` + `NSTextView`（无 gutter）
- 调用 `SyntaxHighlighter().highlight(code, language: "json")` 得到 `NSAttributedString`
- 背景色：`AtomOneDark.background`（固定深色，terminal 风格，不跟随系统浅色模式，与 FileBrowser 高亮行为一致）
- `NSTextView.isSelectable = true`，支持文字选择与复制
- 竖向可滚动，横向不滚动
- `isError = true` 时：跳过 SyntaxHighlighter，直接渲染纯红色等宽文本（`NSColor.systemRed`，与现有 error section 视觉一致）
- `body` 为空时（`nil` 或空字符串）：`prettyJSON()` 已返回 `"(empty)"`，直接渲染该占位文本，无需特殊处理

**修改文件**: `macos/Sources/Features/Agent/CtrlServer/CtrlAPIMonitorPanel.swift`

将 `detailSection` 函数内的 `ScrollView { Text(...) }` 替换为：

```swift
JSONHighlightView(content: prettyJSON(body), isError: isError)
```

外层 `VStack` 结构（标题栏 + Divider + 内容区）保持不变。

---

## 改动三：菜单栏 Observability 子菜单

**文件**: `macos/Sources/App/macOS/AppDelegate.swift`

**快捷键**: `⌥⌘C`（C for Controller）。已确认 AppDelegate 中无 `⌥⌘C` 使用。`⌥⌘I` 已被 Ghostty 内建 Terminal Inspector 占用，不可使用。

### 新菜单结构

```
Agent
├── Launch Agent                        ⌥⌘A
├── [separator]
├── Observability ▶
│   ├── Agents In Workspace             ⌥⌘M  (原: Toggle Agent Monitor)
│   ├── Agent Dashboard                 ⌥⌘D
│   ├── Agent Notification Center       ⌥⌘N  (原: Toggle Notification Center)
│   ├── [separator]
│   └── Controller API Monitor          ⌥⌘C  (新增)
├── [separator]
└── Jump to Highest Priority Unread     ⌥⌘U
```

### 具体改动

从当前 `agentMenu` 中删除以下 `addItem` 调用：
- `agentMenu.addItem(toggleAgentMonitor)`
- `agentMenu.addItem(toggleNotificationCenter)`
- `agentMenu.addItem(agentDashboard)`
- 相关 `separator` 调整（保留 Launch Agent 后的 separator，保留 Jump to Unread 前的 separator）

新建 `NSMenu(title: "Observability")`，按顺序添加：

```swift
let observabilityMenu = NSMenu(title: "Observability")

let agentsInWorkspace = NSMenuItem(
    title: "Agents In Workspace",
    action: #selector(toggleAgentMonitor(_:)),
    keyEquivalent: "m")
agentsInWorkspace.keyEquivalentModifierMask = [.command, .option]
observabilityMenu.addItem(agentsInWorkspace)

let agentDashboard = NSMenuItem(
    title: "Agent Dashboard",
    action: #selector(showAgentDashboard(_:)),
    keyEquivalent: "d")
agentDashboard.keyEquivalentModifierMask = [.command, .option]
observabilityMenu.addItem(agentDashboard)

let notifCenter = NSMenuItem(
    title: "Agent Notification Center",
    action: #selector(toggleNotificationCenter(_:)),
    keyEquivalent: "n")
notifCenter.keyEquivalentModifierMask = [.command, .option]
observabilityMenu.addItem(notifCenter)

observabilityMenu.addItem(.separator())

let ctrlMonitor = NSMenuItem(
    title: "Controller API Monitor",
    action: #selector(toggleCtrlAPIMonitor(_:)),
    keyEquivalent: "c")
ctrlMonitor.keyEquivalentModifierMask = [.command, .option]
observabilityMenu.addItem(ctrlMonitor)

let observabilityItem = NSMenuItem(title: "Observability", action: nil, keyEquivalent: "")
observabilityItem.submenu = observabilityMenu
agentMenu.addItem(observabilityItem)
```

新增 selector（加在 `AppDelegate` 中，与其他 toggle selector 同处）：

```swift
@objc func toggleCtrlAPIMonitor(_ sender: Any?) {
    CtrlAPIStore.shared.isMonitorVisible.toggle()
}
```

NSMenuItem 的 `target` 使用默认值 `nil`（走 responder chain），与其他现有菜单项一致。

---

## 不在范围内

- `CtrlAPIStore`、`CtrlAPIRecord` 数据层不做改动
- `CtrlAPIMonitorPanel` 布局（拖拽调整高度、HSplitView、过滤器）不做改动
- `SyntaxHighlighter` / `SyntaxHighlightView` 本身不做改动
- highlight.js 不做升级或替换
