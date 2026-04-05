# Agent Browser Multi-Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Agent Browser 面板添加多 tab 支持，人工使用和 Agent API 同等重要。

**Architecture:** 引入 `BrowserTabManager`（一个 Workspace 一个实例），持有 `[BrowserTab]` 数组和 active tab ID；`BrowserSurfaceStore` 改为管理 `[WorkspaceID: BrowserTabManager]`；tab strip 嵌入工具栏行（紧凑方案），溢出时显示 `+N ▾` 下拉；Agent 通过 `browser_new_tab` / `browser_close_tab` / `browser_focus_tab` / `browser_list_tabs` 操作，并可在现有 browser 操作中传入 `tabId` 参数。

**Tech Stack:** Swift 5.9, SwiftUI, WKWebKit, Swift Testing (`@Test` / `#expect`)

---

## 文件结构

| 文件 | 操作 | 职责 |
|------|------|------|
| `Browser/BrowserTab.swift` | **新建** | `BrowserTab` struct + `BrowserTabSnapshot` Codable |
| `Browser/BrowserTabManager.swift` | **新建** | tab CRUD、active 状态、restore prompt 逻辑 |
| `Browser/BrowserTabOverflowMenu.swift` | **新建** | `+N ▾` 下拉菜单组件 |
| `Browser/BrowserRestoreBanner.swift` | **新建** | 首次打开时的恢复询问 banner |
| `Browser/BrowserSurfaceStore.swift` | **改造** | `[UUID: WKWebView]` → `[UUID: BrowserTabManager]` |
| `Browser/BrowserPanelToolbar.swift` | **改造** | 工具栏嵌入 tab strip |
| `Browser/BrowserPanelView.swift` | **改造** | 接受 BrowserTabManager，渲染 active WebView + banner |
| `Browser/BrowserWebView.swift` | **不变** | — |
| `Workspace/WorkspaceModel.swift` | **改造** | 新增 `browserTabSnapshots` + `browserActiveTabId` |
| `Agent/CtrlServer/CtrlToolHandler.swift` | **改造** | 新增 `browser_new_tab` / `browser_close_tab` / `browser_focus_tab` / `browser_list_tabs` |
| `Tests/Workspace/BrowserTabManagerTests.swift` | **新建** | BrowserTabManager 单元测试 |

---

## Task 1: BrowserTab 数据模型

**Files:**
- Create: `macos/Sources/Features/Workspace/Browser/BrowserTab.swift`

- [ ] **Step 1: 创建文件**

```swift
// macos/Sources/Features/Workspace/Browser/BrowserTab.swift
import Foundation
import WebKit

/// 一个 browser tab 实例。WKWebView 由 BrowserTabManager 在创建时注入。
struct BrowserTab: Identifiable {
    let id: UUID
    var title: String
    var url: URL?
    let webView: WKWebView

    init(id: UUID = UUID(), title: String = "New Tab", url: URL? = nil, webView: WKWebView) {
        self.id = id
        self.title = title
        self.url = url
        self.webView = webView
    }
}

/// 用于持久化的轻量快照，不含 WKWebView。
struct BrowserTabSnapshot: Codable, Equatable {
    let id: UUID
    let url: URL?
    let title: String
}
```

- [ ] **Step 2: 构建验证**

```bash
make check
```

预期：零编译错误。

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/Browser/BrowserTab.swift
git commit -m "feat(browser): add BrowserTab and BrowserTabSnapshot data model"
```

---

## Task 2: BrowserTabManager — 核心 CRUD

**Files:**
- Create: `macos/Sources/Features/Workspace/Browser/BrowserTabManager.swift`
- Create: `macos/Tests/Workspace/BrowserTabManagerTests.swift`

- [ ] **Step 1: 先写测试（TDD）**

```swift
// macos/Tests/Workspace/BrowserTabManagerTests.swift
import Testing
import Foundation
import WebKit
@testable import Ghostty

@MainActor
struct BrowserTabManagerTests {

    // MARK: - newTab

    @Test func newTabCreatesTabAndFocuses() {
        let mgr = BrowserTabManager()
        #expect(mgr.tabs.isEmpty)
        let id = mgr.newTab()
        #expect(mgr.tabs.count == 1)
        #expect(mgr.tabs[0].id == id)
        #expect(mgr.activeTabId == id)
    }

    @Test func newTabWithURLSetsURL() {
        let mgr = BrowserTabManager()
        let url = URL(string: "https://example.com")!
        let id = mgr.newTab(url: url)
        #expect(mgr.tabs[0].url == url)
        _ = id
    }

    @Test func secondNewTabFocusesNewTab() {
        let mgr = BrowserTabManager()
        _ = mgr.newTab()
        let id2 = mgr.newTab()
        #expect(mgr.tabs.count == 2)
        #expect(mgr.activeTabId == id2)
    }

    // MARK: - closeTab

    @Test func closeTabRemovesIt() {
        let mgr = BrowserTabManager()
        let id = mgr.newTab()
        mgr.closeTab(id: id)
        #expect(mgr.tabs.isEmpty)
    }

    @Test func closeActiveTabSwitchesToLeftNeighbor() {
        let mgr = BrowserTabManager()
        let id1 = mgr.newTab()
        let id2 = mgr.newTab()
        // active は id2
        mgr.closeTab(id: id2)
        #expect(mgr.tabs.count == 1)
        #expect(mgr.activeTabId == id1)
    }

