# Session 持久化与恢复 (Phase 1.1) 实现规划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有快照机制基础上，新增多快照历史（max 5）、截图预览、启动恢复弹窗缩略图、全局快照管理面板、以及从快照创建 Workspace 功能。

**Architecture:** 引入 `SnapshotStore` 管理每个 Workspace 最多 5 条历史快照（JSON + JPEG），保持 `workspace.json` 向后兼容；`WorkspaceManager.saveSnapshot()` 不改变调用签名，内部集成截图与 SnapshotStore；更新 `RestoreView` 展示缩略图；新增全局 `SnapshotManagerView`；`WorkspaceCreateForm` 新增"从快照创建"入口。

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit (NSBitmapImageRep), Foundation (JSONEncoder/FileManager/URL), Swift Testing (@Test)

---

## 文件变更清单

**新建：**
- `macos/Sources/Features/Workspace/SnapshotStore/SnapshotEntry.swift`
- `macos/Sources/Features/Workspace/SnapshotStore/SnapshotStore.swift`
- `macos/Sources/Features/Workspace/SnapshotCapture.swift`
- `macos/Sources/Features/Workspace/SnapshotManager/SnapshotManagerViewModel.swift`
- `macos/Sources/Features/Workspace/SnapshotManager/SnapshotManagerView.swift`
- `macos/Tests/Workspace/SnapshotStoreTests.swift`

**修改：**
- `macos/Sources/Features/Workspace/WorkspaceManager.swift` — 集成 SnapshotStore，loadSnapshot 优先读 SnapshotStore，添加 rootDir 校验
- `macos/Sources/Features/Workspace/RestoreView.swift` — 每行添加缩略图，点击放大
- `macos/Sources/Features/Workspace/WorkspaceCreateForm.swift` — 添加"从快照创建"区块
- `macos/Sources/App/macOS/AppDelegate.swift` — Workspace 菜单新增"管理快照"，连接 SnapshotManagerView；restoreWorkspaces 添加 rootDir 校验

---

## Task 1: SnapshotEntry 数据模型

**Files:**
- Create: `macos/Sources/Features/Workspace/SnapshotStore/SnapshotEntry.swift`
- Test: `macos/Tests/Workspace/SnapshotStoreTests.swift`

- [ ] **Step 1: 创建 SnapshotEntry.swift**

```swift
// macos/Sources/Features/Workspace/SnapshotStore/SnapshotEntry.swift
import Foundation

/// 单条 Workspace 布局快照，不含 WorkspaceModel（通过 workspaceId 关联）
struct SnapshotEntry: Codable, Identifiable {
    let id: UUID
    let savedAt: Date
    var windowFrame: WindowFrame?
    var sidebarWidth: CGFloat
    var sidebarVisible: Bool
    var tabs: [PersistedTab]?
    var activeTabIndex: Int?

    struct WindowFrame: Codable, Equatable {
        var x, y, width, height: CGFloat

        init(from rect: CGRect) {
            x = rect.origin.x
            y = rect.origin.y
            width = rect.size.width
            height = rect.size.height
        }

        var cgRect: CGRect {
            CGRect(x: x, y: y, width: width, height: height)
        }
    }

    struct PersistedTab: Codable, Equatable {
        let title: String
        let titleLocked: Bool
    }
}
```

- [ ] **Step 2: 写 JSON 往返测试**

创建 `macos/Tests/Workspace/SnapshotStoreTests.swift`（先只写 SnapshotEntry 的测试，后续 Task 2 在同一文件追加）：

