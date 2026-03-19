# FileBrowser 批量操作实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 FileBrowser 添加批量选择（Cmd/Shift+Click）、批量删除（确认 Alert）、批量移动（拖拽 + NSOpenPanel）能力。

**Architecture:** 将 `FileBrowserViewModel` 的单选状态 `selectedNodeId: UUID?` 改为多选 `selectedNodeIds: Set<UUID>` + 确定性主选 `lastSelectedId: UUID?`；点击手势通过 `NSApp.currentEvent?.modifierFlags` 读取修饰键；拖拽和 NSOpenPanel 在 `FileNodeRow`/`FileBrowserPanel` 中实现。

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing framework（`@Test`/`#expect`），Xcode 15+，`make check`（类型检查），`make dev`（增量构建）

**规则:** 所有特性开发必须在 git worktree 中进行（`.worktrees/` 目录），完成后通过 Pull Request 合并。

---

## 文件结构

| 文件 | 操作 | 职责 |
|------|------|------|
| `macos/Sources/Features/Workspace/FileBrowser/FileBrowserViewModel.swift` | 修改 | 多选状态、选择方法、reload 恢复、键盘导航、批量删除/移动 |
| `macos/Sources/Features/Workspace/FileBrowser/FileNodeRow.swift` | 修改 | 右键菜单多选适配、draggable 支持 |
| `macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift` | 修改 | 点击修饰键感知、Cmd+A、批量删除 Alert、NSOpenPanel、dropDestination、选中计数标签 |
| `macos/Tests/Workspace/FileBrowserViewModelNavigationTests.swift` | 修改 | 修复已有测试中的 `selectedNodeId` 引用，新增批量选择测试 |

---

## Task 1：创建 git worktree

**Files:**
- 工作目录：`.worktrees/filebrowser-batch-ops`

- [ ] **Step 1: 创建 feature branch 和 worktree**

```bash
git worktree add .worktrees/filebrowser-batch-ops -b feat/filebrowser-batch-ops
```

- [ ] **Step 2: 进入 worktree，验证状态**

```bash
cd .worktrees/filebrowser-batch-ops
git status
```

预期输出：`On branch feat/filebrowser-batch-ops, nothing to commit`

---

## Task 2：修复已有测试（先让测试处于已知状态）

**Files:**
- Modify: `macos/Tests/Workspace/FileBrowserViewModelNavigationTests.swift`

> **背景：** 现有测试直接访问 `selectedNodeId`，下一步会将该属性改名为 `selectedNodeIds`（Set）+ `lastSelectedId`。先将已有测试改为使用新 API，让它们在 Task 3 实现后能通过。

- [ ] **Step 1: 理解现有测试结构**

阅读 `macos/Tests/Workspace/FileBrowserViewModelNavigationTests.swift`。共 6 个测试，均测试 `selectNext()`/`selectPrevious()` 的导航行为，使用 `vm.selectedNodeId` 作为断言目标。

- [ ] **Step 2: 更新所有测试使用新 API**

将所有 `vm.selectedNodeId = nodes[n].node.id` 替换为 `vm.selectNode(id: nodes[n].node.id)`，将所有 `#expect(vm.selectedNodeId == ...)` 替换为 `#expect(vm.lastSelectedId == ...)`，将 `vm.selectedNodeId = nil` 替换为 `vm.clearSelection()`：