    @Test func closeActiveTabWhenNoLeftNeighborSwitchesToRight() {
        let mgr = BrowserTabManager()
        let id1 = mgr.newTab()
        let id2 = mgr.newTab()
        mgr.focusTab(id: id1)        // active は id1（左端）
        mgr.closeTab(id: id1)
        #expect(mgr.tabs.count == 1)
        #expect(mgr.activeTabId == id2)
    }

    @Test func closeLastTabCreatesNewBlankTab() {
        let mgr = BrowserTabManager()
        let id = mgr.newTab()
        mgr.closeTab(id: id)
        // 最後の tab を閉じると新しい blank tab が自動生成される
        #expect(mgr.tabs.count == 1)
        #expect(mgr.tabs[0].url == nil)
        #expect(mgr.activeTabId == mgr.tabs[0].id)
    }

    // MARK: - focusTab

    @Test func focusTabUpdatesActiveId() {
        let mgr = BrowserTabManager()
        let id1 = mgr.newTab()
        let id2 = mgr.newTab()
        mgr.focusTab(id: id1)
        #expect(mgr.activeTabId == id1)
        _ = id2
    }

    @Test func focusUnknownIdIsNoOp() {
        let mgr = BrowserTabManager()
        let id = mgr.newTab()
        mgr.focusTab(id: UUID())   // 存在しない ID
        #expect(mgr.activeTabId == id)
    }

    // MARK: - activeTab

    @Test func activeTabReturnsCorrectTab() {
        let mgr = BrowserTabManager()
        let id1 = mgr.newTab()
        _ = mgr.newTab()
        mgr.focusTab(id: id1)
        #expect(mgr.activeTab?.id == id1)
    }
}
```

- [ ] **Step 2: 运行测试，确认全部失败（BrowserTabManager 还不存在）**

```bash
xcodebuild test \
  -project macos/Ghostty.xcodeproj \
  -scheme Ghostty \
  -destination 'platform=macOS' \
  -only-testing:GhosttyTests/BrowserTabManagerTests \
  2>&1 | grep -E "(FAILED|error:|Build FAILED)"
```

预期：`Build FAILED` 因 `BrowserTabManager` 未定义。

- [ ] **Step 3: 实现 BrowserTabManager**

```swift
// macos/Sources/Features/Workspace/Browser/BrowserTabManager.swift
import Foundation
import WebKit

/// 管理单个 Workspace 的所有 browser tab。
/// 一个 Workspace 对应一个实例，由 BrowserSurfaceStore 持有。
@MainActor
final class BrowserTabManager: ObservableObject {
    @Published private(set) var tabs: [BrowserTab] = []
    @Published private(set) var activeTabId: UUID?
    @Published var showRestorePrompt: Bool = false

    private let webViewFactory: () -> WKWebView

    init(webViewFactory: @escaping () -> WKWebView = { WKWebView() }) {
        self.webViewFactory = webViewFactory
    }

    // MARK: - Public API

    /// 新建 tab，自动 focus 到新 tab。返回 tab_id。
    @discardableResult
    func newTab(url: URL? = nil) -> UUID {
        let wv = makeWebView()
        var tab = BrowserTab(webView: wv)
        tab.url = url
        if let url {
            wv.load(URLRequest(url: url))
        }
        tabs.append(tab)
        activeTabId = tab.id
        return tab.id
    }

    /// 关闭指定 tab。若关闭的是 active tab，切换到左侧邻居（无左则取右侧）。
    /// 若关闭后 tabs 为空，自动创建一个空白 tab。
    func closeTab(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = activeTabId == id
        tabs[idx].webView.navigationDelegate = nil
        tabs.remove(at: idx)
        if wasActive {
            if tabs.isEmpty {
                newTab()
            } else {
                let newIdx = max(0, idx - 1)
                activeTabId = tabs[newIdx].id
            }
        }
    }

    /// 切换 active tab（不切换时不修改 active）。
    func focusTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabId = id
    }

    var activeTab: BrowserTab? {
        tabs.first { $0.id == activeTabId }
    }

    // MARK: - Restore

    /// 加载快照并创建对应 tab（用户点「Restore」后调用）。
    func loadSnapshot(_ snapshots: [BrowserTabSnapshot], activeId: UUID?) {
        for snap in snapshots {
            let wv = makeWebView()
            var tab = BrowserTab(id: snap.id, title: snap.title, url: snap.url, webView: wv)
            if let url = snap.url {
                wv.load(URLRequest(url: url))
            }
            tabs.append(tab)
        }
        if let activeId, tabs.contains(where: { $0.id == activeId }) {
            activeTabId = activeId
        } else {
            activeTabId = tabs.first?.id
        }
        showRestorePrompt = false
    }

    /// 将当前所有 tab 序列化为快照数组（保存时调用）。
    func currentSnapshot() -> [BrowserTabSnapshot] {
        tabs.map { BrowserTabSnapshot(id: $0.id, url: $0.url, title: $0.title) }
    }

    /// 若有可恢复的快照，设置 showRestorePrompt = true（BrowserSurfaceStore 初始化时调用）。
    func prepareRestore(snapshots: [BrowserTabSnapshot]) {
        guard !snapshots.isEmpty else { return }
        showRestorePrompt = true
    }

    // MARK: - Title/URL Update (called from BrowserWebView coordinator)

    func updateTab(id: UUID, title: String?, url: URL?) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        if let title { tabs[idx].title = title }
        if let url   { tabs[idx].url = url }
    }

    // MARK: - Private

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        let wv = webViewFactory()
        wv.allowsBackForwardNavigationGestures = true
        return wv
    }
}
```

- [ ] **Step 4: 运行测试，确认全部通过**

```bash
xcodebuild test \
  -project macos/Ghostty.xcodeproj \
  -scheme Ghostty \
  -destination 'platform=macOS' \
  -only-testing:GhosttyTests/BrowserTabManagerTests \
  2>&1 | grep -E "(Test Suite|passed|failed)"