```swift
// macos/Tests/Workspace/SnapshotStoreTests.swift
import Testing
import Foundation
@testable import Ghostty

@Suite("SnapshotEntry Tests")
struct SnapshotEntryTests {
    @Test func roundtrip() throws {
        let entry = SnapshotEntry(
            id: UUID(),
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            windowFrame: SnapshotEntry.WindowFrame(from: CGRect(x: 10, y: 20, width: 1200, height: 800)),
            sidebarWidth: 240,
            sidebarVisible: true,
            tabs: [
                SnapshotEntry.PersistedTab(title: "server", titleLocked: true),
                SnapshotEntry.PersistedTab(title: "zsh", titleLocked: false)
            ],
            activeTabIndex: 1
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(entry)
        let decoded = try decoder.decode(SnapshotEntry.self, from: data)

        #expect(decoded.id == entry.id)
        #expect(decoded.sidebarWidth == 240)
        #expect(decoded.sidebarVisible == true)
        #expect(decoded.tabs?.count == 2)
        #expect(decoded.tabs?[0].title == "server")
        #expect(decoded.tabs?[0].titleLocked == true)
        #expect(decoded.activeTabIndex == 1)
        #expect(decoded.windowFrame?.x == 10)
        #expect(decoded.windowFrame?.width == 1200)
    }

    @Test func nilTabsRoundtrip() throws {
        let entry = SnapshotEntry(
            id: UUID(), savedAt: Date(),
            windowFrame: nil, sidebarWidth: 260,
            sidebarVisible: false, tabs: nil, activeTabIndex: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(entry)
        let decoded = try decoder.decode(SnapshotEntry.self, from: data)

        #expect(decoded.tabs == nil)
        #expect(decoded.windowFrame == nil)
    }
}
```

- [ ] **Step 3: 运行测试，确认通过**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty
swift test --filter SnapshotEntryTests 2>&1 | tail -20
```

预期：`Test run with 2 tests passed`

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Workspace/SnapshotStore/SnapshotEntry.swift \
        macos/Tests/Workspace/SnapshotStoreTests.swift
git commit -m "feat(snapshot): add SnapshotEntry data model with tests"
```

---

## Task 2: SnapshotStore（多快照存储，max 5）

**Files:**
- Create: `macos/Sources/Features/Workspace/SnapshotStore/SnapshotStore.swift`
- Test: `macos/Tests/Workspace/SnapshotStoreTests.swift` （追加）

- [ ] **Step 1: 创建 SnapshotStore.swift**

```swift
// macos/Sources/Features/Workspace/SnapshotStore/SnapshotStore.swift
import Foundation

/// 管理单个 Workspace 的历史快照，最多保存 maxCount 条
final class SnapshotStore {
    static let maxCount = 5

    private let snapshotsDir: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fm = FileManager.default

    /// - Parameters:
    ///   - workspaceId: Workspace 的 UUID
    ///   - storageRootURL: WorkspaceManager 的 storageDir（对应 PolterttyConfig.workspaceDir）
    init(workspaceId: UUID, storageRootURL: URL) {
        snapshotsDir = storageRootURL
            .appendingPathComponent(workspaceId.uuidString)
            .appendingPathComponent("snapshots")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Index

    private var indexURL: URL { snapshotsDir.appendingPathComponent("index.json") }

    private func loadIndex() -> [UUID] {
        guard let data = try? Data(contentsOf: indexURL),
              let ids = try? decoder.decode([UUID].self, from: data) else { return [] }
        return ids
    }

    private func saveIndex(_ ids: [UUID]) throws {
        let data = try encoder.encode(ids)
        try data.write(to: indexURL, options: .atomic)
    }

    // MARK: - CRUD

    /// 保存新快照（自动淘汰最旧的超出 maxCount 部分）
    func save(_ entry: SnapshotEntry, screenshot: Data?) throws {
        try fm.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)

        let entryURL = snapshotsDir.appendingPathComponent("\(entry.id.uuidString).json")
        let entryData = try encoder.encode(entry)
        try entryData.write(to: entryURL, options: .atomic)

        if let jpegData = screenshot {
            let screenshotURL = snapshotsDir.appendingPathComponent("\(entry.id.uuidString).jpg")
            try jpegData.write(to: screenshotURL, options: .atomic)
        }

        var ids = loadIndex()
        ids.append(entry.id)
        while ids.count > Self.maxCount {
            let removed = ids.removeFirst()
            deleteFiles(for: removed)
        }
        try saveIndex(ids)
    }

    /// 按时间从旧到新返回所有快照
    func loadAll() -> [SnapshotEntry] {
        loadIndex().compactMap { load(id: $0) }
    }

    /// 返回最新的快照
    func loadLatest() -> SnapshotEntry? {
        loadIndex().last.flatMap { load(id: $0) }
    }

    /// 返回指定 ID 的截图（NSImage）
    func screenshot(for entryId: UUID) -> NSImage? {
        let url = snapshotsDir.appendingPathComponent("\(entryId.uuidString).jpg")
        return NSImage(contentsOf: url)
    }

    /// 删除单条快照及其截图
    func delete(id: UUID) {
        deleteFiles(for: id)
        var ids = loadIndex()
        ids.removeAll { $0 == id }
        try? saveIndex(ids)
    }

    // MARK: - Helpers

    private func load(id: UUID) -> SnapshotEntry? {
        let url = snapshotsDir.appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(SnapshotEntry.self, from: data)
    }

    private func deleteFiles(for id: UUID) {
        try? fm.removeItem(at: snapshotsDir.appendingPathComponent("\(id.uuidString).json"))
        try? fm.removeItem(at: snapshotsDir.appendingPathComponent("\(id.uuidString).jpg"))
    }
}
```

