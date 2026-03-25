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

删除以下代码块：

```swift
Button(action: { ctrlAPIStore.isMonitorVisible.toggle() }) {
    Image(systemName: "network")
        .font(.system(size: 11))
        .foregroundStyle(ctrlAPIStore.isMonitorVisible ? Color.accentColor : Color.secondary)
}
.buttonStyle(.plain)
.help("Ctrl API Monitor")
```

同时删除已不再使用的 `@ObservedObject private var ctrlAPIStore = CtrlAPIStore.shared` 属性声明。

---

## 改动二：JSON 语法高亮（WKWebView + highlight.js）

**方案**: 复用项目已有的 `highlight.min.js`（位于 `FileBrowser` 目录），用 `WKWebView` 渲染高亮 JSON。

**新增文件**: `macos/Sources/Features/Agent/CtrlServer/HighlightedJSONView.swift`

实现要点：
- `NSViewRepresentable` 包装 `WKWebView`
- 加载内联 HTML，注入 `highlight.min.js`，对 `<pre><code class="language-json">` 执行高亮
- 使用 `prefers-color-scheme` CSS media query 自动适配系统深浅色
- 背景色透明，与 detail pane 背景融合
- WKWebView 原生提供文字选择能力

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
HighlightedJSONView(content: prettyJSON(body), isError: isError)
```

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
│   └── Controller API Monitor          ⌥⌘I
└── ───────────────────────────────────
└── Jump to Highest Priority Unread     ⌥⌘U
```

### 具体改动

1. 新建 `NSMenu(title: "Observability")`，将以下现有项移入：
   - `toggleAgentMonitor` → 改名为 `Agents In Workspace`，保留 `⌥⌘M`
   - `showAgentDashboard` → `Agent Dashboard`，保留 `⌥⌘D`
   - `toggleNotificationCenter` → `Agent Notification Center`，保留 `⌥⌘N`

2. 在子菜单末尾加 separator，新增：
   - `Controller API Monitor`，快捷键 `⌥⌘I`，触发新 selector `toggleCtrlAPIMonitor(_:)`

3. 新增 selector：
   ```swift
   @objc func toggleCtrlAPIMonitor(_ sender: Any?) {
       CtrlAPIStore.shared.isMonitorVisible.toggle()
   }
   ```

4. `Agent Dashboard` 的行为保持不变（`showAgentDashboard` 打开独立窗口）。

5. `Jump to Highest Priority Unread` 保留在 Agent 顶层菜单（通知操作，非观测工具）。

---

## 不在范围内

- `CtrlAPIStore`、`CtrlAPIRecord` 数据层不做改动
- `CtrlAPIMonitorPanel` 布局（拖拽调整高度、HSplitView、过滤器）不做改动
- highlight.js 本身不做升级或替换