```

预期：`Test Suite 'BrowserTabManagerTests' passed`，所有 10 个测试绿色。

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Workspace/Browser/BrowserTabManager.swift \
        macos/Tests/Workspace/BrowserTabManagerTests.swift
git commit -m "feat(browser): add BrowserTabManager with full tab CRUD and tests"
```

---

## Task 3: BrowserTabManager — Restore 持久化逻辑测试

**Files:**
- Modify: `macos/Tests/Workspace/BrowserTabManagerTests.swift`

- [ ] **Step 1: 追加 restore 相关测试**

在 `BrowserTabManagerTests` struct 末尾追加：

```swift
    // MARK: - Snapshot / Restore

    @Test func currentSnapshotReturnsAllTabs() {
        let mgr = BrowserTabManager()
        let url = URL(string: "https://example.com")!
        let id = mgr.newTab(url: url)
        mgr.updateTab(id: id, title: "Example", url: url)
        let snaps = mgr.currentSnapshot()
        #expect(snaps.count == 1)
        #expect(snaps[0].id == id)
        #expect(snaps[0].url == url)
        #expect(snaps[0].title == "Example")
    }

    @Test func currentSnapshotWhenEmptyReturnsEmpty() {
        let mgr = BrowserTabManager()
        _ = mgr.newTab()
        // tab が 1 つある状態で取得
        let snaps = mgr.currentSnapshot()
        #expect(snaps.count == 1)
    }

    @Test func prepareRestoreSetsPromptFlagWhenSnapshotsExist() {
        let mgr = BrowserTabManager()
        let snap = BrowserTabSnapshot(id: UUID(), url: URL(string: "https://a.com"), title: "A")
        mgr.prepareRestore(snapshots: [snap])
        #expect(mgr.showRestorePrompt == true)
        #expect(mgr.tabs.isEmpty)   // prepareRestore は tab を作らない
    }

    @Test func prepareRestoreDoesNothingForEmptySnapshots() {
        let mgr = BrowserTabManager()
        mgr.prepareRestore(snapshots: [])
        #expect(mgr.showRestorePrompt == false)
    }

    @Test func loadSnapshotCreatesTabs() {
        let mgr = BrowserTabManager()
        let id1 = UUID()
        let id2 = UUID()
        let snaps = [
            BrowserTabSnapshot(id: id1, url: URL(string: "https://a.com"), title: "A"),
            BrowserTabSnapshot(id: id2, url: nil, title: "B"),
        ]
        mgr.loadSnapshot(snaps, activeId: id2)
        #expect(mgr.tabs.count == 2)
        #expect(mgr.tabs[0].id == id1)
        #expect(mgr.tabs[1].id == id2)
        #expect(mgr.activeTabId == id2)
        #expect(mgr.showRestorePrompt == false)
    }

    @Test func loadSnapshotFallsBackToFirstTabIfActiveIdUnknown() {
        let mgr = BrowserTabManager()
        let snap = BrowserTabSnapshot(id: UUID(), url: nil, title: "X")
        mgr.loadSnapshot([snap], activeId: UUID())  // 存在しない activeId
        #expect(mgr.activeTabId == snap.id)
    }
```

- [ ] **Step 2: 运行测试**

```bash
xcodebuild test \
  -project macos/Ghostty.xcodeproj \
  -scheme Ghostty \
  -destination 'platform=macOS' \
  -only-testing:GhosttyTests/BrowserTabManagerTests \
  2>&1 | grep -E "(Test Suite|passed|failed)"
```

预期：全部通过。

- [ ] **Step 3: Commit**

```bash
git add macos/Tests/Workspace/BrowserTabManagerTests.swift
git commit -m "test(browser): add snapshot/restore tests for BrowserTabManager"
```

---

## Task 4: WorkspaceModel — 新增持久化字段

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceModel.swift`

- [ ] **Step 1: 新增两个可选字段到 `WorkspaceModel` struct**

在 `browserPanelWidth: CGFloat = 400` 之后添加：

```swift
    var browserTabSnapshots: [BrowserTabSnapshot]?
    var browserActiveTabId: UUID?
```

- [ ] **Step 2: 更新 `CodingKeys` enum**

在 `browserPanelWidth = "browserPanelWidth"` 之后添加：

```swift
        case browserTabSnapshots = "browserTabSnapshots"
        case browserActiveTabId = "browserActiveTabId"
```

- [ ] **Step 3: 更新 `init(from decoder:)` 中的解码**

在 `browserPanelWidth = try container.decodeIfPresent(...)` 之后添加：

```swift
        browserTabSnapshots = try container.decodeIfPresent([BrowserTabSnapshot].self, forKey: .browserTabSnapshots)
        browserActiveTabId  = try container.decodeIfPresent(UUID.self, forKey: .browserActiveTabId)
