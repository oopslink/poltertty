# 文件浏览器 UX 优化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复文件浏览器三类体验问题：单击目录展开/折叠抖动、hover 无防抖导致大量重绘、滚动时图标同步阻塞主线程及 `visibleNodes` 无缓存每帧重算。

**Architecture:** 点击修复在视图层（`FileBrowserPanel` + `FileNodeRow`）；hover 防抖在行组件内用 Swift Concurrency Task 实现；图标缓存用 `NSCache` 静态缓存 + 异步加载；`visibleNodes` 改为 `@Published` 存储属性，用 Combine 驱动刷新。

**Tech Stack:** SwiftUI, AppKit, Swift Concurrency (`Task.sleep`), Combine (`$publisher.sink`, `Set<AnyCancellable>`)

---

## File Map

| 文件 | 改动类型 | 内容 |
|------|---------|------|
| `macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift` | 修改 | `onSingleClick` 移除目录 toggleExpand；`onDoubleClick` 对目录执行 toggleExpand |
| `macos/Sources/Features/Workspace/FileBrowser/FileNodeRow.swift` | 修改 | hover 加 50ms 防抖；`FileIconView` 加 `NSCache` + 异步加载 |
| `macos/Sources/Features/Workspace/FileBrowser/FileBrowserViewModel.swift` | 修改 | `visibleNodes` 改为 `@Published` 存储属性；Combine 观察相关属性驱动 `rebuildVisibleNodes()` |
| `macos/Tests/Workspace/FileBrowserViewModelNavigationTests.swift` | 修改 | 新增 `visibleNodes` 缓存行为测试 |

---

## Task 1：修复点击展开/折叠抖动

**Files:**
- Modify: `macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift:590-609`

### 背景

`FileBrowserPanel.nodeRowView` 中，`onSingleClick` 对目录调用了 `toggleExpand`。同时，`FileNodeRow` 的箭头图标也有 `onTapGesture { onToggleExpand() }`。`simultaneousGesture` 不拦截子 view 事件，导致单击时两个 toggle 都触发 → 展开又立刻折叠。

### 修复：`onSingleClick` 移除目录展开逻辑

- [ ] **Step 1：修改 `onSingleClick` 回调**

在 `FileBrowserPanel.swift`，找到 `onSingleClick:` 闭包（约 591-604 行），将其改为：

```swift
onSingleClick: {
    let flags = NSEvent.modifierFlags
    if flags.contains(.command) {
        viewModel.toggleSelection(id: entry.node.id)
    } else if flags.contains(.shift) {
        viewModel.extendSelection(to: entry.node.id)
    } else {
        viewModel.selectNode(id: entry.node.id)
        // 单击只选中，不展开/折叠。展开由箭头点击或双击触发。
    }
    DispatchQueue.main.async { isFocused = true }
},
```

- [ ] **Step 2：修改 `onDoubleClick` 回调，对目录执行展开/折叠**

找到 `onDoubleClick:` 闭包（约 605-609 行），将其改为：

```swift
onDoubleClick: {
    if entry.node.isDirectory {
        viewModel.toggleExpand(nodeId: entry.node.id)
    } else {
        viewModel.openInDefaultApp(entry.node.url)
    }
},
```

- [ ] **Step 3：验证编译通过**

```bash
cd macos && xcodebuild build -scheme Ghostty -configuration Debug -quiet 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4：提交**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift
git commit -m "fix(filebrowser): 单击目录只选中不展开，双击才展开/折叠"
```

---

## Task 2：hover 防抖

**Files:**
- Modify: `macos/Sources/Features/Workspace/FileBrowser/FileNodeRow.swift:35-117`

### 背景

`FileNodeRow.isHovering` 在 `.onHover` 中直接赋值，鼠标扫过 N 行触发 N 次 SwiftUI 重绘。

### 修复：50ms 延迟进入 hover，立即退出

- [ ] **Step 1：添加 `hoverTask` 状态变量**