- [ ] **Step 2: 在 SnapshotStoreTests.swift 追加 SnapshotStore 测试**

在文件末尾追加（保留原有 SnapshotEntryTests）：

```swift
@Suite("SnapshotStore Tests")
struct SnapshotStoreTests {
    private func makeTempStore() -> (SnapshotStore, UUID, URL) {
        let workspaceId = UUID()
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let store = SnapshotStore(workspaceId: workspaceId, storageRootURL: tempDir)
        return (store, workspaceId, tempDir)
    }

    private func makeEntry(savedAt: Date = Date()) -> SnapshotEntry {
        SnapshotEntry(
            id: UUID(), savedAt: savedAt,
            windowFrame: SnapshotEntry.WindowFrame(from: CGRect(x: 0, y: 0, width: 800, height: 600)),
            sidebarWidth: 240, sidebarVisible: true,
            tabs: [SnapshotEntry.PersistedTab(title: "zsh", titleLocked: false)],
            activeTabIndex: 0
        )
    }

    @Test func saveAndLoadLatest() throws {
        let (store, _, _) = makeTempStore()
        let entry = makeEntry()
        try store.save(entry, screenshot: nil)

        let loaded = store.loadLatest()
        #expect(loaded?.id == entry.id)
        #expect(loaded?.sidebarWidth == 240)
    }

    @Test func maxCountEnforced() throws {
        let (store, _, _) = makeTempStore()
        var entries: [SnapshotEntry] = []
        for i in 0..<7 {
            let e = makeEntry(savedAt: Date(timeIntervalSince1970: Double(i) * 60))
            entries.append(e)
            try store.save(e, screenshot: nil)
        }

        let all = store.loadAll()
        #expect(all.count == 5)
        // 最新的 5 条（index 2..6）
        #expect(all[0].id == entries[2].id)
        #expect(all[4].id == entries[6].id)
    }

    @Test func deleteEntry() throws {
        let (store, _, _) = makeTempStore()
        let e1 = makeEntry()
        let e2 = makeEntry()
        try store.save(e1, screenshot: nil)
        try store.save(e2, screenshot: nil)

        store.delete(id: e1.id)

        let all = store.loadAll()
        #expect(all.count == 1)
        #expect(all[0].id == e2.id)
    }

    @Test func loadAllOrder() throws {
        let (store, _, _) = makeTempStore()
        let older = makeEntry(savedAt: Date(timeIntervalSince1970: 1000))
        let newer = makeEntry(savedAt: Date(timeIntervalSince1970: 2000))
        try store.save(older, screenshot: nil)
        try store.save(newer, screenshot: nil)

        let all = store.loadAll()
        #expect(all[0].id == older.id)   // 从旧到新
        #expect(all[1].id == newer.id)
    }
}
```

- [ ] **Step 3: 运行测试，确认通过**

```bash
swift test --filter SnapshotStoreTests 2>&1 | tail -20
```

预期：`Test run with 4 tests passed`

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Workspace/SnapshotStore/SnapshotStore.swift \
        macos/Tests/Workspace/SnapshotStoreTests.swift