```

- [ ] **Step 4: 构建验证**

```bash
make check
```

预期：零编译错误。

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceModel.swift
git commit -m "feat(browser): add browserTabSnapshots and browserActiveTabId to WorkspaceModel"
```

---

## Task 5: BrowserSurfaceStore — 改为管理 BrowserTabManager

**Files:**
- Modify: `macos/Sources/Features/Workspace/Browser/BrowserSurfaceStore.swift`

- [ ] **Step 1: 全量替换文件内容**

```swift
// macos/Sources/Features/Workspace/Browser/BrowserSurfaceStore.swift
import Foundation
import WebKit

/// 管理每个 Workspace 对应的 BrowserTabManager。
/// BrowserTabManager 懒惰创建（首次打开 Browser Panel 时），Workspace 删除时销毁。
@MainActor
class BrowserSurfaceStore: ObservableObject {
    @Published private(set) var managers: [UUID: BrowserTabManager] = [:]

    /// 获取或创建指定 Workspace 的 BrowserTabManager。
    /// 若 WorkspaceModel 有快照且尚未加载，设置 showRestorePrompt。
    func manager(for workspaceId: UUID, snapshots: [BrowserTabSnapshot]? = nil) -> BrowserTabManager {
        if let existing = managers[workspaceId] {
            return existing
        }
        let mgr = BrowserTabManager()
        // 若有持久化快照，提示用户恢复（不自动创建 tab）
        if let snaps = snapshots, !snaps.isEmpty {
            mgr.prepareRestore(snapshots: snaps)
        }
        // 没有快照时创建一个初始空白 tab
        if mgr.tabs.isEmpty && !mgr.showRestorePrompt {
            mgr.newTab()
        }
        managers[workspaceId] = mgr
        return mgr
    }

    /// Workspace 删除时调用，释放所有 WKWebView。
    func removeManager(for workspaceId: UUID) {
        if let mgr = managers[workspaceId] {
            for tab in mgr.tabs {
                tab.webView.navigationDelegate = nil
            }
        }
        managers.removeValue(forKey: workspaceId)
    }
}
```

- [ ] **Step 2: 构建验证**

```bash
make check
```

预期：零编译错误。（此时 `BrowserPanelView` 和 `BrowserPanelToolbar` 可能报错，因为它们还在用旧 API，下面 Task 8 / 9 修复。）

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/Browser/BrowserSurfaceStore.swift
git commit -m "feat(browser): refactor BrowserSurfaceStore to manage BrowserTabManager per workspace"
```

---

## Task 6: BrowserTabOverflowMenu — 溢出下拉组件

**Files:**
- Create: `macos/Sources/Features/Workspace/Browser/BrowserTabOverflowMenu.swift`

- [ ] **Step 1: 创建文件**

```swift
// macos/Sources/Features/Workspace/Browser/BrowserTabOverflowMenu.swift
import SwiftUI

/// 当 tab 数量超出可见区域时，显示「+N ▾」下拉按钮，列出所有溢出 tab。
struct BrowserTabOverflowMenu: View {
    let overflowTabs: [BrowserTab]
    let activeTabId: UUID?
    let onSelect: (UUID) -> Void