```swift
// macos/Tests/Workspace/FileBrowserViewModelNavigationTests.swift
import Testing
import Foundation
@testable import Ghostty

struct FileBrowserViewModelNavigationTests {

    private func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        for name in ["a.txt", "b.txt", "c.txt"] {
            FileManager.default.createFile(atPath: tmp.appendingPathComponent(name).path, contents: nil)
        }
        return tmp
    }

    @Test func testSelectNextMovesSelectionDown() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer { vm.stop(); try? FileManager.default.removeItem(at: dir) }
        try await Task.sleep(nanoseconds: 200_000_000)

        let nodes = vm.visibleNodes
        guard nodes.count >= 2 else { Issue.record("Expected at least 2 nodes"); return }

        vm.selectNode(id: nodes[0].node.id)
        vm.selectNext()
        #expect(vm.lastSelectedId == nodes[1].node.id)
    }

    @Test func testSelectPreviousMovesSelectionUp() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer { vm.stop(); try? FileManager.default.removeItem(at: dir) }
        try await Task.sleep(nanoseconds: 200_000_000)

        let nodes = vm.visibleNodes
        guard nodes.count >= 2 else { Issue.record("Expected at least 2 nodes"); return }

        vm.selectNode(id: nodes[1].node.id)
        vm.selectPrevious()
        #expect(vm.lastSelectedId == nodes[0].node.id)
    }

    @Test func testSelectNextClampsAtBottom() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer { vm.stop(); try? FileManager.default.removeItem(at: dir) }
        try await Task.sleep(nanoseconds: 200_000_000)

        let nodes = vm.visibleNodes
        guard let last = nodes.last else { Issue.record("Expected at least 1 node"); return }

        vm.selectNode(id: last.node.id)
        vm.selectNext()
        #expect(vm.lastSelectedId == last.node.id)
    }

    @Test func testSelectPreviousClampsAtTop() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer { vm.stop(); try? FileManager.default.removeItem(at: dir) }
        try await Task.sleep(nanoseconds: 200_000_000)

        let nodes = vm.visibleNodes
        guard let first = nodes.first else { Issue.record("Expected at least 1 node"); return }

        vm.selectNode(id: first.node.id)
        vm.selectPrevious()
        #expect(vm.lastSelectedId == first.node.id)
    }

    @Test func testSelectNextWithNoSelectionSelectsFirst() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer { vm.stop(); try? FileManager.default.removeItem(at: dir) }
        try await Task.sleep(nanoseconds: 200_000_000)

        let nodes = vm.visibleNodes
        guard let first = nodes.first else { Issue.record("Expected at least 1 node"); return }

        vm.clearSelection()
        vm.selectNext()
        #expect(vm.lastSelectedId == first.node.id)
    }

    @Test func testSelectPreviousWithNoSelectionSelectsFirst() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer { vm.stop(); try? FileManager.default.removeItem(at: dir) }
        try await Task.sleep(nanoseconds: 200_000_000)

        let nodes = vm.visibleNodes
        guard let first = nodes.first else { Issue.record("Expected at least 1 node"); return }

        vm.clearSelection()
        vm.selectPrevious()
        #expect(vm.lastSelectedId == first.node.id)
    }
}
```

- [ ] **Step 3: 确认类型检查失败（预期，因为 API 还不存在）**

```bash
make check 2>&1 | grep "error:" | head -20
```

预期：编译错误，`value of type 'FileBrowserViewModel' has no member 'selectNode'` 等。

- [ ] **Step 4: Commit 测试（红灯状态）**

```bash
git add macos/Tests/Workspace/FileBrowserViewModelNavigationTests.swift
git commit -m "test: update navigation tests to use new multi-selection API (red)"
```

---

## Task 3：实现 FileBrowserViewModel 多选状态

**Files:**
- Modify: `macos/Sources/Features/Workspace/FileBrowser/FileBrowserViewModel.swift`

- [ ] **Step 1: 替换选择状态属性**

在 `// MARK: - Published State` 区域，将：

```swift
@Published var selectedNodeId: UUID? = nil
```

替换为：

```swift
@Published var selectedNodeIds: Set<UUID> = []
@Published private(set) var lastSelectedId: UUID? = nil   // @Published 保证预览面板 SwiftUI 响应性

/// 兼容预览面板：返回最后一次明确选中的节点 ID
var primarySelectedId: UUID? { lastSelectedId }
```

- [ ] **Step 2: 更新 selectNode 方法（原有方法改写）**

将原有的 `func selectNode(id: UUID?)` 方法替换为以下实现：

```swift
// MARK: - Selection

func selectNode(id: UUID?) {
    if let id {
        selectedNodeIds = [id]
        lastSelectedId = id
        let node = findNodeInTree(id: id, nodes: rootNodes)
        if let node, !node.isDirectory {
            showPreviewPanel = true
        } else {
            showPreviewPanel = false
            isPreviewFullscreen = false
        }
    } else {
        clearSelection()
    }
}

func toggleSelection(id: UUID) {
    if selectedNodeIds.contains(id) {
        selectedNodeIds.remove(id)
        if lastSelectedId == id {
            lastSelectedId = nil   // Set 无序，不用 .first 避免不确定性；nil 表示"无主选"
        }
    } else {
        selectedNodeIds.insert(id)
        lastSelectedId = id
    }
    // 多选时关闭预览面板
    if selectedNodeIds.count != 1 {
        showPreviewPanel = false
        isPreviewFullscreen = false
    }
}

func extendSelection(to targetId: UUID) {
    guard let anchorId = lastSelectedId else {
        selectNode(id: targetId)
        return
    }
    let nodes = visibleNodes
    guard let anchorIdx = nodes.firstIndex(where: { $0.node.id == anchorId }),
          let targetIdx = nodes.firstIndex(where: { $0.node.id == targetId }) else { return }
    let range = min(anchorIdx, targetIdx)...max(anchorIdx, targetIdx)
    let rangeIds = Set(nodes[range].map { $0.node.id })
    selectedNodeIds = rangeIds
    lastSelectedId = targetId
    showPreviewPanel = false
    isPreviewFullscreen = false
}

func clearSelection() {
    selectedNodeIds = []
    lastSelectedId = nil
    showPreviewPanel = false
    isPreviewFullscreen = false
}

func selectAll() {
    let nodes = visibleNodes
    selectedNodeIds = Set(nodes.map { $0.node.id })
    lastSelectedId = nodes.last?.node.id
    showPreviewPanel = false
    isPreviewFullscreen = false
}
```

