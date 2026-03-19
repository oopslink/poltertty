# Filetree 键盘导航设计文档

**日期**: 2026-03-19
**特性**: 文件树键盘导航（上下移动选择 + Enter 展开文件夹）

---

## 背景

FileBrowser 面板已支持多种键盘快捷键（r/n/t/space 等），但缺少基础的方向键导航能力。用户需要鼠标点击才能在文件树中移动选择，键盘操作体验不完整。

---

## 需求

- `↑` 键：将选中项移动到上一个可见节点
- `↓` 键：将选中项移动到下一个可见节点
- `Enter` 键：对目录节点触发展开/收起，对文件节点忽略
- 键盘导航时，如果选中项移出可视区域，自动滚动使其可见

---

## 设计方案：ScrollViewReader + ViewModel 导航方法（方案 A）

### 架构决策

在 ViewModel 中添加导航方法（而非在 View 层计算），原因：
- `visibleNodes` 是展平的线性列表，已在 ViewModel 中维护，导航逻辑天然归属于此
- 与现有 `selectNode`、`toggleExpand` 等方法保持一致的职责划分

不复用 `selectNode(id:)` 方法，因为该方法会联动 preview panel 的显隐状态，键盘导航时不应触发此副作用。

---

## 实施细节

### FileBrowserViewModel 改动

新增两个导航方法：

```swift
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

### FileBrowserPanel 改动

**treeScrollView**：用 `ScrollViewReader` 包裹，给每个 `FileNodeRow` 添加 `.id(entry.node.id)`，并通过 `onChange(of: viewModel.selectedNodeId)` 触发自动滚动：

```swift
ScrollViewReader { proxy in
    ScrollView {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.visibleNodes, id: \.node.id) { entry in
                FileNodeRow(...)
                    .id(entry.node.id)
            }
        }
    }
    .onChange(of: viewModel.selectedNodeId) { id in
        if let id { proxy.scrollTo(id, anchor: .nearest) }
    }
}
```

**新增三个 key handler**（与现有 `.backport.onKeyPress` 模式一致）：

```swift
.backport.onKeyPress(KeyEquivalent.upArrow)   { handleUpArrow(modifiers: $0) }
.backport.onKeyPress(KeyEquivalent.downArrow) { handleDownArrow(modifiers: $0) }
.backport.onKeyPress(KeyEquivalent.return)    { handleReturnKey(modifiers: $0) }
```

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

---

## 边界行为

| 场景 | 行为 |
|------|------|
| 在列表顶部按 ↑ | 停留在第一项（不循环） |
| 在列表底部按 ↓ | 停留在最后一项（不循环） |
| 无选中状态时按 ↑/↓ | 选中第一项 |
| 对文件节点按 Enter | 忽略（返回 `.ignored`） |
| 选中项移出可视区域 | `scrollTo(id, anchor: .nearest)` 自动滚动 |

---

## 受影响文件

- `macos/Sources/Features/Workspace/FileBrowser/FileBrowserViewModel.swift` — 新增 `selectNext()` / `selectPrevious()`
- `macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift` — 新增三个 key handler + 改造 `treeScrollView`