    var body: some View {
        Menu {
            ForEach(overflowTabs) { tab in
                Button {
                    onSelect(tab.id)
                } label: {
                    HStack {
                        if tab.id == activeTabId {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9))
                        }
                        Text(tab.title.isEmpty ? "New Tab" : tab.title)
                        Spacer()
                        if let url = tab.url {
                            Text(url.host ?? "")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 10))
                        }
                    }
                }
            }
        } label: {
            Text("+\(overflowTabs.count) ▾")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .cornerRadius(3)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
```

- [ ] **Step 2: 构建验证**

```bash
make check
```

预期：零编译错误。

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/Browser/BrowserTabOverflowMenu.swift
git commit -m "feat(browser): add BrowserTabOverflowMenu component"
```

---

## Task 7: BrowserRestoreBanner — 恢复询问 Banner

**Files:**
- Create: `macos/Sources/Features/Workspace/Browser/BrowserRestoreBanner.swift`

- [ ] **Step 1: 创建文件**

```swift
// macos/Sources/Features/Workspace/Browser/BrowserRestoreBanner.swift
import SwiftUI

/// 首次打开 Browser Panel 时，若有上次会话快照，显示此 banner 询问是否恢复。
struct BrowserRestoreBanner: View {
    let tabCount: Int
    let onRestore: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11))
                .foregroundStyle(Color.green.opacity(0.8))

            Text("Restore \(tabCount) tab\(tabCount == 1 ? "" : "s") from last session?")
                .font(.system(size: 11))
                .foregroundStyle(.primary)

            Spacer()

            Button("Restore") {
                onRestore()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Color.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.green.opacity(0.1))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.green.opacity(0.4), lineWidth: 0.5)
            )

            Button("Dismiss") {
                onDismiss()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.05))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Color.green.opacity(0.2)),
            alignment: .bottom
        )
    }
}
```

- [ ] **Step 2: 构建验证**

```bash
make check
```

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/Browser/BrowserRestoreBanner.swift
git commit -m "feat(browser): add BrowserRestoreBanner component"
```

---

## Task 8: BrowserPanelToolbar — 嵌入 Tab Strip

**Files:**
- Modify: `macos/Sources/Features/Workspace/Browser/BrowserPanelToolbar.swift`

工具栏行结构（左 → 右）：
```
[tab strip 弹性区] [+] [divider] [‹] [›] [↺] [地址栏] [✕]
```

Tab strip 用 `GeometryReader` 在背景测量可用宽度，动态决定可见 tab 数。

- [ ] **Step 1: 全量替换文件内容**

```swift
// macos/Sources/Features/Workspace/Browser/BrowserPanelToolbar.swift
import SwiftUI
import WebKit

private let minTabWidth: CGFloat = 52
private let maxTabWidth: CGFloat = 110
// 工具栏固定控件区估算宽度：+ (22) + divider (9) + ‹ (22) + › (22) + ↺ (22) + 地址栏 (min 80) + ✕ (22) = ~199
private let fixedControlsWidth: CGFloat = 200

struct BrowserPanelToolbar: View {
    @ObservedObject var manager: BrowserTabManager
    @Binding var currentURL: URL?
    var onClose: () -> Void

    @State private var addressInput: String = ""
    @FocusState private var isEditingAddress: Bool
    @State private var availableTabWidth: CGFloat = 200

    var body: some View {
        HStack(spacing: 0) {
            // ── Tab Strip（弹性）──
            tabStrip
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { availableTabWidth = geo.size.width }
                            .onChange(of: geo.size.width) { availableTabWidth = $0 }
                    }
                )
                .frame(maxWidth: .infinity)

            // ── New Tab Button ──
            Button {
                manager.newTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 28)
            }
            .buttonStyle(.plain)
            .help("New Tab")

            // ── Divider ──
            Divider()
                .frame(height: 14)
                .padding(.horizontal, 4)

            // ── Back ──
            Button { manager.activeTab?.webView.goBack() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(canGoBack ? Color.primary : Color.secondary.opacity(0.4))
                    .frame(width: 22, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!canGoBack)
            .help("Back")

            // ── Forward ──
            Button { manager.activeTab?.webView.goForward() } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(canGoForward ? Color.primary : Color.secondary.opacity(0.4))
                    .frame(width: 22, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!canGoForward)
            .help("Forward")

            // ── Reload ──
            Button { manager.activeTab?.webView.reload() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 22, height: 28)
            }
            .buttonStyle(.plain)
            .help("Reload")

            // ── Address Bar ──
            TextField("Enter URL", text: $addressInput)
                .onSubmit { navigate(to: addressInput) }
                .focused($isEditingAddress)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isEditingAddress ? Color.accentColor : Color.clear, lineWidth: 1)
                )
                .frame(minWidth: 60, maxWidth: .infinity)
                .onChange(of: currentURL) { newURL in
                    if !isEditingAddress {
                        addressInput = newURL?.absoluteString ?? ""
                    }
                }
                .onChange(of: isEditingAddress) { editing in
                    if editing { addressInput = currentURL?.absoluteString ?? "" }
                }
                .onAppear { addressInput = currentURL?.absoluteString ?? "" }

            // ── Close Panel ──
            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 28)
            }
            .buttonStyle(.plain)
            .help("Close Panel")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Tab Strip

    @ViewBuilder
    private var tabStrip: some View {
        let visible = visibleTabs
        let overflow = overflowTabs

        HStack(spacing: 2) {
            ForEach(visible) { tab in
                tabButton(tab: tab)
            }
            if !overflow.isEmpty {
                BrowserTabOverflowMenu(
                    overflowTabs: overflow,
                    activeTabId: manager.activeTabId,
                    onSelect: { manager.focusTab(id: $0) }
                )
            }
        }
        .padding(.leading, 2)
    }

    @ViewBuilder
    private func tabButton(tab: BrowserTab) -> some View {
        let isActive = tab.id == manager.activeTabId
        HStack(spacing: 3) {
            Text(tab.title.isEmpty ? "New Tab" : tab.title)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isActive ? Color.primary : Color.secondary)

            Button {
                manager.closeTab(id: tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Close Tab")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(minWidth: minTabWidth, maxWidth: maxTabWidth)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isActive
                      ? Color(nsColor: .controlBackgroundColor)
                      : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isActive
                                ? Color(nsColor: .separatorColor)
                                : Color.clear,
                                lineWidth: 0.5)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { manager.focusTab(id: tab.id) }
    }

    // MARK: - Overflow computation

    private var maxVisibleCount: Int {
        max(1, Int(availableTabWidth / minTabWidth))
    }

    private var visibleTabs: [BrowserTab] {
        let tabs = manager.tabs
        guard tabs.count > maxVisibleCount else { return tabs }
        // Active tab は常に visible 区域に含める
        var result: [BrowserTab] = []
        var remaining = maxVisibleCount
        // まず active tab を確保
        if let active = manager.activeTab {
            result.append(active)
            remaining -= 1
        }
        // 残りは先頭から（active 以外）
        for tab in tabs {
            guard remaining > 0 else { break }
            if tab.id != manager.activeTabId {
                result.append(tab)
                remaining -= 1
            }
        }
        // 順序を元の tabs 順に並び替え
        return tabs.filter { t in result.contains(where: { $0.id == t.id }) }
    }

    private var overflowTabs: [BrowserTab] {
        let visible = visibleTabs
        return manager.tabs.filter { t in !visible.contains(where: { $0.id == t.id }) }
    }

    // MARK: - Navigation helpers

    private var canGoBack: Bool { manager.activeTab?.webView.canGoBack ?? false }
    private var canGoForward: Bool { manager.activeTab?.webView.canGoForward ?? false }

    private func navigate(to input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let urlString = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: urlString) else { return }
        manager.activeTab?.webView.load(URLRequest(url: url))
    }
}
```

- [ ] **Step 2: 构建验证**

```bash
make check
```

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/Browser/BrowserPanelToolbar.swift
git commit -m "feat(browser): embed compact tab strip into BrowserPanelToolbar"
```