git commit -m "feat(snapshot): add SnapshotStore with max-5 history and tests"
```

---

## Task 3: SnapshotCapture（截图工具）

**Files:**
- Create: `macos/Sources/Features/Workspace/SnapshotCapture.swift`

- [ ] **Step 1: 创建 SnapshotCapture.swift**

```swift
// macos/Sources/Features/Workspace/SnapshotCapture.swift
import AppKit

/// 捕获 NSWindow 内容区域的 JPEG 截图
enum SnapshotCapture {
    /// 返回 JPEG Data，失败返回 nil（不抛出）
    /// 不需要 Screen Recording 权限（仅捕获自身 App 的 View 层级）
    static func capture(window: NSWindow) -> Data? {
        guard let contentView = window.contentView else { return nil }
        let bounds = contentView.bounds
        guard let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        contentView.cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.6])
    }
}
```

- [ ] **Step 2: 手动验证（构建通过即可）**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep -E "(error:|Build succeeded)"
```

预期：`Build succeeded`

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/SnapshotCapture.swift
git commit -m "feat(snapshot): add SnapshotCapture utility using NSBitmapImageRep"
```

---

## Task 4: WorkspaceManager 集成 SnapshotStore + rootDir 校验

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceManager.swift`

- [ ] **Step 1: 读取 WorkspaceManager.swift（必须先读）**

在 `WorkspaceManager` 顶部找到 `private let storageDir: String` 的位置（约第 20-30 行）和 `saveSnapshot()` / `loadSnapshot()` 方法体。

- [ ] **Step 2: 在 storageDir 属性下添加 URL 便利属性**

在 `private let storageDir: String` 后面追加一行：

```swift
private var storageDirURL: URL { URL(fileURLWithPath: storageDir) }
```

- [ ] **Step 3: 修改 saveSnapshot()，在写 workspace.json 之后追加 SnapshotStore 保存逻辑**

找到 `saveSnapshot()` 方法中 `if let data = try? encoder.encode(snapshot)` 的代码块，在其**之后**（方法末尾，closing `}` 前）追加：

```swift
// 同步写入 SnapshotStore（多历史快照）
let entry = SnapshotEntry(
    id: UUID(),
    savedAt: Date(),
    windowFrame: snapshot.windowFrame.map {
        SnapshotEntry.WindowFrame(from: $0.cgRect)
    },
    sidebarWidth: sidebarWidth,
    sidebarVisible: sidebarVisible,
    tabs: tabs?.map { SnapshotEntry.PersistedTab(title: $0.title, titleLocked: $0.titleLocked) },
    activeTabIndex: activeTabIndex
)
let screenshot = SnapshotCapture.capture(window: window)
let store = SnapshotStore(workspaceId: workspaceId, storageRootURL: storageDirURL)
try? store.save(entry, screenshot: screenshot)
```

> 注意：`WorkspaceSnapshot.WindowFrame` 需有 `cgRect` 计算属性（与 SnapshotEntry.WindowFrame 同结构，若不存在则直接用 `CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)`）。

- [ ] **Step 4: 修改 loadSnapshot()，优先从 SnapshotStore 读取**

将现有 `loadSnapshot()` 方法替换为：

```swift
func loadSnapshot(for workspaceId: UUID) -> WorkspaceSnapshot? {
    guard let workspace = workspace(for: workspaceId) else { return nil }

    // 优先读 SnapshotStore（多历史版本中的最新条目）
    let store = SnapshotStore(workspaceId: workspaceId, storageRootURL: storageDirURL)
    if let entry = store.loadLatest() {
        return WorkspaceSnapshot(
            workspace: workspace,
            windowFrame: entry.windowFrame.map {
                WorkspaceSnapshot.WindowFrame(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
            },
            sidebarWidth: entry.sidebarWidth,
            sidebarVisible: entry.sidebarVisible,
            tabs: entry.tabs?.map {
                WorkspaceSnapshot.PersistedTab(title: $0.title, titleLocked: $0.titleLocked)
            },
            activeTabIndex: entry.activeTabIndex
        )
    }

    // Fallback：读旧版 workspace.json
    let path = snapshotPath(for: workspaceId)
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
    return try? decoder.decode(WorkspaceSnapshot.self, from: data)
}
```