- [ ] **Step 3: 更新 reload() 的多选状态恢复**

在 `reload()` 方法中，将：

```swift
// Preserve selected file URL across reload
let selectedURL = self.selectedNodeId.flatMap { self.findNodeURL(id: $0) }
```

替换为：

```swift
// Preserve multi-selection URLs across reload
let selectedURLs = self.selectedNodeIds.compactMap { self.findNodeURL(id: $0) }
let lastSelectedURL = self.lastSelectedId.flatMap { self.findNodeURL(id: $0) }
```

同时将：

```swift
// Restore selection by URL
if let url = selectedURL, let newNode = self.findNodeByURL(url: url, in: self.rootNodes) {
    self.selectedNodeId = newNode.id
} else if selectedURL != nil {
    // Selected file was deleted
    self.selectedNodeId = nil
    self.showPreviewPanel = false
}
```

替换为：

```swift
// Restore multi-selection by URL
var newIds = Set<UUID>()
for url in selectedURLs {
    if let node = self.findNodeByURL(url: url, in: self.rootNodes) {
        newIds.insert(node.id)
    }
}
self.selectedNodeIds = newIds

// Restore lastSelectedId
if let url = lastSelectedURL, let node = self.findNodeByURL(url: url, in: self.rootNodes) {
    self.lastSelectedId = node.id
} else {
    self.lastSelectedId = nil
    self.showPreviewPanel = false
}
```

- [ ] **Step 4: 更新键盘导航方法**

将 `selectNext()` 和 `selectPrevious()` 改为使用新 API（多选时清空后单选移动，与 Finder 行为一致）：

```swift
func selectNext() {
    let nodes = visibleNodes
    guard !nodes.isEmpty else { return }
    if let id = lastSelectedId,
       let idx = nodes.firstIndex(where: { $0.node.id == id }) {
        selectNode(id: nodes[min(idx + 1, nodes.count - 1)].node.id)
    } else {
        selectNode(id: nodes[0].node.id)
    }
}

func selectPrevious() {
    let nodes = visibleNodes
    guard !nodes.isEmpty else { return }
    if let id = lastSelectedId,
       let idx = nodes.firstIndex(where: { $0.node.id == id }) {
        selectNode(id: nodes[max(idx - 1, 0)].node.id)
    } else {
        selectNode(id: nodes[0].node.id)
    }
}
```

- [ ] **Step 5: 更新 findNodeURL 方法**

将：

```swift
func findNodeURL(id: UUID) -> URL? {
    findNodeInTree(id: id, nodes: rootNodes)?.url
}
```

保持不变（签名已兼容）。

- [ ] **Step 6: 添加批量操作方法**

在 `// MARK: - File Operations` 区域末尾追加：

```swift
/// 批量删除选中项，返回无法删除的文件名列表（供 UI 层汇总展示）
@discardableResult
func deleteSelected() -> [String] {
    let urls = selectedNodeIds.compactMap { findNodeURL(id: $0) }
    var errors: [String] = []
    for url in urls {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            errors.append(url.lastPathComponent)
        }
    }
    clearSelection()
    return errors
}

/// 批量移动，前置校验子目录和写权限，返回无法移动的文件名列表
@discardableResult
func move(urls: [URL], to destination: URL) -> [String] {
    // 校验：目标不能是被移动目录的子路径
    for url in urls where url.hasDirectoryPath {
        if destination.path.hasPrefix(url.path + "/") || destination.path == url.path {
            return ["目标路径不合法：不能移动到自身子目录"]
        }
    }
    // 校验：目标目录可写
    guard FileManager.default.isWritableFile(atPath: destination.path) else {
        return ["目标目录无写入权限"]
    }

    var errors: [String] = []
    for url in urls {
        let target = destination.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.moveItem(at: url, to: target)
        } catch {
            errors.append(url.lastPathComponent)
        }
    }
    clearSelection()
    return errors
}
```