---

## Task 9: BrowserPanelView — 串联 BrowserTabManager

**Files:**
- Modify: `macos/Sources/Features/Workspace/Browser/BrowserPanelView.swift`

- [ ] **Step 1: 全量替换文件内容**

`BrowserPanelView` 现在从 `BrowserSurfaceStore` 取 manager，渲染 active tab 的 WebView，并在顶部放 `BrowserRestoreBanner`。

```swift
// macos/Sources/Features/Workspace/Browser/BrowserPanelView.swift
import SwiftUI
import WebKit

struct BrowserPanelView: View {
    let workspaceId: UUID?
    @ObservedObject var browserStore: BrowserSurfaceStore
    var snapshotsForRestore: [BrowserTabSnapshot]
    var activeSnapshotId: UUID?
    var onClose: () -> Void

    @State private var currentURL: URL? = nil

    var body: some View {
        VStack(spacing: 0) {
            if let wsId = workspaceId {
                let mgr = browserStore.manager(
                    for: wsId,
                    snapshots: snapshotsForRestore.isEmpty ? nil : snapshotsForRestore
                )

                // ── Toolbar with Tab Strip ──
                BrowserPanelToolbar(
                    manager: mgr,
                    currentURL: $currentURL,
                    onClose: onClose
                )

                Divider()

                // ── Restore Banner ──
                if mgr.showRestorePrompt {
                    BrowserRestoreBanner(
                        tabCount: snapshotsForRestore.count,
                        onRestore: {
                            mgr.loadSnapshot(snapshotsForRestore, activeId: activeSnapshotId)
                        },
                        onDismiss: {
                            mgr.showRestorePrompt = false
                            // dismiss 后确保至少有一个空白 tab
                            if mgr.tabs.isEmpty { mgr.newTab() }
                        }
                    )
                    Divider()
                }

                // ── Active WebView ──
                if let activeTab = mgr.activeTab {
                    BrowserWebView(
                        webView: activeTab.webView,
                        currentURL: $currentURL,
                        canGoBack: .constant(activeTab.webView.canGoBack),
                        canGoForward: .constant(activeTab.webView.canGoForward)
                    )
                } else {
                    Spacer()
                }

            } else {
                noWorkspaceView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var noWorkspaceView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "globe")
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No workspace selected")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
```

- [ ] **Step 2: 找到 `BrowserPanelView` 的调用点并更新签名**

搜索调用处：

```bash
grep -rn "BrowserPanelView(" macos/Sources/ --include="*.swift"
```

预期找到 `PolterttyRootView.swift`，将其调用更新为新签名：

```swift
BrowserPanelView(
    workspaceId: workspaceId,
    browserStore: browserStore,
    snapshotsForRestore: workspace?.browserTabSnapshots ?? [],
    activeSnapshotId: workspace?.browserActiveTabId,
    onClose: { browserPanelVisible = false }
)
```

其中 `workspace` 是当前 `WorkspaceModel`（通过 `WorkspaceManager.shared.workspace(for: workspaceId)` 取得）。

- [ ] **Step 3: 找到 Workspace 删除的回调，确认调用 `browserStore.removeManager(for:)`**

```bash
grep -n "removeSurface\|removeManager\|browserStore" macos/Sources/ -r --include="*.swift"
```

若原来调用的是 `browserStore.removeSurface(for: id)`，改为 `browserStore.removeManager(for: id)`。

- [ ] **Step 4: 构建验证**

```bash
make check
```

预期：零编译错误。

- [ ] **Step 5: 冒烟测试**

```bash
make dev
```

打开 App，打开一个 Workspace，按 `⌥⌘B` 打开 Browser Panel，验证：
- 工具栏显示 tab strip（一个 "New Tab" tab）
- 点 `+` 可新建第二个 tab
- 点 tab 上的 `✕` 可关闭
- 切换 Workspace 后 tab 状态独立保留

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Workspace/Browser/BrowserPanelView.swift \
        macos/Sources/Features/Workspace/PolterttyRootView.swift
git commit -m "feat(browser): wire BrowserTabManager into BrowserPanelView"
```

---

## Task 10: Agent API — browser tab 操作接口

**Files:**
- Modify: `macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift`

- [ ] **Step 1: 在 `callTool` switch 中添加四个新 case**

在 `case "show_agent_monitor"` 之前插入：

```swift
        case "browser_new_tab":    return try await callBrowserNewTab(arguments: arguments)
        case "browser_close_tab":  return try await callBrowserCloseTab(arguments: arguments)
        case "browser_focus_tab":  return try await callBrowserFocusTab(arguments: arguments)
        case "browser_list_tabs":  return try await callBrowserListTabs(arguments: arguments)