- [ ] **Step 5: 构建确认**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep -E "(error:|Build succeeded)"
```

预期：`Build succeeded`

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceManager.swift
git commit -m "feat(snapshot): integrate SnapshotStore into WorkspaceManager save/load"
```

---

## Task 5: AppDelegate restoreWorkspaces 添加 rootDir 校验

**Files:**
- Modify: `macos/Sources/App/macOS/AppDelegate.swift`

- [ ] **Step 1: 找到 restoreWorkspaces() 方法**

读取 `AppDelegate.swift`，找到 `restoreWorkspaces(_ ids:, replacingWindow:)` 方法中"对每个 workspace ID 获取模型"的代码段（从探索结果得知在行 1028 附近）。

- [ ] **Step 2: 在获取 workspace 模型后添加 rootDir 校验**

在 `guard let workspace = manager.workspace(for: id) else { continue }` 之后（或等效位置）插入：

```swift
// 校验工作目录是否存在
let root = workspace.rootDir
if !root.isEmpty && !FileManager.default.fileExists(atPath: root) {
    let alert = NSAlert()
    alert.messageText = "无法恢复 Workspace"
    alert.informativeText = ""\(workspace.name)" 的工作目录不存在：\(root)"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "跳过")
    alert.runModal()
    continue
}
```

- [ ] **Step 3: 构建确认**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep -E "(error:|Build succeeded)"
```

预期：`Build succeeded`

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/App/macOS/AppDelegate.swift
git commit -m "feat(snapshot): show error alert when rootDir missing on restore"
```

---

## Task 6: RestoreView 添加缩略图

**Files:**
- Modify: `macos/Sources/Features/Workspace/RestoreView.swift`

- [ ] **Step 1: 读取 RestoreView.swift**

先完整读取文件，了解现有 row 结构。

- [ ] **Step 2: 添加截图加载逻辑**

在 `RestoreView` 内添加截图辅助方法，并添加 `@State private var enlargedSnapshot: NSImage? = nil`：

```swift
// 在 RestoreView 的 body 外添加
private func latestScreenshot(for workspace: WorkspaceModel) -> NSImage? {
    guard let storageDir = PolterttyConfig.shared.workspaceDir as String? else { return nil }
    let store = SnapshotStore(
        workspaceId: workspace.id,
        storageRootURL: URL(fileURLWithPath: storageDir)
    )
    guard let latest = store.loadLatest() else { return nil }
    return store.screenshot(for: latest.id)
}
```

- [ ] **Step 3: 在行 View 中添加缩略图和放大 Sheet**

找到当前行的 HStack（显示 checkmark + workspace 名 + 时间戳的 HStack），在**最左侧**插入缩略图：

```swift
// 缩略图（约 80×50 pts）
Group {
    if let img = latestScreenshot(for: workspace) {
        Image(nsImage: img)
            .resizable()
            .scaledToFill()
            .frame(width: 80, height: 50)
            .clipped()
            .cornerRadius(4)
            .onTapGesture { enlargedSnapshot = img }
    } else {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(nsColor: .windowBackgroundColor))
            .frame(width: 80, height: 50)
    }
}
```

在 `RestoreView` 的 `body` 最外层容器上添加 `.sheet`：

```swift
.sheet(item: $enlargedSnapshotItem) { item in
    VStack(spacing: 12) {
        Image(nsImage: item.image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 900, maxHeight: 600)
        Button("关闭") { enlargedSnapshotItem = nil }
    }
    .padding(20)
}
```

为 `.sheet(item:)` 添加包装类型（在 `RestoreView` 外部）：

```swift
private struct SnapshotImageItem: Identifiable {
    let id = UUID()
    let image: NSImage
}
```

并将 `@State private var enlargedSnapshot: NSImage?` 替换为：

```swift
@State private var enlargedSnapshotItem: SnapshotImageItem? = nil
```

`onTapGesture` 改为：

```swift
.onTapGesture { enlargedSnapshotItem = SnapshotImageItem(image: img) }
```

- [ ] **Step 4: 构建确认**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep -E "(error:|Build succeeded)"
```

预期：`Build succeeded`

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Workspace/RestoreView.swift
git commit -m "feat(snapshot): add screenshot thumbnail to RestoreView with tap-to-enlarge"
```