在 `FileNodeRow` 的 `@State private var isHovering = false` 下方添加：

```swift
@State private var hoverTask: Task<Void, Never>? = nil
```

- [ ] **Step 2：替换 `.onHover` 实现**

找到当前的 `.onHover { hovering in isHovering = hovering }` （约 115-117 行），替换为：

```swift
.onHover { hovering in
    hoverTask?.cancel()
    if hovering {
        hoverTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            guard !Task.isCancelled else { return }
            await MainActor.run { isHovering = true }
        }
    } else {
        isHovering = false
    }
}
```

- [ ] **Step 3：验证编译通过**

```bash
cd macos && xcodebuild build -scheme Ghostty -configuration Debug -quiet 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4：提交**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/FileNodeRow.swift
git commit -m "fix(filebrowser): hover 加 50ms 防抖，减少无效重绘"
```

---

## Task 3：文件图标异步缓存

**Files:**
- Modify: `macos/Sources/Features/Workspace/FileBrowser/FileNodeRow.swift`（`FileIconView` 部分，约 249-269 行）

### 背景

`FileIconView.updateNSView` 每次重绘同步调用 `NSWorkspace.shared.icon(forFile:)`，主线程阻塞；一屏 30 行每帧最多 30 次同步 I/O，是滚动掉帧的主因。

### 修复：静态 NSCache + Task.detached 异步加载

- [ ] **Step 1：替换 `FileIconView` 实现**

找到 `private struct FileIconView: NSViewRepresentable {`（约 249 行），将整个结构体替换为：

```swift
private struct FileIconView: NSViewRepresentable {
    let url: URL

    private static let cache = NSCache<NSURL, NSImage>()

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyDown
        view.imageAlignment = .alignCenter
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        let nsurl = url as NSURL
        if let cached = Self.cache.object(forKey: nsurl) {
            nsView.image = cached
            return
        }
        Task.detached(priority: .utility) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            Self.cache.setObject(icon, forKey: nsurl)
            await MainActor.run { nsView.image = icon }
        }
    }
}
```

- [ ] **Step 2：验证编译通过**

```bash
cd macos && xcodebuild build -scheme Ghostty -configuration Debug -quiet 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3：提交**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/FileNodeRow.swift
git commit -m "perf(filebrowser): 图标加 NSCache 静态缓存 + 异步加载，消除主线程阻塞"
```

---

## Task 4：visibleNodes 改为 @Published 缓存属性

**Files:**
- Modify: `macos/Sources/Features/Workspace/FileBrowser/FileBrowserViewModel.swift`
- Modify: `macos/Tests/Workspace/FileBrowserViewModelNavigationTests.swift`

### 背景

`visibleNodes` 是计算属性，每次 SwiftUI 访问（包括每次 `@Published` 变化触发的 body diff）都全量执行过滤逻辑。改为 `@Published` 存储属性，由 Combine 在相关状态实际变化时驱动刷新。

### TDD

- [ ] **Step 1：先写失败测试**

在 `FileBrowserViewModelNavigationTests.swift` 末尾（`}` 闭合前）添加：

```swift
@Test func testVisibleNodesReflectsFilterTextChange() async throws {
    let dir = try makeTempDir() // creates a.txt, b.txt, c.txt
    let vm = FileBrowserViewModel(rootDir: dir.path)
    defer {
        vm.stop()
        try? FileManager.default.removeItem(at: dir)
    }
    try await Task.sleep(nanoseconds: 200_000_000)

    #expect(vm.visibleNodes.count == 3)

    await MainActor.run { vm.filterText = "a" }
    // 以 @Published 缓存实现：filterText 变化后 visibleNodes 应立即更新
    #expect(vm.visibleNodes.count == 1)
    #expect(vm.visibleNodes.first?.node.name == "a.txt")

    await MainActor.run { vm.filterText = "" }
    #expect(vm.visibleNodes.count == 3)
}

@Test func testVisibleNodesReflectsToggleExpand() async throws {
    // 创建：rootDir/subdir/nested.txt
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    let subdir = tmp.appendingPathComponent("subdir")
    try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: subdir.appendingPathComponent("nested.txt").path, contents: nil)

    let vm = FileBrowserViewModel(rootDir: tmp.path)
    defer {
        vm.stop()
        try? FileManager.default.removeItem(at: tmp)
    }
    try await Task.sleep(nanoseconds: 200_000_000)

    // 初始：只有 subdir（折叠状态）
    #expect(vm.visibleNodes.count == 1)

    // 展开 subdir
    guard let dirNode = vm.visibleNodes.first else {
        Issue.record("Expected subdir node"); return
    }
    vm.toggleExpand(nodeId: dirNode.node.id)

    // 展开后应有 subdir + nested.txt
    #expect(vm.visibleNodes.count == 2)
}
```