```

- [ ] **Step 2: 实现四个私有方法**

在文件末尾（`default:` case 之前的最后一个私有方法之后）追加：

```swift
    // MARK: - Browser Tab API

    /// browser_new_tab — 在当前 active workspace 的 Browser Panel 新建 tab。
    /// 参数: workspaceId (optional), url (optional)
    /// 返回: { "tabId": "uuid" }
    private func callBrowserNewTab(arguments: [String: Any]) async throws -> String {
        let tabId: UUID = try await withCheckedThrowingContinuation { cont in
            Task { @MainActor in
                guard let store = Self.browserStore() else {
                    cont.resume(throwing: RPCError(code: -32603, message: "browser_new_tab: browserStore not available"))
                    return
                }
                let wsId = Self.resolveWorkspaceId(arguments)
                let mgr = store.manager(for: wsId)
                let url = (arguments["url"] as? String).flatMap { URL(string: $0) }
                let id = mgr.newTab(url: url)
                cont.resume(returning: id)
            }
        }
        return #"{"tabId":"\#(tabId.uuidString)"}"#
    }

    /// browser_close_tab — 关闭指定 tab。
    /// 参数: tabId (required), workspaceId (optional)
    private func callBrowserCloseTab(arguments: [String: Any]) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            Task { @MainActor in
                guard let tabIdStr = arguments["tabId"] as? String,
                      let tabId = UUID(uuidString: tabIdStr) else {
                    cont.resume(throwing: RPCError(code: -32602, message: "browser_close_tab: missing tabId"))
                    return
                }
                guard let store = Self.browserStore() else {
                    cont.resume(throwing: RPCError(code: -32603, message: "browser_close_tab: browserStore not available"))
                    return
                }
                let wsId = Self.resolveWorkspaceId(arguments)
                store.manager(for: wsId).closeTab(id: tabId)
                cont.resume(returning: #"{"ok":true}"#)
            }
        }
    }

    /// browser_focus_tab — 将指定 tab 设为 active（更新 UI）。
    /// 参数: tabId (required), workspaceId (optional)
    private func callBrowserFocusTab(arguments: [String: Any]) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            Task { @MainActor in
                guard let tabIdStr = arguments["tabId"] as? String,
                      let tabId = UUID(uuidString: tabIdStr) else {
                    cont.resume(throwing: RPCError(code: -32602, message: "browser_focus_tab: missing tabId"))
                    return
                }
                guard let store = Self.browserStore() else {
                    cont.resume(throwing: RPCError(code: -32603, message: "browser_focus_tab: browserStore not available"))
                    return
                }
                let wsId = Self.resolveWorkspaceId(arguments)
                store.manager(for: wsId).focusTab(id: tabId)
                cont.resume(returning: #"{"ok":true}"#)
            }
        }
    }

    /// browser_list_tabs — 列出指定 workspace 的所有 tab。
    /// 参数: workspaceId (optional)
    /// 返回: [{ tabId, title, url, active }]
    private func callBrowserListTabs(arguments: [String: Any]) async throws -> String {
        let result: String = try await withCheckedThrowingContinuation { cont in
            Task { @MainActor in
                guard let store = Self.browserStore() else {
                    cont.resume(throwing: RPCError(code: -32603, message: "browser_list_tabs: browserStore not available"))
                    return
                }
                let wsId = Self.resolveWorkspaceId(arguments)
                let mgr = store.manager(for: wsId)
                let arr: [[String: Any]] = mgr.tabs.map { tab in
                    var d: [String: Any] = [
                        "tabId":  tab.id.uuidString,
                        "title":  tab.title,
                        "active": tab.id == mgr.activeTabId,
                    ]
                    if let url = tab.url { d["url"] = url.absoluteString }
                    return d
                }
                guard let data = try? JSONSerialization.data(withJSONObject: arr),
                      let str = String(data: data, encoding: .utf8) else {
                    cont.resume(throwing: RPCError(code: -32603, message: "browser_list_tabs: serialization failed"))
                    return
                }
                cont.resume(returning: str)
            }
        }
        return result
    }

    // MARK: - Browser helpers

    /// BrowserSurfaceStore を AppDelegate 経由で取得する。
    private static func browserStore() -> BrowserSurfaceStore? {
        (NSApp.delegate as? AppDelegate)?.browserStore
    }

    /// workspaceId 引数があれば使い、なければ active workspace の ID を返す。
    private static func resolveWorkspaceId(_ arguments: [String: Any]) -> UUID {
        if let str = arguments["workspaceId"] as? String, let id = UUID(uuidString: str) {
            return id
        }
        return WorkspaceManager.shared.activeWorkspaceId() ?? UUID()
    }
```

- [ ] **Step 3: 确认 `AppDelegate` 暴露 `browserStore` 属性**

```bash
grep -n "browserStore" macos/Sources/App/macOS/AppDelegate.swift
```

若未暴露，在 `AppDelegate` 中添加：

```swift
var browserStore: BrowserSurfaceStore { /* 取得 PolterttyRootView 中的实例 */ }
```

注意：`browserStore` 实例通常在 `TerminalController` 或环境中持有，根据实际架构选择最短的访问路径（可通过 `EnvironmentValues` 或单例）。若找不到合适路径，改用 `WorkspaceManager.shared` 持有。

- [ ] **Step 4: 确认 `WorkspaceManager` 有 `activeWorkspaceId()` 方法**

```bash
grep -n "activeWorkspaceId" macos/Sources/Features/Workspace/WorkspaceManager.swift
```

若不存在，添加：

```swift
func activeWorkspaceId() -> UUID? {
    activeWindows.first(where: { $0.value.isKeyWindow })?.key
}
```

- [ ] **Step 5: 构建验证**

```bash
make check
```

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift \
        macos/Sources/App/macOS/AppDelegate.swift \
        macos/Sources/Features/Workspace/WorkspaceManager.swift
git commit -m "feat(browser): add browser_new_tab, browser_close_tab, browser_focus_tab, browser_list_tabs to Ctrl API"
```