- [ ] **Step 7: 编译检查**

```bash
make check 2>&1 | grep "error:" | head -30
```

预期：无编译错误（或仅有 `FileBrowserPanel`/`FileNodeRow` 中旧引用 `selectedNodeId` 的错误，Task 4/5 会修复）。

- [ ] **Step 8: Commit**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/FileBrowserViewModel.swift
git commit -m "feat(filebrowser): 多选状态 Set<UUID> + lastSelectedId，新增选择方法和批量移动"
```

---

## Task 4：运行测试，修复编译错误

**Files:**
- Modify: `macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift`（临时修复 `selectedNodeId` 引用）

> `FileBrowserPanel.swift` 中还有 `selectedNodeId` 的引用会导致编译失败，在 Task 5 完整重写之前先做最小化修复让测试能跑起来。

- [ ] **Step 1: 确认编译错误位置**

```bash
make check 2>&1 | grep "error:" | grep -v "FileBrowserPanel"
```

- [ ] **Step 2: 在 FileBrowserPanel 中修复所有旧引用（三种模式分别处理）**

在 `FileBrowserPanel.swift` 中做以下替换：

**模式 A：读取用途**（`let nodeId = viewModel.selectedNodeId`，`if let nodeId = viewModel.selectedNodeId` 等）
→ 替换为 `viewModel.lastSelectedId`

**模式 B：赋值 nil 用途**（`viewModel.selectedNodeId = nil`）
→ 替换为 `viewModel.clearSelection()`（⚠️ 不能写 `viewModel.lastSelectedId = nil`，因为 `lastSelectedId` 是 `@Published private(set)`，外部不可写）

**模式 C：isSelected 判断**（`isSelected: viewModel.selectedNodeId == entry.node.id`）
→ 替换为 `isSelected: viewModel.selectedNodeIds.contains(entry.node.id)`

**模式 D：`.onChange` 监听**（`.onChange(of: viewModel.selectedNodeId)`）
→ 替换为 `.onChange(of: viewModel.lastSelectedId)`（`lastSelectedId` 是 `@Published`，可被 SwiftUI 监听）

- [ ] **Step 3: 编译检查通过**

```bash
make check 2>&1 | grep "error:"
```

预期：无输出（零错误）。

- [ ] **Step 4: Commit 临时修复**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift
git commit -m "fix(filebrowser): 临时修复 FileBrowserPanel 中 selectedNodeId 引用"
```

---

## Task 5：新增批量选择测试（绿灯验证）

**Files:**
- Modify: `macos/Tests/Workspace/FileBrowserViewModelNavigationTests.swift`

- [ ] **Step 1: 确认现有 6 个测试通过**

```bash
xcodebuild test -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -testPlan GhosttyTests -only-testing:"GhosttyTests/FileBrowserViewModelNavigationTests" \
  2>&1 | tail -20
```

预期：`Test Suite 'FileBrowserViewModelNavigationTests' passed`（6 tests）

如果 xcodebuild test 命令失败，改用：
```bash
make check
```
（确认无编译错误即可，集成测试运行需要模拟器/真实设备环境）

- [ ] **Step 2: 追加批量选择测试**

在 `FileBrowserViewModelNavigationTests.swift` 的 `}` 结束符前追加：