---

## Task 7: SnapshotManagerViewModel

**Files:**
- Create: `macos/Sources/Features/Workspace/SnapshotManager/SnapshotManagerViewModel.swift`

- [ ] **Step 1: 创建 SnapshotManagerViewModel.swift**

```swift
// macos/Sources/Features/Workspace/SnapshotManager/SnapshotManagerViewModel.swift
import Foundation
import AppKit

struct WorkspaceSnapshotGroup: Identifiable {
    let workspace: WorkspaceModel
    var entries: [SnapshotEntry]   // 从新到旧排列
    var id: UUID { workspace.id }
}

@MainActor
final class SnapshotManagerViewModel: ObservableObject {
    @Published var groups: [WorkspaceSnapshotGroup] = []

    private var storageRootURL: URL {
        URL(fileURLWithPath: PolterttyConfig.shared.workspaceDir)
    }

    func load() {
        let manager = WorkspaceManager.shared
        groups = manager.workspaces
            .filter { !$0.isTemporary }
            .compactMap { ws in
                let store = SnapshotStore(workspaceId: ws.id, storageRootURL: storageRootURL)
                let entries = store.loadAll().sorted { $0.savedAt > $1.savedAt }
                guard !entries.isEmpty else { return nil }
                return WorkspaceSnapshotGroup(workspace: ws, entries: entries)
            }
    }

    func screenshot(for entryId: UUID, workspaceId: UUID) -> NSImage? {
        SnapshotStore(workspaceId: workspaceId, storageRootURL: storageRootURL)
            .screenshot(for: entryId)
    }

    func delete(entryId: UUID, workspaceId: UUID) {
        SnapshotStore(workspaceId: workspaceId, storageRootURL: storageRootURL)
            .delete(id: entryId)
        load()
    }

    /// 返回用于"从快照创建"的 SnapshotEntry（传给 WorkspaceCreateForm）
    func entry(id: UUID, workspaceId: UUID) -> SnapshotEntry? {
        SnapshotStore(workspaceId: workspaceId, storageRootURL: storageRootURL)
            .loadAll()
            .first { $0.id == id }
    }
}
```

- [ ] **Step 2: 构建确认**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep -E "(error:|Build succeeded)"
```

预期：`Build succeeded`

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/SnapshotManager/SnapshotManagerViewModel.swift
git commit -m "feat(snapshot): add SnapshotManagerViewModel"
```

---

## Task 8: SnapshotManagerView（全局管理面板）

**Files:**
- Create: `macos/Sources/Features/Workspace/SnapshotManager/SnapshotManagerView.swift`

- [ ] **Step 1: 创建 SnapshotManagerView.swift**

