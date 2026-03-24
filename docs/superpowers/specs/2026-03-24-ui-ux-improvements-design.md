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
- **分隔线规则**：每个 tab 在自身**右侧** overlay 一条竖线。为避免 active tab 背景色块两侧产生视觉噪音，规则如下：
  - Active tab 不显示自身右侧竖线（`tab.isActive == true` 时不渲染）
  - 紧靠 active tab 右侧的 tab 也不显示自身右侧竖线（即该 tab 的 `isNextActive == true`）
  - 数组末位 tab 的 `isNextActive` 为 `false`
  - `layout.overflow` 中的溢出 tab 不进入 `ForEach` 渲染，无需处理

- **`isNextActive` 计算方式**：在 `WorkspaceBarView.body` 的 `ForEach(layout.visible)` 中，改用 `Array(layout.visible.enumerated())` 遍历，通过下标 `i+1` 访问下一个元素判断其 `isActive`；末位元素直接传 `false`

### 涉及文件

- `macos/Sources/Features/Workspace/TabBar/TerminalTabItem.swift`
- `macos/Sources/Features/Workspace/TabBar/TitlebarTabsAccessory.swift`（`WorkspaceBarView` 中改用 `enumerated()` 传 `isNextActive`）

---

## 2. 侧边栏 Worktree 归属关系优化

### 现状

- Worktree 列表直接跟在 workspace item 后面，缩进 `padding(.leading, 16)`，无明显视觉连接
- 与 workspace 的父子关系不直观

### 目标

**方案 C（用户选定）**：使用 workspace 的 accent 色做左边线，共享颜色强化归属感。

### 设计细节

- Worktree 折叠区的 `VStack(spacing: 0)`（包含 header button + `if worktreeExpanded { WorktreeListView }` 两部分）整体包裹在一个额外的 `VStack` 或直接在该 `VStack` 上，用 `.overlay(alignment: .leading)` 添加 2px 竖线
- overlay 挂在**最外层的 `VStack(spacing: 0)`** 上，确保竖线从 header 顶部延伸到列表底部
- 竖线用 `Rectangle().fill(worktreeLineColor).frame(width: 2)` 实现，高度自动撑满父视图
- 竖线颜色：active workspace 时取 `workspace.color`，非 active 时（当前只在 active workspace 下才显示 worktree 区域，故此规则仅供扩展参考）
- 整体 `padding(.leading, 20)` 为竖线和内容留出空间（原为 `padding(.leading, 16)`）

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
- `ExpandedWorkspaceItem` 共有**两处**调用需要同步修改：
  1. `ungroupedSection`（约第 303 行）中 active workspace 对应的调用
  2. `expandedContent` 内分组 `ForEach(manager.workspacesInGroup(group.id))` 中 active workspace 对应的调用
  - 两处均只在 `workspace.id == currentWorkspaceId` 时传入 `onShowCreateForm: { showWorktreeCreateForm = true }`，非 active workspace 传 `nil`
- `WorktreeListView` 共有**两处**调用需要同步移除 `onShowCreateForm` 参数：
  1. `ungroupedSection` 中（约第 348 行）
  2. `expandedContent` 分组内（约第 471 行）

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