```swift
    // MARK: - 批量选择测试

    @Test func testToggleSelectionAddsAndRemoves() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer { vm.stop(); try? FileManager.default.removeItem(at: dir) }
        try await Task.sleep(nanoseconds: 200_000_000)

        let nodes = vm.visibleNodes
        guard nodes.count >= 2 else { Issue.record("Expected at least 2 nodes"); return }

        let id0 = nodes[0].node.id
        let id1 = nodes[1].node.id

        vm.selectNode(id: id0)
        #expect(vm.selectedNodeIds.count == 1)

        vm.toggleSelection(id: id1)
        #expect(vm.selectedNodeIds.count == 2)
        #expect(vm.selectedNodeIds.contains(id0))
        #expect(vm.selectedNodeIds.contains(id1))
        #expect(vm.lastSelectedId == id1)

        vm.toggleSelection(id: id0)
        #expect(vm.selectedNodeIds.count == 1)
        #expect(!vm.selectedNodeIds.contains(id0))
    }

    @Test func testExtendSelectionSelectsRange() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer { vm.stop(); try? FileManager.default.removeItem(at: dir) }
        try await Task.sleep(nanoseconds: 200_000_000)

        let nodes = vm.visibleNodes
        guard nodes.count >= 3 else { Issue.record("Expected at least 3 nodes"); return }

        vm.selectNode(id: nodes[0].node.id)
        vm.extendSelection(to: nodes[2].node.id)
        #expect(vm.selectedNodeIds.count == 3)
        #expect(vm.lastSelectedId == nodes[2].node.id)
    }

    @Test func testSelectAllSelectsAllVisibleNodes() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer { vm.stop(); try? FileManager.default.removeItem(at: dir) }
        try await Task.sleep(nanoseconds: 200_000_000)

        let nodes = vm.visibleNodes
        guard !nodes.isEmpty else { Issue.record("Expected at least 1 node"); return }

        vm.selectAll()
        #expect(vm.selectedNodeIds.count == nodes.count)
    }

    @Test func testClearSelectionClearsAll() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer { vm.stop(); try? FileManager.default.removeItem(at: dir) }
        try await Task.sleep(nanoseconds: 200_000_000)

        let nodes = vm.visibleNodes
        guard !nodes.isEmpty else { Issue.record("Expected at least 1 node"); return }

        vm.selectAll()
        vm.clearSelection()
        #expect(vm.selectedNodeIds.isEmpty)
        #expect(vm.lastSelectedId == nil)
    }

    @Test func testSelectNextClearsMultiSelection() async throws {
        let dir = try makeTempDir()
        let vm = FileBrowserViewModel(rootDir: dir.path)
        defer { vm.stop(); try? FileManager.default.removeItem(at: dir) }
        try await Task.sleep(nanoseconds: 200_000_000)

        let nodes = vm.visibleNodes
        guard nodes.count >= 2 else { Issue.record("Expected at least 2 nodes"); return }

        vm.selectAll()
        #expect(vm.selectedNodeIds.count > 1)

        vm.selectNode(id: nodes[0].node.id)
        vm.selectNext()
        // 方向键后应清空多选，只剩一个
        #expect(vm.selectedNodeIds.count == 1)
        #expect(vm.lastSelectedId == nodes[1].node.id)
    }
```

- [ ] **Step 3: 编译检查**

```bash
make check 2>&1 | grep "error:"
```

预期：无错误。

- [ ] **Step 4: Commit 新测试**

```bash
git add macos/Tests/Workspace/FileBrowserViewModelNavigationTests.swift
git commit -m "test(filebrowser): 新增批量选择测试（toggleSelection/extendSelection/selectAll/clearSelection）"
```

---

## Task 6：更新 FileNodeRow — 右键菜单多选适配 + 拖拽

**Files:**
- Modify: `macos/Sources/Features/Workspace/FileBrowser/FileNodeRow.swift`

- [ ] **Step 1: 添加多选状态参数和拖拽回调**

在 `FileNodeRow` struct 的属性列表中添加：

```swift
let isMultiSelected: Bool           // 是否有多个节点被选中（影响右键菜单）
let selectedCount: Int              // 当前选中数量
let selectedURLs: [URL]            // 所有选中节点的 URL（用于拖拽载荷）
let onMoveSelected: (() -> Void)?   // 触发"移动到…"面板
```

- [ ] **Step 2: 更新 contextMenu**

将 `contextMenu` 替换为多选适配版本：

```swift
.contextMenu {
    if isMultiSelected {
        // 多选菜单
        Button("删除 \(selectedCount) 个项目…", role: .destructive) { onDelete() }
        Button("移动到…") { onMoveSelected?() }
    } else {
        // 单选菜单（保持原有）
        Button("Open in Terminal") { onOpenInTerminal() }
        Button("Copy Path") { onCopyPath() }
        Divider()
        Button("New File") { onNewFile() }
        Button("New Directory") { onNewDirectory() }
        Divider()
        Button("Rename") { onStartRename() }
        Button("Delete", role: .destructive) { onDelete() }
    }
}
```

- [ ] **Step 3: 添加 draggable 修饰符（支持多文件载荷）**

在 `.contentShape(Rectangle())` 之后、`.onHover` 之前添加拖拽支持。

