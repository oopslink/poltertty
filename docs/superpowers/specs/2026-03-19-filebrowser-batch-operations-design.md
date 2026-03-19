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

// 便利属性（兼容预览面板）
var primarySelectedId: UUID? { selectedNodeIds.first }
```

### 新增选择方法

| 方法 | 行为 |
|------|------|
| `selectNode(id:)` | 单选，清除其他选中 |
| `extendSelection(to:)` | Shift+Click 范围选（基于 visibleNodes 扁平索引） |
| `toggleSelection(id:)` | Cmd+Click 追加或取消单个 |
| `clearSelection()` | 清空选中 |
| `selectAll()` | 全选当前可见节点 |

### 预览面板兼容

预览面板改用 `primarySelectedId`，单选场景行为完全不变。

---

## 第二节：批量操作

### 批量删除

- **键盘**：`Cmd+Delete`，多选时弹出 Alert
  - 内容：「删除 N 个项目？此操作将移至废纸篓，可恢复。」
  - 确认后逐个调用 `FileManager.trashItem`
- **右键菜单**：多选时显示「删除 N 个项目…」（单选保持「Delete」不变）

### 批量移动 — 拖拽

- `FileNodeRow` 添加 `.draggable`，载荷为所有选中项的 `[URL]`
- 目录行添加 `.dropDestination(for: URL.self)`，接收并调用 `FileManager.moveItem`
- 支持拖拽到 Finder（macOS 原生文件协议自动支持）

### 批量移动 — "移动到…" 面板

- 多选时，右键菜单显示「移动到…」
- 触发 `NSOpenPanel`（canChooseDirectories: true，canChooseFiles: false）
- 用户选定目标目录后，ViewModel 调用 `move(urls: [URL], to: URL)` 批量执行

### ViewModel 新增方法

```swift
func deleteSelected()                          // 批量删除（含 Alert 触发）
func move(urls: [URL], to destination: URL)    // 批量移动
```

---

## 第三节：UI 交互细节

### 点击手势（集中在 FileBrowserPanel）

| 操作 | 行为 |
|------|------|
| 单击 | `selectNode(id:)` — 清除其他，单选 |
| Cmd+单击 | `toggleSelection(id:)` — 追加/取消 |
| Shift+单击 | `extendSelection(to:)` — 范围选 |

### 键盘快捷键

| 快捷键 | 行为 |
|--------|------|
| `Cmd+A` | 全选可见节点 |
| `Cmd+Delete` | 批量删除（带确认 Alert） |

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
| `FileBrowserViewModel.swift` | 选择状态改为 `Set<UUID>`，新增选择/操作方法 |
| `FileBrowserPanel.swift` | 点击手势逻辑扩展，新增键盘快捷键，Alert 触发 |
| `FileNodeRow.swift` | 添加 draggable/dropDestination，右键菜单动态适配 |

---

## 不在本次范围内

- 跨 Workspace 的文件移动
- 拖拽排序（reorder）
- 批量重命名