```swift
// macos/Sources/Features/Workspace/SnapshotManager/SnapshotManagerView.swift
import SwiftUI
import AppKit

struct SnapshotManagerView: View {
    @StateObject private var vm = SnapshotManagerViewModel()
    @State private var enlargedItem: EnlargedItem? = nil
    @State private var createFromEntry: SnapshotEntry? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("快照管理")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            if vm.groups.isEmpty {
                Spacer()
                Text("暂无快照")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(vm.groups) { group in
                            workspaceSection(group)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(width: 660, height: 480)
        .onAppear { vm.load() }
        .sheet(item: $enlargedItem) { item in
            enlargedView(item)
        }
        .sheet(item: $createFromEntry) { entry in
            // 复用 WorkspaceCreateForm，传入快照作为初始值
            WorkspaceCreateFormWithSnapshot(snapshotEntry: entry) {
                createFromEntry = nil
            }
        }
    }

    @ViewBuilder
    private func workspaceSection(_ group: WorkspaceSnapshotGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Workspace header
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: group.workspace.colorHex) ?? .blue)
                    .frame(width: 10, height: 10)
                Text(group.workspace.name)
                    .font(.subheadline).fontWeight(.semibold)
                Text("(\(group.entries.count) 条快照)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Snapshot rows
            ForEach(group.entries) { entry in
                snapshotRow(entry, workspaceId: group.workspace.id)
            }
        }
    }

    @ViewBuilder
    private func snapshotRow(_ entry: SnapshotEntry, workspaceId: UUID) -> some View {
        HStack(spacing: 12) {
            // Thumbnail
            thumbnailView(entry: entry, workspaceId: workspaceId)

            // Meta
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.savedAt.formatted(.relative(presentation: .named)))
                    .font(.subheadline)
                Text("\(entry.tabs?.count ?? 0) 个 tab · \(entry.savedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Actions
            Button("从此创建") {
                createFromEntry = entry
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(role: .destructive) {
                vm.delete(entryId: entry.id, workspaceId: workspaceId)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func thumbnailView(entry: SnapshotEntry, workspaceId: UUID) -> some View {
        if let img = vm.screenshot(for: entry.id, workspaceId: workspaceId) {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 60)
                .clipped()
                .cornerRadius(4)
                .onTapGesture { enlargedItem = EnlargedItem(image: img) }
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: 96, height: 60)
        }
    }

    @ViewBuilder
    private func enlargedView(_ item: EnlargedItem) -> some View {
        VStack(spacing: 16) {
            Image(nsImage: item.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 900, maxHeight: 600)
            Button("关闭") { enlargedItem = nil }
        }
        .padding(24)
    }

    struct EnlargedItem: Identifiable {
        let id = UUID()
        let image: NSImage
    }
}

// "从快照创建"的包装 View，预填 rootDir
private struct WorkspaceCreateFormWithSnapshot: View {
    let snapshotEntry: SnapshotEntry
    let onDismiss: () -> Void

    var body: some View {
        WorkspaceCreateForm(
            onSubmit: { name, rootDir, colorHex, description in
                _ = WorkspaceManager.shared.create(
                    name: name,
                    rootDir: rootDir,
                    colorHex: colorHex,
                    description: description
                )
                onDismiss()
            },
            onCancel: onDismiss
        )
    }
}
```

> 注意：`Color(hex:)` 是项目已有的扩展（在 `Helpers/` 中），直接可用。如不存在则替换为 `Color.blue`。

- [ ] **Step 2: 构建确认**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep -E "(error:|Build succeeded)"
```

预期：`Build succeeded`

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/SnapshotManager/SnapshotManagerView.swift
git commit -m "feat(snapshot): add SnapshotManagerView global panel"
```

---

## Task 9: AppDelegate 菜单集成

**Files:**
- Modify: `macos/Sources/App/macOS/AppDelegate.swift`

- [ ] **Step 1: 读取 AppDelegate.swift 中 setupWorkspaceMenu() 方法（约行 1149-1252）**

找到 Workspace 菜单的 `workspaceMenu.addItem(.separator())` 位置（最后一个分隔线的位置）。

- [ ] **Step 2: 在 Workspace 菜单末尾追加"管理快照"菜单项**

在 `setupWorkspaceMenu()` 中，最后一个 `workspaceMenu.addItem(...)` 之后追加：

```swift
workspaceMenu.addItem(.separator())

let manageSnapshots = NSMenuItem(
    title: "管理快照…",
    action: #selector(openSnapshotManager(_:)),
    keyEquivalent: ""
)
workspaceMenu.addItem(manageSnapshots)
```

- [ ] **Step 3: 添加 openSnapshotManager IBAction**

在 AppDelegate 的其他 `@IBAction` 方法附近（如 `newWorkspace` 方法下方）添加：

```swift
@IBAction func openSnapshotManager(_ sender: Any?) {
    if snapshotManagerWindow == nil {
        let view = SnapshotManagerView()
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "快照管理"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 660, height: 480))
        window.center()
        snapshotManagerWindow = window
    }
    snapshotManagerWindow?.makeKeyAndOrderFront(nil)
}
```

- [ ] **Step 4: 在 AppDelegate 的属性区域添加 window 引用**

在 `AppDelegate` 类的属性声明区（与其他 `var xxxWindow: NSWindow?` 同处）添加：

```swift
private var snapshotManagerWindow: NSWindow?
```

- [ ] **Step 5: 构建确认**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep -E "(error:|Build succeeded)"
```

预期：`Build succeeded`

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/App/macOS/AppDelegate.swift
git commit -m "feat(snapshot): add '管理快照' menu item in Workspace menu"
```