SwiftUI 的 `.draggable` 只支持单个 item，需通过 `.onDrag` + `NSItemProvider` 实现多文件拖拽：

```swift
.onDrag {
    // 多选拖拽：载荷为所有选中 URL；单选/未选：只拖当前行
    let urls: [URL] = (isMultiSelected && selectedURLs.contains(node.url))
        ? selectedURLs
        : [node.url]
    // NSItemProvider 支持多个文件 URL（macOS 原生文件拖拽协议）
    let provider = NSItemProvider()
    for url in urls {
        provider.registerFileRepresentation(
            forTypeIdentifier: "public.file-url",
            fileOptions: [],
            visibility: .all
        ) { completion in
            completion(url, false, nil)
            return nil
        }
    }
    return provider
} preview: {
    if isMultiSelected && selectedCount > 1 {
        Label("\(selectedCount) 个项目", systemImage: "doc.on.doc")
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))
            .cornerRadius(6)
    } else {
        Label(node.name, systemImage: node.isDirectory ? "folder" : "doc")
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))
            .cornerRadius(6)
    }
}
```

> **注意：** `.onDrag` 的 preview 闭包在 macOS 14+ 可用；若编译目标低于 macOS 14，拖拽预览将使用系统默认样式（可接受）。

- [ ] **Step 4: 编译检查**

```bash
make check 2>&1 | grep "error:"
```

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/FileNodeRow.swift
git commit -m "feat(filebrowser): FileNodeRow 多选右键菜单 + draggable 支持"
```

---

## Task 7：更新 FileBrowserPanel — 完整多选交互

**Files:**
- Modify: `macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift`

- [ ] **Step 1: 添加 Alert 和 Sheet 状态**

在 `FileBrowserPanel` struct 中已有的 `@State` 属性后添加：

```swift
@State private var showBatchDeleteAlert = false
@State private var showMoveError = false
@State private var moveErrorMessage = ""
```

- [ ] **Step 2: 在 body 的 `.background` 修饰符链中追加 Alert**

在 `panelContent` 的修饰符链（`.focusable()` 之后）追加：

```swift
.alert("删除 \(viewModel.selectedNodeIds.count) 个项目？", isPresented: $showBatchDeleteAlert) {
    Button("取消", role: .cancel) {}
    Button("移到废纸篓", role: .destructive) {
        // 业务逻辑下沉到 ViewModel，View 层只处理 UI 反馈
        let errors = viewModel.deleteSelected()
        if !errors.isEmpty {
            moveErrorMessage = "以下项目无法删除：\(errors.joined(separator: "、"))"
            showMoveError = true
        }
    }
} message: {
    Text("此操作将移至废纸篓，可恢复。")
}
.alert("操作失败", isPresented: $showMoveError) {
    Button("好") {}
} message: {
    Text(moveErrorMessage)
}
```

- [ ] **Step 3: 更新 treeScrollView 中的 FileNodeRow 调用**

将 `FileNodeRow(...)` 的调用更新，传入新增参数并将 `onSingleClick` 改为感知修饰键：

```swift
FileNodeRow(
    node: entry.node,
    depth: entry.depth,
    gitStatus: viewModel.gitStatus(for: entry.node.url),
    isSelected: viewModel.selectedNodeIds.contains(entry.node.id),
    isMultiSelected: viewModel.selectedNodeIds.count > 1,
    selectedCount: viewModel.selectedNodeIds.count,
    selectedURLs: viewModel.selectedNodeIds.compactMap { viewModel.findNodeURL(id: $0) },
    onToggleExpand: {
        viewModel.toggleExpand(nodeId: entry.node.id)
    },
    onSingleClick: {
        // 通过 NSApp.currentEvent 读取修饰键
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if flags.contains(.command) {
            viewModel.toggleSelection(id: entry.node.id)
        } else if flags.contains(.shift) {
            viewModel.extendSelection(to: entry.node.id)
        } else {
            viewModel.selectNode(id: entry.node.id)
            if entry.node.isDirectory {
                viewModel.toggleExpand(nodeId: entry.node.id)
            }
        }
        isFocused = true
    },
    onDoubleClick: {
        if !entry.node.isDirectory {
            viewModel.openInDefaultApp(entry.node.url)
        }
    },
    onOpenInTerminal: { onOpenInTerminal?(entry.node.url) },
    onCopyPath: { viewModel.copyPath(entry.node.url) },
    onNewFile: {
        let dir = entry.node.isDirectory
            ? entry.node.url
            : entry.node.url.deletingLastPathComponent()
        viewModel.createFile(inDirectory: dir, name: "untitled")
    },
    onNewDirectory: {
        let dir = entry.node.isDirectory
            ? entry.node.url
            : entry.node.url.deletingLastPathComponent()
        viewModel.createDirectory(inDirectory: dir, name: "untitled")
    },
    onDelete: {
        if viewModel.selectedNodeIds.count > 1 {
            showBatchDeleteAlert = true
        } else {
            viewModel.delete(url: entry.node.url)
            if viewModel.lastSelectedId == entry.node.id {
                viewModel.clearSelection()
            }
        }
    },
    onMoveSelected: { presentMovePanel() },
    onStartRename: {
        renameText = entry.node.name
        viewModel.renamingURL = entry.node.url
    },
    isRenaming: viewModel.renamingURL == entry.node.url,
    renameText: viewModel.renamingURL == entry.node.url
        ? Binding(get: { renameText }, set: { renameText = $0 })
        : nil,
    onCommitRename: { newName in viewModel.rename(url: entry.node.url, to: newName) },
    onCancelRename: { viewModel.renamingURL = nil }
)
```

- [ ] **Step 4: 添加 dropDestination 到目录行**

在 `FileNodeRow` 调用链后追加（仅目录节点）：

```swift
.dropDestination(for: URL.self) { droppedURLs, _ in
    guard entry.node.isDirectory else { return false }
    viewModel.move(urls: droppedURLs, to: entry.node.url)
    return true
} isTargeted: { _ in }
```

- [ ] **Step 5: 添加 presentMovePanel 方法**

在 `// MARK: - Key Handlers` 前追加：

