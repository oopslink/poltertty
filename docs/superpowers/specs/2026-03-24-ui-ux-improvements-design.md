# UI/UX 优化设计文档

**日期**: 2026-03-24
**范围**: Tab 边框样式、侧边栏 worktree 归属关系、"Add Worktree" 入口迁移

---

## 1. Tab 边框优化

### 现状

`TerminalTabItem` 当前样式：
- 背景完全透明
- Active tab：底部 2px accent 色条
- Hover：底部 2px 浅色条
- Tab 之间无任何分隔

### 目标

**方案 C（用户选定）**：竖分隔线 + active 背景色块，保留底部 accent 色条。

### 设计细节

- **Active tab**：圆角（`cornerRadius: 4`）背景色块，颜色 `Color.primary.opacity(0.1)`，底部 2px accent 色条保留
- **非 active tab**：透明背景，相邻 tab 之间加 1px 竖分隔线，颜色 `Color(nsColor: .separatorColor)`；hover 时显示浅色背景 `Color.primary.opacity(0.05)`
- **分隔线规则**：每个 tab 在右侧 overlay 一条竖线，active tab 及其右邻 tab 不显示分隔线（避免与背景色块产生视觉噪音）；这需要 `TerminalTabItem` 知道右侧 tab 是否 active，通过新增 `isNextActive: Bool` 参数传入

### 涉及文件

- `macos/Sources/Features/Workspace/TabBar/TerminalTabItem.swift`
- `macos/Sources/Features/Workspace/TabBar/TitlebarTabsAccessory.swift`（传 `isNextActive`）

---

## 2. 侧边栏 Worktree 归属关系优化

### 现状

- Worktree 列表直接跟在 workspace item 后面，缩进 `padding(.leading, 16)`，无明显视觉连接
- 与 workspace 的父子关系不直观

### 目标

**方案 C（用户选定）**：使用 workspace 的 accent 色做左边线，共享颜色强化归属感。

### 设计细节

- Worktree 折叠区（header + list）整体用 `overlay(alignment: .leading)` 添加 2px 竖线
- 竖线颜色：取自 `workspace.color`（与 workspace item 左侧 active bar 同色），非 active workspace 时颜色降至 `workspace.color.opacity(0.35)`
- 当前缩进从 `padding(.leading, 16)` 改为 `padding(.leading, 20)`，为左边线留出视觉空间
- 左边线高度：撑满整个 worktree 折叠区

### 涉及文件

- `macos/Sources/Features/Workspace/WorkspaceSidebar.swift`（ungroupedSection 和分组内的 worktree 区块）

---

## 3. "Add Worktree" 入口迁移

### 现状

- `WorktreeListView` 底部有一个独立的"+ Add Worktree"按钮，体积大、位置偏，割裂感强

### 目标

- 删除底部按钮
- 在 `ExpandedWorkspaceItem` 右侧增加 `···` 菜单按钮，hover 时显示
- 菜单首个条目：**Add Worktree…**，调用回调 `onShowCreateForm`
- 后续可扩展其他条目（Rename、Archive 等）

### 设计细节

**`ExpandedWorkspaceItem` 改动**：
- 新增 `var onShowCreateForm: (() -> Void)? = nil` 回调
- `body` 中 `Spacer()` 后增加 `···` 按钮，hover 时 `opacity(1)`，否则 `opacity(0)`
- 点击调用 `NSMenu`，条目：
  - "Add Worktree…" → `onShowCreateForm?()`
- 按钮使用 `.buttonStyle(.plain)`，`foregroundColor(.secondary)`

**`WorktreeListView` 改动**：
- 删除底部 `Button(action: onShowCreateForm)` 及相关 `addButtonHovering` state
- 删除 `onShowCreateForm` 参数（该回调上移至 workspace item 层）

**`WorkspaceSidebar` 改动**：
- `ExpandedWorkspaceItem` 调用处传入 `onShowCreateForm: { showWorktreeCreateForm = true }`（仅 active workspace）
- `WorktreeListView` 调用处移除 `onShowCreateForm` 参数

### 涉及文件

- `macos/Sources/Features/Workspace/WorkspaceSidebar.swift`
- `macos/Sources/Features/Workspace/WorktreeListView.swift`

---

## 总结

| 改动 | 文件 | 复杂度 |
|------|------|--------|
| Tab 竖分隔线 + active 背景 | `TerminalTabItem.swift`, `TitlebarTabsAccessory.swift` | 低 |
| Worktree 左边线 | `WorkspaceSidebar.swift` | 低 |
| Add Worktree 入口迁移 | `WorkspaceSidebar.swift`, `WorktreeListView.swift` | 低 |

三项改动均为纯 UI 调整，无数据模型变更，无新文件，可在同一个 worktree 内完成。