---

## Task 10: WorkspaceCreateForm "从快照创建"

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceCreateForm.swift`

- [ ] **Step 1: 读取 WorkspaceCreateForm.swift（完整内容，152 行）**

了解现有 @State 属性列表和 body 结构，找到最后一个表单字段（Color 选择器）下方的位置。

- [ ] **Step 2: 添加 State 属性**

在现有 `@State private var selectedColor` 下方追加：

```swift
@State private var createFromSnapshot = false
@State private var snapshotWorkspaceId: UUID? = nil
@State private var snapshotEntryId: UUID? = nil

private var availableWorkspaces: [WorkspaceModel] {
    WorkspaceManager.shared.workspaces.filter { !$0.isTemporary }
}

private func snapshotEntries(for workspaceId: UUID) -> [SnapshotEntry] {
    let store = SnapshotStore(
        workspaceId: workspaceId,
        storageRootURL: URL(fileURLWithPath: PolterttyConfig.shared.workspaceDir)
    )
    return store.loadAll().sorted { $0.savedAt > $1.savedAt }
}
```

- [ ] **Step 3: 在 Color 选择器下方添加"从快照创建"区块**

找到 Color 选择器对应的 `Section` 或 `HStack` 的 closing brace，在其后追加：

```swift
// 从快照创建
Divider()
    .padding(.vertical, 4)

Toggle("从已有快照创建", isOn: $createFromSnapshot)

if createFromSnapshot {
    if availableWorkspaces.isEmpty {
        Text("暂无可用 Workspace 快照")
            .font(.caption)
            .foregroundStyle(.secondary)
    } else {
        Picker("来源 Workspace", selection: $snapshotWorkspaceId) {
            Text("请选择").tag(UUID?.none)
            ForEach(availableWorkspaces) { ws in
                Text(ws.name).tag(Optional(ws.id))
            }
        }

        if let wsId = snapshotWorkspaceId {
            let entries = snapshotEntries(for: wsId)
            if entries.isEmpty {
                Text("该 Workspace 暂无快照")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("快照", selection: $snapshotEntryId) {
                    Text("请选择").tag(UUID?.none)
                    ForEach(entries) { entry in
                        Text(entry.savedAt.formatted(.relative(presentation: .named)))
                            .tag(Optional(entry.id))
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 4: 修改提交逻辑，选中快照时用其 rootDir 预填**

找到提交按钮的 action（调用 `onSubmit` 的地方），在调用前追加：

```swift
// 如果选择了"从快照创建"，从对应 workspace 复制 rootDir
if createFromSnapshot,
   let wsId = snapshotWorkspaceId,
   let sourceWorkspace = WorkspaceManager.shared.workspace(for: wsId),
   !rootDir.isEmpty == false || rootDir == "~" {
    rootDir = sourceWorkspace.rootDir
}
```

> 注意：`WorkspaceManager.shared.workspace(for:)` 是否存在需确认。如方法名不同（如 `find(id:)` 或直接 `workspaces.first { $0.id == wsId }`），使用对应写法。

- [ ] **Step 5: 构建确认**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep -E "(error:|Build succeeded)"
```

预期：`Build succeeded`

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceCreateForm.swift
git commit -m "feat(snapshot): add '从快照创建' option in WorkspaceCreateForm"
```

---

## 验收检查

完成所有 Task 后，逐项验证：

- [ ] 关闭 App 后重开，启动弹窗出现，列表每行有缩略图
- [ ] 点击缩略图可放大预览
- [ ] 多次关闭同一 Workspace，Workspace 菜单 → 管理快照 → 该 Workspace 最多展示 5 条
- [ ] 快照管理面板：点击"从此创建"弹出 WorkspaceCreateForm
- [ ] 快照管理面板：点击删除按钮后该条消失
- [ ] 新建 Workspace 表单：勾选"从已有快照创建"后出现 Workspace + 快照选择器
- [ ] 恢复时工作目录不存在：弹出警告对话框，该 Workspace 被跳过
- [ ] `swift test --filter SnapshotStoreTests` 全部通过
- [ ] `swift test --filter SnapshotEntryTests` 全部通过
