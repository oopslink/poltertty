# FileBrowser 批量操作设计文档

**日期**：2026-03-19
**状态**：已批准
**功能**：FileBrowser 批量选择、批量删除、批量移动

---

## 背景

当前 FileBrowser 仅支持单文件操作。本设计为其添加批量选择、批量删除和批量移动能力，采用 macOS 原生交互风格。

---

## 设计目标

- 支持多文件/目录同时选中
- 批量删除（移至废纸篓，带确认 Alert）
- 批量移动（拖拽 + "移动到…" 面板双模式）
- 改动最小，不破坏现有预览面板、重命名等功能

---

## 方案选择

采用**最小侵入式方案**：将 ViewModel 中的单选 `UUID?` 改为多选 `Set<UUID>`，点击手势逻辑集中在 `FileBrowserPanel`，不引入新的状态管理层，不重构视图树。

---

## 第一节：选择状态管理

### FileBrowserViewModel 变更

```swift
// 旧
@Published var selectedNodeId: UUID? = nil

// 新
@Published var selectedNodeIds: Set<UUID> = []
private(set) var lastSelectedId: UUID? = nil   // 确定性"主选中"，用于预览面板

// 便利属性（兼容预览面板）
var primarySelectedId: UUID? { lastSelectedId }
```

`lastSelectedId` 在每次选中操作中更新为最后一次被点击/导航到的节点 ID，不受 `Set` 无序性影响。

### 新增选择方法

| 方法 | 行为 |
|------|------|
| `selectNode(id:)` | 单选，清除其他选中，更新 `lastSelectedId` |
| `extendSelection(to:)` | Shift+Click 范围选（基于 `visibleNodes` 扁平索引，从 `lastSelectedId` 所在位置到目标位置） |
| `toggleSelection(id:)` | Cmd+Click 追加或取消单个，追加时更新 `lastSelectedId` |
| `clearSelection()` | 清空，重置 `lastSelectedId = nil` |
| `selectAll()` | 全选当前可见节点，`lastSelectedId` 设为最后一个可见节点 |

### reload() 中的多选状态恢复

现有 `reload()` 只保存/恢复单个 `selectedURL`，改为 `Set<UUID>` 后需同步更新：

```swift
// reload() 内
let selectedURLs = selectedNodeIds.compactMap { findNodeURL(id: $0) }
let lastSelectedURL = lastSelectedId.flatMap { findNodeURL(id: $0) }

// ... 重建树后 ...

// 恢复多选
var newIds = Set<UUID>()
for url in selectedURLs {
    if let node = findNodeByURL(url: url, in: rootNodes) { newIds.insert(node.id) }
}
selectedNodeIds = newIds

// 恢复 lastSelectedId
if let url = lastSelectedURL, let node = findNodeByURL(url: url, in: rootNodes) {
    lastSelectedId = node.id
} else {
    lastSelectedId = nil
    showPreviewPanel = false
}
```

### 键盘导航在多选时的语义

`selectNext()` / `selectPrevious()` 在多选激活时的行为：清空当前多选，从 `lastSelectedId` 位置单选移动。与 macOS Finder 行为一致（方向键会退出多选状态）。

### 预览面板兼容

预览面板改用 `primarySelectedId`（即 `lastSelectedId`），单选场景行为完全不变。

---

## 第二节：批量操作

### 批量删除

- **键盘**：`Cmd+Delete`，多选时弹出 Alert
  - 内容：「删除 N 个项目？此操作将移至废纸篓，可恢复。」
  - 确认后逐个调用 `FileManager.trashItem`
  - **部分失败处理**：收集所有失败的 URL，操作完成后弹出错误 Alert 汇总，例如「3 个项目中 1 个无法删除：foo.txt（权限不足）」
- **右键菜单**：多选时显示「删除 N 个项目…」（单选保持「Delete」不变）

### 批量移动 — 拖拽