- [ ] **Step 2：运行测试，确认失败（当前 visibleNodes 是计算属性，测试中的 filterText 赋值时序可能不可靠）**

```bash
cd macos && xcodebuild test -scheme Ghostty -only-testing:GhosttyTests/FileBrowserViewModelNavigationTests/testVisibleNodesReflectsFilterTextChange -quiet 2>&1 | tail -20
```

Expected: 测试失败或行为不确定。

- [ ] **Step 3：添加 `import Combine` 和 `cancellables` 存储**

在 `FileBrowserViewModel.swift` 顶部的 `import AppKit` 下方添加：

```swift
import Combine
```

在 `// MARK: - Internal State` 区域，在 `private var monitor: FileSystemMonitor?` 下方添加：

```swift
private var cancellables = Set<AnyCancellable>()
```

- [ ] **Step 4：将 `visibleNodes` 改为 `@Published` 存储属性**

找到当前的 `var visibleNodes: [(node: FileNode, depth: Int)] {`（约 203 行），将整个计算属性（含 `}` 约 218 行）替换为：

```swift
@Published private(set) var visibleNodes: [(node: FileNode, depth: Int)] = []
```

- [ ] **Step 5：新增 `rebuildVisibleNodes()` 方法**

在 `var visibleNodes` 声明下方（即新的一行存储属性后），在 `// MARK: - Hidden Files Toggle` 上方插入：

```swift
// MARK: - Visible Nodes Cache

private func computeVisibleNodes() -> [(node: FileNode, depth: Int)] {
    var result: [(FileNode, Int)] = []
    let baseNodes: [FileNode]
    if let focusURL = focusedRootURL,
       let focusNode = findNodeByURL(url: focusURL, in: rootNodes),
       let children = focusNode.children {
        baseNodes = children
    } else {
        baseNodes = rootNodes
    }
    let source = filterText.isEmpty && activeExtensions.isEmpty && activeGitStatuses.isEmpty
        ? baseNodes
        : filterTree(nodes: baseNodes, query: filterText.lowercased())
    collectVisible(from: source, depth: 0, into: &result)
    return result
}

private func rebuildVisibleNodes() {
    visibleNodes = computeVisibleNodes()
}
```

- [ ] **Step 6：在 `init` 末尾设置 Combine 观察**

找到 `init(rootDir:isVisible:panelWidth:)` 的末尾 `}`，在 `monitor?.start()` 和 `reload()` 调用之前插入：

```swift
// 观察所有影响可见节点的 @Published 属性，驱动 visibleNodes 缓存刷新
Publishers.MergeMany(
    $rootNodes.map { _ in () }.eraseToAnyPublisher(),
    $filterText.map { _ in () }.eraseToAnyPublisher(),
    $activeExtensions.map { _ in () }.eraseToAnyPublisher(),
    $activeGitStatuses.map { _ in () }.eraseToAnyPublisher(),
    $focusedRootURL.map { _ in () }.eraseToAnyPublisher(),
    $gitStatuses.map { _ in () }.eraseToAnyPublisher()
)
.receive(on: DispatchQueue.main)
.sink { [weak self] in self?.rebuildVisibleNodes() }
.store(in: &cancellables)
```