```swift
// MARK: - Move Panel

private func presentMovePanel() {
    let urls = viewModel.selectedNodeIds.compactMap { viewModel.findNodeURL(id: $0) }
    guard !urls.isEmpty else { return }

    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "移动到此处"
    panel.message = "选择目标目录"

    panel.begin { response in
        guard response == .OK, let destination = panel.url else { return }
        // 校验和错误处理委托给 ViewModel，View 只处理返回的错误列表展示
        let errors = viewModel.move(urls: urls, to: destination)
        if !errors.isEmpty {
            DispatchQueue.main.async {
                moveErrorMessage = errors.joined(separator: "\n")
                showMoveError = true
            }
        }
    }
}
```

- [ ] **Step 6: 更新 handleDeleteKey 支持批量删除 Alert**

将：

```swift
private func handleDeleteKey(modifiers: EventModifiers) -> BackportKeyPressResult {
    guard isFocused, modifiers.contains(.command) else { return .ignored }
    guard let nodeId = viewModel.selectedNodeId,
          let entry = viewModel.visibleNodes.first(where: { $0.node.id == nodeId }) else { return .ignored }
    viewModel.delete(url: entry.node.url)
    viewModel.selectedNodeId = nil
    return .handled
}
```

替换为：

```swift
private func handleDeleteKey(modifiers: EventModifiers) -> BackportKeyPressResult {
    guard isFocused, modifiers.contains(.command) else { return .ignored }
    guard !viewModel.selectedNodeIds.isEmpty else { return .ignored }
    if viewModel.selectedNodeIds.count > 1 {
        showBatchDeleteAlert = true
    } else if let id = viewModel.lastSelectedId,
              let entry = viewModel.visibleNodes.first(where: { $0.node.id == id }) {
        viewModel.delete(url: entry.node.url)
        viewModel.clearSelection()
    }
    return .handled
}
```

- [ ] **Step 7: 添加 Cmd+A 快捷键**

在现有 `.backport.onKeyPress` 链中追加：

```swift
.backport.onKeyPress("a") { handleAKey(modifiers: $0) }
```

并在 Key Handlers 区域添加：

```swift
private func handleAKey(modifiers: EventModifiers) -> BackportKeyPressResult {
    guard isFocused, modifiers.contains(.command) else { return .ignored }
    viewModel.selectAll()
    return .handled
}
```

- [ ] **Step 8: 更新箭头键处理（多选时清空再移动）**

现有 `handleUpArrow`/`handleDownArrow` 直接调用 `viewModel.selectPrevious()`/`viewModel.selectNext()`，而 `selectNext()`/`selectPrevious()` 内部已改为调用 `selectNode(id:)`（会清空多选），无需额外修改。确认调用链正确即可。

- [ ] **Step 9: 添加选中计数标签到 filter bar**

