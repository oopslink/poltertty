# Agent Browser 多 Tab 设计

**日期**：2026-04-05  
**状态**：已审核，待实现

---

## 背景

Agent Browser 当前是 1 Workspace : 1 WKWebView 的简单映射。为了支持 AI Agent 并发操作多个页面（如登录态隔离、并行抓取），以及人工手动多开页面，需要引入多 tab 支持。

---

## 设计目标

- 人工使用和 Agent 自动化同等重要
- Agent 通过 `tab_id`（UUID）稳定引用 tab，不受 tab 顺序变化影响
- Tab bar 紧凑，不额外占用行高（与工具栏合并为一行）
- 默认不恢复上次会话，首次打开时询问

---

## 数据模型

### `BrowserTab`（struct）

```swift
struct BrowserTab: Identifiable {
    let id: UUID          // tab_id，Agent 引用用
    var title: String     // 页面 <title>，实时更新
    var url: URL?         // 当前 URL
    let webView: WKWebView
}
```

### `BrowserTabSnapshot`（Codable，用于持久化）

```swift
struct BrowserTabSnapshot: Codable {
    let id: UUID
    let url: URL?
    let title: String
}
```

### `BrowserTabManager`（ObservableObject，一个 Workspace 一个实例）

```swift
@MainActor
class BrowserTabManager: ObservableObject {
    @Published private(set) var tabs: [BrowserTab] = []
    @Published var activeTabId: UUID?
    @Published var showRestorePrompt: Bool = false

    func newTab(url: URL? = nil) -> UUID   // 创建 tab，返回 tab_id
    func closeTab(id: UUID)                // 关闭 tab；若关闭 active，切换到相邻 tab
    func focusTab(id: UUID)                // 切换 active tab
    var activeTab: BrowserTab? { ... }

    func loadSnapshot(_ snapshot: [BrowserTabSnapshot])  // 用户确认恢复后调用
    func currentSnapshot() -> [BrowserTabSnapshot]       // 保存时调用
}
```

初始化时：若 `WorkspaceModel` 有 `browserTabSnapshots`，则设置 `showRestorePrompt = true`，不自动恢复。

### `BrowserSurfaceStore`（改造）

```swift
@MainActor
class BrowserSurfaceStore: ObservableObject {
    @Published private(set) var managers: [UUID: BrowserTabManager] = [:]

    func manager(for workspaceId: UUID) -> BrowserTabManager  // 懒惰创建
    func removeManager(for workspaceId: UUID)                  // Workspace 删除时调用
}
```

---

## UI 布局

Tab strip 与工具栏合并为一行（紧凑方案），结构从左到右：

```
[ tab1 | tab2* | tab3 | +N▾ ] [ + ] [ divider ] [ ‹ › ↺ ] [ 地址栏 ] [ ✕ ]
 ↑ tab 区（弹性，可变宽）                          ↑ 固定控件区
```

### Tab 样式规则

- **Active tab**：背景 `controlBackgroundColor`，有边框，文字 primary
- **Inactive tab**：无背景，文字 secondary，hover 时略微高亮
- **每个 tab**：显示截断的 title（`lineLimit(1)`），右侧有 `✕` 关闭按钮
- **`+` 按钮**：新建 tab，紧接在 tab 列表右侧

### Tab 溢出处理

当 tab 区域宽度不足以展示所有 tab 时，末尾显示 `+N ▾` 下拉按钮（`NSMenu` 或 SwiftUI `Menu`），列出所有溢出 tab 的完整 title 和 URL，点击切换。Active tab 始终优先显示在可见区域。

### 恢复询问 Banner

首次打开且有上次会话快照时，在工具栏下方（WebView 上方）显示 banner：

```
┌─────────────────────────────────────────────────────┐
│  上次会话有 N 个 tab，是否恢复？        [恢复]  忽略  │
└─────────────────────────────────────────────────────┘
```

- 点击「恢复」：调用 `manager.loadSnapshot(_:)`，创建对应 tab 并加载 URL
- 点击「忽略」：清除 snapshot，banner 消失，保持当前空白 tab

---

## 持久化

`WorkspaceModel` 新增两个可选字段：

```swift
var browserTabSnapshots: [BrowserTabSnapshot]?
var browserActiveTabId: UUID?
```

**保存时机**：Browser Panel 关闭时 或 App 退出时，调用 `manager.currentSnapshot()` 写入 `WorkspaceModel`。  
**恢复策略**：默认不恢复。`BrowserTabManager` 初始化时仅设置 `showRestorePrompt = true`，等待用户确认。

---

## Agent API

### Tab 管理接口

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `browser.new_tab` | `url?: String` | `{ tab_id }` | 新建 tab，可选初始 URL；创建后自动 focus 到新 tab |
| `browser.close_tab` | `tab_id: UUID` | — | 关闭指定 tab |
| `browser.focus_tab` | `tab_id: UUID` | — | 切换到指定 tab（更新 UI） |
| `browser.list_tabs` | — | `[{ tab_id, url, title, active }]` | 列出当前 Workspace 所有 tab |

### 操作类接口（扩展现有 `browser.*`）

所有现有操作接口新增可选 `tab_id` 参数：

- 不传 `tab_id`：作用于当前 active tab
- 传入 `tab_id`：作用于指定 tab，**不切换 active tab**

```jsonc
// 默认作用于 active tab
{ "method": "browser.navigate", "params": { "url": "https://localhost:3000" } }

// 指定 tab，不影响 UI 焦点
{ "method": "browser.snapshot", "params": { "tab_id": "uuid-xxx" } }
{ "method": "browser.click",    "params": { "tab_id": "uuid-xxx", "ref": "e3" } }
```

### 典型 Agent 工作流

```
# 在 tab_a 完成登录
new_tab()            → tab_a
navigate("https://app.example.com/login", tab_a)
fill(username_ref, "admin", tab_a)
fill(password_ref, "secret", tab_a)
click(submit_ref, tab_a)

# 另开 tab_b 操作业务页，登录态由 cookie 共享
new_tab()            → tab_b
navigate("https://app.example.com/dashboard", tab_b)
snapshot(tab_b)      → DOM 快照，不影响 tab_a
```

---

## 文件改动范围

```
Browser/
  BrowserSurfaceStore.swift       ← 改：managers 字典替换 webViews 字典
  BrowserTabManager.swift         ← 新：tab CRUD、恢复逻辑
  BrowserTab.swift                ← 新：BrowserTab struct + BrowserTabSnapshot
  BrowserPanelView.swift          ← 改：接受 BrowserTabManager，渲染 tab strip
  BrowserPanelToolbar.swift       ← 改：tab strip 区域嵌入工具栏行
  BrowserTabOverflowMenu.swift    ← 新：「+N ▾」下拉菜单组件
  BrowserRestoreBanner.swift      ← 新：恢复询问 banner 组件
  BrowserWebView.swift            ← 不变

WorkspaceModel.swift              ← 改：新增 browserTabSnapshots、browserActiveTabId
```

Ctrl API 层（`TerminalController.swift` 或独立 handler）新增 `browser.new_tab`、`browser.close_tab`、`browser.focus_tab`、`browser.list_tabs`，并为现有操作接口添加 `tab_id` 路由逻辑。

---

## 不在本次范围内

- Tab 标题的 favicon 显示
- Tab 拖拽排序
- 跨 Workspace 移动 tab
- Tab 的键盘快捷键（`⌘T` 新建 / `⌘W` 关闭）——与 Ghostty 原生快捷键有冲突，留待后续专项处理
