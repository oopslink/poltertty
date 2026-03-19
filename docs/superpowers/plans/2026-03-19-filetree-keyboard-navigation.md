# Filetree 键盘导航实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在文件浏览器面板中支持 ↑/↓ 键移动选择、Enter 键展开/收起目录。

**Architecture:** 在 `FileBrowserViewModel` 中新增 `selectNext()` / `selectPrevious()` 纯导航方法（不触发 preview panel 副作用）；在 `FileBrowserPanel` 的 `treeScrollView` 中引入 `ScrollViewReader` 实现自动滚动，并注册三个新的 key handler。

**Tech Stack:** Swift 5.9+、SwiftUI、macOS 14+（`onKeyPress`）、Swift Testing

---

## 受影响文件

| 文件 | 操作 |
|------|------|
| `macos/Sources/Features/Workspace/FileBrowser/FileBrowserViewModel.swift` | 修改：新增 `selectNext()` / `selectPrevious()` |
| `macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift` | 修改：改造 `treeScrollView`，新增三个 key handler |
| `macos/Tests/Workspace/FileBrowserViewModelNavigationTests.swift` | 新建：ViewModel 导航方法单元测试 |

---

## Task 1：为 ViewModel 导航方法编写失败测试

**Files:**
- Create: `macos/Tests/Workspace/FileBrowserViewModelNavigationTests.swift`

测试思路：创建临时目录结构，初始化 ViewModel，通过 `visibleNodes` 验证导航行为。

- [ ] **Step 1: 创建测试文件**

```swift
// macos/Tests/Workspace/FileBrowserViewModelNavigationTests.swift
import Testing
import Foundation
@testable import Ghostty

struct FileBrowserViewModelNavigationTests {

    // 创建临时目录：rootDir/a.txt, rootDir/b.txt, rootDir/c.txt
    private func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        for name in ["a.txt", "b.txt", "c.txt"] {
            FileManager.default.createFile(atPath: tmp.appendingPathComponent(name).path, contents: nil)
        }
        return tmp
    }

    @Test func testSelectNextMovesSelectionDown() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = FileBrowserViewModel(rootDir: dir.path)
        let nodes = vm.visibleNodes
        guard nodes.count >= 2 else { return }

        vm.selectedNodeId = nodes[0].node.id
        vm.selectNext()
        #expect(vm.selectedNodeId == nodes[1].node.id)
    }

    @Test func testSelectPreviousMovesSelectionUp() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = FileBrowserViewModel(rootDir: dir.path)
        let nodes = vm.visibleNodes
        guard nodes.count >= 2 else { return }

        vm.selectedNodeId = nodes[1].node.id
        vm.selectPrevious()
        #expect(vm.selectedNodeId == nodes[0].node.id)
    }

    @Test func testSelectNextClampsAtBottom() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = FileBrowserViewModel(rootDir: dir.path)
        let nodes = vm.visibleNodes
        guard let last = nodes.last else { return }

        vm.selectedNodeId = last.node.id
        vm.selectNext()
        #expect(vm.selectedNodeId == last.node.id)
    }

    @Test func testSelectPreviousClampsAtTop() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = FileBrowserViewModel(rootDir: dir.path)
        let nodes = vm.visibleNodes
        guard let first = nodes.first else { return }

        vm.selectedNodeId = first.node.id
        vm.selectPrevious()
        #expect(vm.selectedNodeId == first.node.id)
    }

    @Test func testSelectNextWithNoSelectionSelectsFirst() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = FileBrowserViewModel(rootDir: dir.path)
        let nodes = vm.visibleNodes
        guard let first = nodes.first else { return }

        vm.selectedNodeId = nil
        vm.selectNext()
        #expect(vm.selectedNodeId == first.node.id)
    }

    @Test func testSelectPreviousWithNoSelectionSelectsFirst() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = FileBrowserViewModel(rootDir: dir.path)
        let nodes = vm.visibleNodes
        guard let first = nodes.first else { return }

        vm.selectedNodeId = nil
        vm.selectPrevious()
        #expect(vm.selectedNodeId == first.node.id)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

```bash
cd macos && xcodebuild test \
  -scheme Ghostty \
  -destination 'platform=macOS' \
  -only-testing GhosttyTests/FileBrowserViewModelNavigationTests \
  2>&1 | grep -E "FAIL|error:|FileBrowserViewModel"
```

预期：编译错误 — `selectNext` / `selectPrevious` 未定义。

---

## Task 2：在 ViewModel 实现导航方法

**Files:**
- Modify: `macos/Sources/Features/Workspace/FileBrowser/FileBrowserViewModel.swift`（在 `// MARK: - Preview` 区块后追加新区块）

- [ ] **Step 3: 在 FileBrowserViewModel.swift 中添加新区块**

在文件末尾（`}` 闭合括号前）添加：

```swift
// MARK: - Keyboard Navigation

func selectNext() {
    let nodes = visibleNodes
    guard !nodes.isEmpty else { return }
    if let id = selectedNodeId,
       let idx = nodes.firstIndex(where: { $0.node.id == id }) {
        selectedNodeId = nodes[min(idx + 1, nodes.count - 1)].node.id
    } else {
        selectedNodeId = nodes[0].node.id
    }
}

func selectPrevious() {
    let nodes = visibleNodes
    guard !nodes.isEmpty else { return }
    if let id = selectedNodeId,
       let idx = nodes.firstIndex(where: { $0.node.id == id }) {
        selectedNodeId = nodes[max(idx - 1, 0)].node.id
    } else {
        selectedNodeId = nodes[0].node.id
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

```bash
cd macos && xcodebuild test \
  -scheme Ghostty \
  -destination 'platform=macOS' \
  -only-testing GhosttyTests/FileBrowserViewModelNavigationTests \
  2>&1 | grep -E "passed|failed|error:"