---

## Task 11: 持久化集成 — 保存 tab 快照

Browser Panel 关闭或 App 退出时，将当前 tab 快照写入 `WorkspaceModel`。

**Files:**
- Modify: `macos/Sources/Features/Workspace/PolterttyRootView.swift`（或持久化保存的调用点）

- [ ] **Step 1: 找到 browserPanelVisible 关闭时的回调**

```bash
grep -n "browserPanelVisible\|saveBrowserPanel\|browserStore" \
  macos/Sources/Features/Workspace/PolterttyRootView.swift
```

- [ ] **Step 2: 在 Browser Panel 关闭时保存快照**

在 `onClose: { browserPanelVisible = false }` 触发处，追加保存逻辑：

```swift
onClose: {
    // 关闭前保存 tab 快照到 WorkspaceModel
    if let wsId = workspaceId,
       let mgr = browserStore.managers[wsId] {
        WorkspaceManager.shared.updateWorkspace(wsId) { ws in
            ws.browserTabSnapshots = mgr.currentSnapshot()
            ws.browserActiveTabId  = mgr.activeTabId
        }
    }
    browserPanelVisible = false
}
```

- [ ] **Step 3: 找到 App 退出时的保存循环，确认 browser 快照也在保存范围内**

```bash
grep -n "saveSnapshot\|browserTabSnapshots\|destroyAllTemporary" \
  macos/Sources/App/macOS/AppDelegate.swift
```

若退出保存循环未包含 browser 快照，在退出保存代码附近追加：

```swift
// 保存每个 Workspace 的 browser tab 快照
for wsId in WorkspaceManager.shared.allWorkspaceIds() {
    if let mgr = browserStore.managers[wsId] {
        WorkspaceManager.shared.updateWorkspace(wsId) { ws in
            ws.browserTabSnapshots = mgr.currentSnapshot()
            ws.browserActiveTabId  = mgr.activeTabId
        }
    }
}
```

- [ ] **Step 4: 构建并验证端到端**

```bash
make dev
```

流程验证：
1. 打开 App，打开 Browser Panel，新建三个 tab 并分别导航到不同 URL
2. 关闭 Browser Panel（或退出 App）
3. 重新打开 Browser Panel → 应出现 "Restore 3 tabs from last session?" banner
4. 点「Restore」→ 三个 tab 出现，URL 正确
5. 重新测试：点「Dismiss」→ banner 消失，只有一个空白 tab，下次打开不再弹 banner

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Workspace/PolterttyRootView.swift \
        macos/Sources/App/macOS/AppDelegate.swift
git commit -m "feat(browser): persist browser tab snapshots on panel close and app exit"
```

---

## Task 12: UI/UX Checklist 验收

对照设计文档中的 UI/UX checklist 逐项目测：

- [ ] Tab strip 与工具栏同行，总高度不变
- [ ] Active tab 有边框 + 背景色，inactive 无背景
- [ ] `✕` 关闭按钮可见（不需要只在 hover 显示，当前方案始终显示）
- [ ] 单 tab 时 `✕` 仍可点击（关闭后回到空白 tab）
- [ ] 关闭 active tab 切换到左侧邻居，最左时切到右侧
- [ ] `+N ▾` 下拉列出所有溢出 tab，active tab 始终在可见区域
- [ ] `+N ▾` 下拉支持键盘（↑↓ / Return / Esc）—— SwiftUI `Menu` 原生支持 ✓
- [ ] Banner 文案英文：`Restore N tabs from last session?` / `Restore` / `Dismiss`
- [ ] 所有 tooltip 英文：`New Tab` / `Close Tab` / `Back` / `Forward` / `Reload` / `Close Panel`
- [ ] `BrowserPanelView` 根视图有 `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)`
- [ ] Workspace 切换后 tab 状态独立（切回来时 tab 不丢失）
- [ ] Workspace 删除时 `removeManager(for:)` 被调用，WebView 释放

```bash
make dev
```

全部通过后最终 commit：

```bash
git add -A
git commit -m "feat(browser): Agent Browser multi-tab support complete"
```

---

## Self-Review Notes

**Spec coverage check:**
- ✅ 数据模型（Task 1, 2）
- ✅ UI 紧凑 tab strip（Task 8）
- ✅ 溢出下拉（Task 6, 8）
- ✅ 恢复 banner（Task 7, 9）
- ✅ 持久化字段（Task 4）
- ✅ Agent API 四个接口（Task 10）
- ✅ 持久化集成（Task 11）

**已知需要在实现时确认的点：**
- `AppDelegate.browserStore` 的访问路径，取决于 `BrowserSurfaceStore` 实例当前在哪里持有（`TerminalController`？全局？）。Task 10 Step 3 有详细说明。
- `BrowserWebView` 的 `canGoBack` / `canGoForward` binding 在 Task 9 中用 `.constant()` 简化，若需要实时更新，参考原始 `BrowserPanelView` 中的 `@State` + coordinator 模式接入 `BrowserTabManager.updateTab(id:title:url:)`。
