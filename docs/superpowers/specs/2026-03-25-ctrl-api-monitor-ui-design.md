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

删除以下代码块（必须删除，否则编译器会报 unused property 警告）：

```swift
@ObservedObject private var ctrlAPIStore = CtrlAPIStore.shared
```

以及：

```swift
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

**方案**: 复用 `SyntaxHighlightView.swift` 中已有的 `SyntaxHighlighter`（JavaScriptCore + highlight.js），封装一个不带行号 gutter 的轻量 wrapper。

**新增文件**: `macos/Sources/Features/Agent/CtrlServer/JSONHighlightView.swift`

实现要点：
- `NSViewRepresentable` 包装单个 `NSTextView`（无 gutter，无 `SyntaxContainerView`）
- 直接调用 `SyntaxHighlighter().highlight(code, language: "json")` 得到 `NSAttributedString`
- 背景色用 `AtomOneDark.background`，与现有 FileBrowser 高亮风格一致
- `NSTextView.isSelectable = true`，支持文字选择
- 竖向可滚动（`NSScrollView` 包裹），横向不需要（JSON pretty print 通常不超宽）

**修改文件**: `macos/Sources/Features/Agent/CtrlServer/CtrlAPIMonitorPanel.swift`

将 `detailSection` 函数内的：

```swift
ScrollView([.horizontal, .vertical]) {
    Text(prettyJSON(body))
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(isError ? Color.red : Color.primary)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
}
```

替换为：

```swift
JSONHighlightView(content: prettyJSON(body), isError: isError)
```

`isError` 为 true 时，跳过语法高亮，直接以红色纯文本渲染（与现有 error section 行为一致）。

外层 `VStack` 结构（标题栏 + Divider + 内容区）保持不变。

---

## 改动三：菜单栏 Observability 子菜单

**文件**: `macos/Sources/App/macOS/AppDelegate.swift`

### 新菜单结构

```
Agent
├── Launch Agent                        ⌥⌘A
├── ───────────────────────────────────
├── Observability ▶
│   ├── Agents In Workspace             ⌥⌘M
│   ├── Agent Dashboard                 ⌥⌘D
│   ├── Agent Notification Center       ⌥⌘N
│   ├── ─────────────────────────────
│   └── Controller API Monitor          ⌥⌘C
└── ───────────────────────────────────
└── Jump to Highest Priority Unread     ⌥⌘U
```

注：`⌥⌘I` 已被 Ghostty 内建 Terminal Inspector 占用，Controller API Monitor 改用 `⌥⌘C`（C for Controller）。

### 具体改动

删除当前 `agentMenu` 中以下 `addItem` 调用：
- `agentMenu.addItem(toggleAgentMonitor)`
- `agentMenu.addItem(toggleNotificationCenter)`
- `agentMenu.addItem(.separator())` （两处 separator 中位于这两项前后的）
- `agentMenu.addItem(agentDashboard)`

新建 `NSMenu(title: "Observability")`，按以下顺序添加：

```swift
let observabilityMenu = NSMenu(title: "Observability")

// Agents In Workspace（原 Toggle Agent Monitor，保留 selector 和快捷键）
let agentsInWorkspace = NSMenuItem(title: "Agents In Workspace",
    action: #selector(toggleAgentMonitor(_:)), keyEquivalent: "m")
agentsInWorkspace.keyEquivalentModifierMask = [.command, .option]
observabilityMenu.addItem(agentsInWorkspace)

// Agent Dashboard（原 showAgentDashboard，保留行为）
let agentDashboard = NSMenuItem(title: "Agent Dashboard",
    action: #selector(showAgentDashboard(_:)), keyEquivalent: "d")
agentDashboard.keyEquivalentModifierMask = [.command, .option]
observabilityMenu.addItem(agentDashboard)

// Agent Notification Center（原 Toggle Notification Center）
let notifCenter = NSMenuItem(title: "Agent Notification Center",
    action: #selector(toggleNotificationCenter(_:)), keyEquivalent: "n")
notifCenter.keyEquivalentModifierMask = [.command, .option]
observabilityMenu.addItem(notifCenter)

observabilityMenu.addItem(.separator())

// Controller API Monitor（新增）
let ctrlMonitor = NSMenuItem(title: "Controller API Monitor",
    action: #selector(toggleCtrlAPIMonitor(_:)), keyEquivalent: "c")
ctrlMonitor.keyEquivalentModifierMask = [.command, .option]
observabilityMenu.addItem(ctrlMonitor)

let observabilityItem = NSMenuItem(title: "Observability", action: nil, keyEquivalent: "")
observabilityItem.submenu = observabilityMenu
agentMenu.addItem(observabilityItem)
```

新增 selector：

```swift
@objc func toggleCtrlAPIMonitor(_ sender: Any?) {
    CtrlAPIStore.shared.isMonitorVisible.toggle()
}
```

`Jump to Highest Priority Unread`（`⌥⌘U`）保留在 Agent 顶层，位置在 Observability 之后加 separator 后。

---

## 不在范围内

- `CtrlAPIStore`、`CtrlAPIRecord` 数据层不做改动
- `CtrlAPIMonitorPanel` 布局（拖拽调整高度、HSplitView、过滤器）不做改动
- `SyntaxHighlighter` / `SyntaxHighlightView` 本身不做改动
- highlight.js 不做升级或替换