- `FileNodeRow` 添加 `.draggable`
  - **拖拽起始行已在 `selectedNodeIds` 中**：载荷为所有选中项的 `[URL]`
  - **拖拽起始行不在 `selectedNodeIds` 中**：先清空选中，单选该行，再以单个 URL 为载荷开始拖拽
- 目录行添加 `.dropDestination(for: URL.self)`，接收并调用 `FileManager.moveItem`
- 支持拖拽到 Finder（macOS 原生文件协议自动支持）
- **拖拽取消**：SwiftUI 的 `dropDestination` 在取消时自动退出 `isTargeted` 状态，无需额外清理；若实现了自定义高亮需确保取消路径同样清理

### 批量移动 — "移动到…" 面板

- 多选时，右键菜单显示「移动到…」
- 触发 `NSOpenPanel`（`canChooseDirectories: true`，`canChooseFiles: false`）
- 用户选定目标目录后，ViewModel 调用 `move(urls: [URL], to: URL)` 批量执行

### ViewModel 新增方法

```swift
func deleteSelected()                          // 批量删除（触发 Alert，部分失败汇总报错）
func move(urls: [URL], to destination: URL)    // 批量移动
```

**`move` 前置校验**：
1. 若 `destination` 是任一被移动目录的子路径 → 提示错误，不执行
2. 若 `destination` 无写权限（`FileManager.isWritableFile(atPath:)` 返回 false）→ 提示权限错误，不执行
3. 部分失败同批量删除策略：操作完成后汇总报告

---

## 第三节：UI 交互细节

### 点击手势（集中在 FileBrowserPanel，通过 AppKit 感知修饰键）

当前 `FileNodeRow` 的 `TapGesture` 不提供修饰键信息。需将行的点击处理替换为 `NSClickGestureRecognizer`（AppKit 层），在回调中读取 `NSEvent.modifierFlags`，或通过 `simultaneousGesture` + `NSEventMonitor` 捕获修饰键后传入 ViewModel。

具体选择：使用 `NSClickGestureRecognizer` 包装在 `NSViewRepresentable` 内，提供 `onClick(modifierFlags:)` 回调给 `FileBrowserPanel`。

| 操作 | 行为 |
|------|------|
| 单击（无修饰键） | `selectNode(id:)` — 清除其他，单选 |
| Cmd+单击 | `toggleSelection(id:)` — 追加/取消 |
| Shift+单击 | `extendSelection(to:)` — 范围选 |

### 键盘快捷键

| 快捷键 | 行为 |
|--------|------|
| `Cmd+A` | 全选可见节点 |
| `Cmd+Delete` | 批量删除（带确认 Alert） |
| `↑` / `↓` | 清空多选，单选移动（与 Finder 一致） |

### 右键菜单动态适配

- **单选**：保持现有菜单不变（Rename、New File、New Directory、Delete 等）
- **多选**：隐藏 Rename、New File、New Directory；显示「删除 N 个项目…」和「移动到…」

### 行视图背景

- 多选时每个选中行沿用 `Color.accentColor.opacity(0.15)`，视觉一致

### 状态提示（低优先级）

- 多选激活时，filter bar 下方显示「已选 N 个项目」小标签

---

## 受影响文件

| 文件 | 变更类型 |
|------|----------|
| `FileBrowserViewModel.swift` | 选择状态改为 `Set<UUID>` + `lastSelectedId`，新增选择/操作方法，更新 `reload()` 多选恢复逻辑，更新键盘导航方法 |
| `FileBrowserPanel.swift` | 点击手势扩展（AppKit 修饰键感知），新增键盘快捷键，Alert 触发 |
| `FileNodeRow.swift` | 添加 draggable/dropDestination，右键菜单动态适配，替换点击手势为 AppKit 包装 |
| `FileBrowserViewModelNavigationTests.swift` | `selectedNodeId` 改名后需更新所有测试引用 |

---

## 不在本次范围内

- 跨 Workspace 的文件移动
- 拖拽排序（reorder）
- 批量重命名