```

预期：`6 tests passed, 0 failed`。

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/FileBrowserViewModel.swift \
        macos/Tests/Workspace/FileBrowserViewModelNavigationTests.swift
git commit -m "feat(filetree): 添加 selectNext/selectPrevious 键盘导航方法"
```

---

## Task 3：改造 treeScrollView + 注册 key handler

**Files:**
- Modify: `macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift`

- [ ] **Step 6: 替换 treeScrollView**

找到 `private var treeScrollView: some View {` 方法，将其全部替换为：

```swift
private var treeScrollView: some View {
    ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.visibleNodes, id: \.node.id) { entry in
                    FileNodeRow(
                        node: entry.node,
                        depth: entry.depth,
                        gitStatus: viewModel.gitStatus(for: entry.node.url),
                        isSelected: viewModel.selectedNodeId == entry.node.id,
                        onToggleExpand: {
                            viewModel.toggleExpand(nodeId: entry.node.id)
                        },
                        onSingleClick: {
                            viewModel.selectNode(id: entry.node.id)
                            if entry.node.isDirectory {
                                viewModel.toggleExpand(nodeId: entry.node.id)
                            }
                            isFocused = true
                        },
                        onDoubleClick: {
                            if !entry.node.isDirectory {
                                viewModel.openInDefaultApp(entry.node.url)
                            }
                        },
                        onOpenInTerminal: {
                            onOpenInTerminal?(entry.node.url)
                        },
                        onCopyPath: {
                            viewModel.copyPath(entry.node.url)
                        },
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
                            viewModel.delete(url: entry.node.url)
                            if viewModel.selectedNodeId == entry.node.id {
                                viewModel.selectedNodeId = nil
                                viewModel.showPreviewPanel = false
                            }
                        },
                        onStartRename: {
                            renameText = entry.node.name
                            viewModel.renamingURL = entry.node.url
                        },
                        isRenaming: viewModel.renamingURL == entry.node.url,
                        renameText: viewModel.renamingURL == entry.node.url
                            ? Binding(get: { renameText }, set: { renameText = $0 })
                            : nil,
                        onCommitRename: { newName in
                            viewModel.rename(url: entry.node.url, to: newName)
                        },
                        onCancelRename: {
                            viewModel.renamingURL = nil
                        }
                    )
                    .id(entry.node.id)
                }
            }
        }
        .onChange(of: viewModel.selectedNodeId) { id in
            if let id {
                proxy.scrollTo(id, anchor: .nearest)
            }
        }
    }
}
```

唯一的变化是：
1. 用 `ScrollViewReader { proxy in ... }` 包裹
2. 每个 `FileNodeRow` 末尾增加 `.id(entry.node.id)`
3. `ScrollView` 末尾增加 `.onChange(of:)` 回调

- [ ] **Step 7: 在 body 中注册三个新 key handler**

找到 `body` 属性的 `.backport.onKeyPress(" ") { handleSpaceKey(modifiers: $0) }` 这一行，在其后追加：

```swift
.backport.onKeyPress(KeyEquivalent.upArrow)   { handleUpArrow(modifiers: $0) }
.backport.onKeyPress(KeyEquivalent.downArrow) { handleDownArrow(modifiers: $0) }
.backport.onKeyPress(KeyEquivalent.return)    { handleReturnKey(modifiers: $0) }
```

- [ ] **Step 8: 在 // MARK: - Key Handlers 区块末尾添加三个 handler 方法**

找到 `handleSpaceKey` 方法末尾，在其后追加：

```swift
private func handleUpArrow(modifiers: EventModifiers) -> BackportKeyPressResult {
    guard isFocused else { return .ignored }
    viewModel.selectPrevious()
    return .handled
}

private func handleDownArrow(modifiers: EventModifiers) -> BackportKeyPressResult {
    guard isFocused else { return .ignored }
    viewModel.selectNext()
    return .handled
}

private func handleReturnKey(modifiers: EventModifiers) -> BackportKeyPressResult {
    guard isFocused,
          let nodeId = viewModel.selectedNodeId,
          let entry = viewModel.visibleNodes.first(where: { $0.node.id == nodeId }),
          entry.node.isDirectory else { return .ignored }
    viewModel.toggleExpand(nodeId: nodeId)
    return .handled
}
```

- [ ] **Step 9: 编译确认无错误**

```bash
cd macos && xcodebuild build \
  -scheme Ghostty \
  -destination 'platform=macOS' \
  2>&1 | grep -E "error:|warning:|BUILD"
```

预期：`BUILD SUCCEEDED`，无 error。

- [ ] **Step 10: Commit**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift
git commit -m "feat(filetree): 添加方向键导航和 Enter 展开/收起目录"
```

---

## 手动验证清单

构建并运行后，在文件浏览器中确认：

- [ ] 点击文件树使其获得焦点后，按 ↓ 键选中第一项（无选中时）
- [ ] 连续按 ↓ 依次向下移动选中项
- [ ] 连续按 ↑ 依次向上移动选中项
- [ ] 在列表顶部按 ↑ 不循环，停留在第一项
- [ ] 在列表底部按 ↓ 不循环，停留在最后一项
- [ ] 对目录节点按 Enter，展开/收起目录
- [ ] 对文件节点按 Enter，无反应
- [ ] 键盘导航时，选中项移出可视区域后自动滚动使其可见