完整 `init` 应如下：

```swift
init(rootDir: String, isVisible: Bool = false, panelWidth: CGFloat = 260) {
    self.rootDir = rootDir
    self.isVisible = isVisible
    self.panelWidth = panelWidth

    // Combine 观察必须在 reload() 之前建立，确保首次加载也能刷新 visibleNodes
    Publishers.MergeMany(
        $rootNodes.map { _ in () }.eraseToAnyPublisher(),
        $filterText.map { _ in () }.eraseToAnyPublisher(),
        $activeExtensions.map { _ in () }.eraseToAnyPublisher(),
        $activeGitStatuses.map { _ in () }.eraseToAnyPublisher(),
        $focusedRootURL.map { _ in () }.eraseToAnyPublisher(),
        $gitStatuses.map { _ in () }.eraseToAnyPublisher()
    )
    .receive(on: DispatchQueue.main)
    .sink { [weak self] in self?.rebuildVisibleNodes() }
    .store(in: &cancellables)

    guard !rootDir.isEmpty, FileManager.default.fileExists(atPath: rootDir) else { return }
    setupMonitor()
    reload()
}
```

- [ ] **Step 7：验证编译通过**

```bash
cd macos && xcodebuild build -scheme Ghostty -configuration Debug -quiet 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

如果出现编译错误，最常见原因是某处调用了 `visibleNodes` 的旧计算属性语义（不应有）。确认所有调用处只是读取属性即可，无需改动。

- [ ] **Step 8：运行所有文件浏览器 ViewModel 测试**

```bash
cd macos && xcodebuild test -scheme Ghostty -only-testing:GhosttyTests/FileBrowserViewModelNavigationTests -quiet 2>&1 | tail -30
```

Expected: 所有测试 PASS，包括新增的两个测试。

如果 `testVisibleNodesReflectsFilterTextChange` 仍然失败，原因是 `$filterText` 的 Combine sink 在同一 RunLoop tick 内没有立即更新 `visibleNodes`。解法：在测试中的 `vm.filterText = "a"` 后添加：
```swift
try await Task.sleep(nanoseconds: 10_000_000) // 10ms，等 Combine sink 在 main queue 触发
```

- [ ] **Step 9：提交**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/FileBrowserViewModel.swift
git add macos/Tests/Workspace/FileBrowserViewModelNavigationTests.swift
git commit -m "perf(filebrowser): visibleNodes 改为 @Published 缓存属性，Combine 驱动刷新"
```

---

## Self-Review

**Spec coverage check:**

| Spec 要求 | 覆盖任务 |
|----------|---------|
| 单击目录只选中不展开 | Task 1 Step 1 |
| 双击目录展开/折叠 | Task 1 Step 2 |
| hover 50ms 防抖 | Task 2 |
| hover 离开立即清除高亮 | Task 2（`isHovering = false` 无延迟） |
| 图标 NSCache 静态缓存 | Task 3 |
| 图标异步加载不阻塞主线程 | Task 3（`Task.detached`） |
| visibleNodes 改为 @Published 存储属性 | Task 4 Step 4 |
| Combine 驱动刷新（6 个属性） | Task 4 Step 6 |

**Placeholder scan:** 无 TBD / TODO。

**Type consistency:**
- `rebuildVisibleNodes()` — Task 4 Step 5 定义，Step 6 在 Combine sink 中调用 ✓
- `computeVisibleNodes()` — Task 4 Step 5 定义，`rebuildVisibleNodes()` 内调用 ✓
- `visibleNodes: [(node: FileNode, depth: Int)]` — Task 4 Step 4 改为存储属性，所有调用处（`extendSelection`、`selectAll`、`selectNext`、`selectPrevious`）只读取，无需修改 ✓
- `cancellables: Set<AnyCancellable>` — Task 4 Step 3 声明，Step 6 `.store(in:)` 使用 ✓