将现有 `filterBar` 改为：

```swift
private var filterBar: some View {
    VStack(spacing: 0) {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            TextField("Filter", text: $viewModel.filterText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)

        if viewModel.selectedNodeIds.count > 1 {
            HStack {
                Text("已选 \(viewModel.selectedNodeIds.count) 个项目")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Button("取消选择") { viewModel.clearSelection() }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
    }
}
```

- [ ] **Step 10: 更新其他 Key Handlers 中旧的 `selectedNodeId` 引用**

检查所有 Key Handler 中是否还有 `viewModel.selectedNodeId` 引用，全部改为 `viewModel.lastSelectedId`（Task 4 的临时修复应已处理，这里做最终确认）。

- [ ] **Step 11: 编译检查**

```bash
make check 2>&1 | grep "error:"
```

预期：无错误。

- [ ] **Step 12: Commit**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift
git commit -m "feat(filebrowser): 批量选择交互、Cmd+A、批量删除 Alert、移动面板、dropDestination"
```

---

## Task 8：增量构建验证

- [ ] **Step 1: 增量构建**

```bash
make dev 2>&1 | tail -5
```

预期：`BUILD SUCCEEDED`

如果失败且怀疑缓存问题：

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/Ghostty-* && make clean && make dev
```

- [ ] **Step 2: 手动冒烟测试**

启动应用，打开一个有多个文件的目录，验证：
- [ ] 单击选中单个文件（高亮）
- [ ] Cmd+单击追加选中（两行高亮）
- [ ] Shift+单击范围选（多行高亮）
- [ ] filter bar 显示「已选 N 个项目」+ 取消按钮
- [ ] 右键菜单多选时显示「删除 N 个项目…」和「移动到…」
- [ ] Cmd+Delete 弹出确认 Alert，确认后文件移至废纸篓
- [ ] Cmd+A 全选所有可见节点
- [ ] 多选后拖拽其中一个选中文件到另一目录，所有选中文件都被移动
- [ ] 不在选中集合中的行直接拖拽，只移动该行文件（不影响其他选中项）
- [ ] 拖拽文件到树内目录完成移动
- [ ] 「移动到…」打开 NSOpenPanel，选择目标后完成移动
- [ ] 方向键清空多选后单选导航

- [ ] **Step 3: 最终 Commit（如有残余改动）**

```bash
git add -p
git commit -m "fix(filebrowser): 修复冒烟测试中发现的问题"
```

---

## Task 9：推送并创建 Pull Request

- [ ] **Step 1: 推送 feature branch**

```bash
git push -u origin feat/filebrowser-batch-ops
```

- [ ] **Step 2: 创建 Pull Request**

```bash
gh pr create \
  --title "feat(filebrowser): 批量选择、批量删除、批量移动" \
  --body "$(cat <<'EOF'
## Summary
- 批量选择：Cmd+Click 追加/取消，Shift+Click 范围选，Cmd+A 全选
- 批量删除：Cmd+Delete 或右键菜单，弹出确认 Alert，移至废纸篓
- 批量移动：拖拽到树内目录，或右键「移动到…」打开 NSOpenPanel

## Changes
- `FileBrowserViewModel`: `selectedNodeId` → `Set<UUID>` + `lastSelectedId`，新增选择方法和 `move(urls:to:)`
- `FileNodeRow`: 多选右键菜单适配，`draggable` 支持
- `FileBrowserPanel`: 修饰键感知点击，批量删除 Alert，NSOpenPanel，`dropDestination`，选中计数标签
- `FileBrowserViewModelNavigationTests`: 已有测试更新 + 新增批量选择测试

## Test plan
- [ ] 单选、Cmd+Click、Shift+Click、Cmd+A 均正确更新高亮
- [ ] 方向键在多选时清空后单选移动
- [ ] Cmd+Delete 弹 Alert，确认后移至废纸篓，部分失败有错误提示
- [ ] 拖拽到目录内完成移动
- [ ] 「移动到…」NSOpenPanel 移动成功，子目录/权限校验阻止非法操作
- [ ] 单元测试全部通过

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: 验证 PR 已创建**

```bash
gh pr view
```

---

## 快速参考

| 命令 | 用途 |
|------|------|
| `make check` | 类型检查（快速，不构建） |
| `make dev` | 增量构建（日常开发） |
| `make dev-clean` | 清理后全量构建（构建失败时） |
| `gh pr create` | 创建 Pull Request |
