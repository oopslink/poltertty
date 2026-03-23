# UI/UX Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 优化 tab 边框样式、侧边栏 worktree 归属关系视觉层级，并将"Add Worktree"入口迁移到 workspace item 的 `···` 菜单。

**Architecture:** 纯 SwiftUI/AppKit UI 调整，无数据模型变更。Tab 新增 `isNextActive` 参数控制分隔线渲染；侧边栏 worktree 区块加左边线 overlay；`ExpandedWorkspaceItem` 新增 `···` 菜单，`WorktreeListView` 移除底部按钮。

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit (NSMenu), macOS 13+

---

## 文件变更地图

| 文件 | 变更类型 | 内容 |
|------|----------|------|
| `macos/Sources/Features/Workspace/TabBar/TerminalTabItem.swift` | 修改 | 新增 `isNextActive: Bool` 参数，添加竖分隔线和 active 背景色块 |
| `macos/Sources/Features/Workspace/TabBar/TitlebarTabsAccessory.swift` | 修改 | `WorkspaceBarView` 改用 `enumerated()` 传 `isNextActive` |
| `macos/Sources/Features/Workspace/WorkspaceSidebar.swift` | 修改 | worktree 区块加左边线；`ExpandedWorkspaceItem` 新增 `onShowCreateForm` 参数并加 `···` 菜单 |
| `macos/Sources/Features/Workspace/WorktreeListView.swift` | 修改 | 删除底部"Add Worktree"按钮和 `onShowCreateForm` 参数 |

---

## Task 1: Tab 竖分隔线 + Active 背景色块

**Files:**
- Modify: `macos/Sources/Features/Workspace/TabBar/TerminalTabItem.swift`

### 背景

当前 `TerminalTabItem` 背景透明，tab 之间无分隔。目标：active tab 加圆角背景色块，相邻 tab 间加竖分隔线（active tab 及其右邻不画线）。底部 accent 色条保留。

- [ ] **Step 1: 在 `TerminalTabItem` 添加 `isNextActive` 参数**

在 `struct TerminalTabItem: View {` 的属性列表中，紧跟 `var agentState: AgentState? = nil` 之后添加：

```swift
var isNextActive: Bool = false
```

- [ ] **Step 2: 添加 active 背景色块**

找到 `TerminalTabItem.swift` 第 68 行附近的内层 `ZStack`（包含 `TextField` / `HStack` 的那个），其 modifier 链上有 `.background(Color.clear)`。将该行替换为：

```swift
.background(
    RoundedRectangle(cornerRadius: 4)
        .fill(tab.isActive ? Color.primary.opacity(0.1) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
)
```

注意：`.background(...)` 之后紧跟的 `.contentShape(Rectangle())`、手势、`.overlay`、`.onHover` 等 modifier 保持不变，只替换这一行。

- [ ] **Step 3: 添加竖分隔线 overlay**

在 `.onHover { isHovered = $0 }` 之后、`.contextMenu` 之前，添加右侧竖分隔线：

```swift
.overlay(alignment: .trailing) {
    if !tab.isActive && !isNextActive {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 0.5)
            .padding(.vertical, 6)
    }
}
```

- [ ] **Step 4: 确认底部 accent 色条代码未被改动**

检查 `ZStack(alignment: .bottom)` 的底部 `Rectangle` 部分仍存在：

```swift
if tab.isActive {
    Rectangle()
        .fill(accentColor)
        .frame(height: 2)
        .transition(.opacity)
} else if isHovered {
    Rectangle()
        .fill(Color.primary.opacity(0.15))
        .frame(height: 2)
        .transition(.opacity)
}
```

若存在则无需修改。

- [ ] **Step 5: 构建确认无编译错误**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build 2>&1 | tail -5
```

预期：`BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Workspace/TabBar/TerminalTabItem.swift
git commit -m "feat(tab-bar): add vertical separator and active background to tab items"
```

---

## Task 2: 传递 `isNextActive` 给每个 TabItem

**Files:**
- Modify: `macos/Sources/Features/Workspace/TabBar/TitlebarTabsAccessory.swift`

### 背景

`WorkspaceBarView.body` 的 `ForEach(layout.visible)` 需改为 `enumerated()` 遍历，为每个 tab 计算其右侧 tab 是否 active。

- [ ] **Step 1: 将 `ForEach` 改为 `enumerated` 遍历**

找到 `WorkspaceBarView.body` 中的：

```swift
ForEach(layout.visible) { tab in
    TerminalTabItem(
        tab: tab,
        accentColor: accentColor,
        isLastTab: viewModel.tabs.count == 1,
        onSelect: { onSwitchTab(tab.id) },
        onClose: { onCloseTab(tab.id) },
        onRename: { viewModel.renameTab(tab.id, title: $0) },
        onCloseOthers: {
            viewModel.tabs
                .filter { $0.id != tab.id }
                .forEach { onCloseTab($0.id) }
        },
        agentState: viewModel.agentState(for: tab.surfaceId)
    )
    .id(tab.id)
}
```

替换为：

```swift
ForEach(Array(layout.visible.enumerated()), id: \.element.id) { index, tab in
    let nextIsActive = index + 1 < layout.visible.count && layout.visible[index + 1].isActive
    TerminalTabItem(
        tab: tab,
        accentColor: accentColor,
        isLastTab: viewModel.tabs.count == 1,
        onSelect: { onSwitchTab(tab.id) },
        onClose: { onCloseTab(tab.id) },
        onRename: { viewModel.renameTab(tab.id, title: $0) },
        onCloseOthers: {
            viewModel.tabs
                .filter { $0.id != tab.id }
                .forEach { onCloseTab($0.id) }
        },
        agentState: viewModel.agentState(for: tab.surfaceId),
        isNextActive: nextIsActive
    )
    .id(tab.id)
}
```

- [ ] **Step 2: 构建确认无编译错误**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build 2>&1 | tail -5
```

预期：`BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/TabBar/TitlebarTabsAccessory.swift
git commit -m "feat(tab-bar): pass isNextActive to suppress separator beside active tab"
```

---

## Task 3: Worktree 区块左边线

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceSidebar.swift`

### 背景

在 `ungroupedSection` 和分组内两处 worktree `VStack(spacing: 0)` 上，加 workspace accent 色左边线，强化归属感。同时将 `padding(.leading, 16)` 改为 `padding(.leading, 20)`。

- [ ] **Step 1: 修改 `ungroupedSection` 中的 worktree 区块**

找到 `ungroupedSection` 中（约第 320–356 行）：

```swift
if workspace.id == currentWorkspaceId,
   let monitor = worktreeMonitor,
   monitor.isGitRepo {
    VStack(spacing: 0) {
        Button(action: { worktreeExpanded.toggle() }) { ... }
        .padding(.leading, 14)
        ...
        if worktreeExpanded {
            WorktreeListView(...)
        }
    }
}
```

在该 `VStack(spacing: 0)` 后添加 overlay 和 padding 修改：

```swift
if workspace.id == currentWorkspaceId,
   let monitor = worktreeMonitor,
   monitor.isGitRepo {
    VStack(spacing: 0) {
        Button(action: { worktreeExpanded.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: worktreeExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 10)
                Text(monitor.worktrees.count == 1
                     ? "1 worktree"
                     : "\(monitor.worktrees.count) worktrees")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(3)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 2)

        if worktreeExpanded {
            WorktreeListView(
                monitor: monitor,
                onOpenInTab: { path in onOpenWorktreeInTab?(path) },
                onOpenInWindow: { path in onOpenWorktreeInWindow?(path) },
                onDelete: { path, _ in confirmDeleteWorktree(path: path, monitor: monitor) }
            )
        }
    }
    .overlay(alignment: .leading) {
        Rectangle()
            .fill(workspace.color.opacity(0.6))
            .frame(width: 2)
    }
    .padding(.leading, 20)
}
```

注意：同时移除 `WorktreeListView` 的 `onShowCreateForm` 参数（Task 4 会删除该参数）。

- [ ] **Step 2: 对分组内 worktree 区块做相同修改**

找到 `expandedContent` 内 `ForEach(manager.workspacesInGroup(group.id))` 中（约第 443–480 行），对 `if workspace.id == currentWorkspaceId, let monitor = worktreeMonitor, monitor.isGitRepo` 区块做与 Step 1 完全相同的修改（overlay + padding(.leading, 20)，移除 onShowCreateForm）。

- [ ] **Step 3: 构建确认无编译错误**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build 2>&1 | tail -5
```

预期：`BUILD SUCCEEDED`（Task 4 前可能有 `onShowCreateForm` 缺失警告，可忽略）

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceSidebar.swift
git commit -m "feat(sidebar): add accent-color left border to worktree section for visual hierarchy"
```

---

## Task 4: 移除 "Add Worktree" 底部按钮，迁移到 `···` 菜单

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorktreeListView.swift`
- Modify: `macos/Sources/Features/Workspace/WorkspaceSidebar.swift`

### 背景

`WorktreeListView` 底部的"+ Add Worktree"按钮体积大、割裂感强。将入口迁移到 `ExpandedWorkspaceItem` 右侧 hover 显示的 `···` 按钮菜单中。

- [ ] **Step 1: 修改 `WorktreeListView`——删除底部按钮和 `onShowCreateForm` 参数**

将 `WorktreeListView` 完整替换为：

```swift
struct WorktreeListView: View {
    @ObservedObject var monitor: GitWorktreeMonitor
    let onOpenInTab: (String) -> Void
    let onOpenInWindow: (String) -> Void
    let onDelete: (String, Bool) -> Void  // path, force

    var body: some View {
        VStack(spacing: 1) {
            ForEach(monitor.worktrees) { worktree in
                WorktreeRow(
                    worktree: worktree,
                    monitor: monitor,
                    onOpenInTab: onOpenInTab,
                    onOpenInWindow: onOpenInWindow,
                    onDelete: onDelete
                )
            }
        }
        .padding(.leading, 16)
    }
}
```

（删除 `onShowCreateForm` 参数、`addButtonHovering` state 和底部 `Button`）

- [ ] **Step 2: 在 `ExpandedWorkspaceItem` 添加 `onShowCreateForm` 回调和 `···` 按钮**

在 `struct ExpandedWorkspaceItem: View {` 的属性列表中，在 `var availableGroups: [WorkspaceGroup] = []` 之后添加：

```swift
var onShowCreateForm: (() -> Void)? = nil
```

在 `@State private var isPressed = false` 之后添加：

```swift
@State private var isMoreHovered = false
```

在 `body` 的 `HStack(spacing: 8)` 内，`Spacer()` 之后添加 `···` 按钮：

```swift
if let onShowCreateForm {
    Button {
        showMoreMenu(onShowCreateForm: onShowCreateForm)
    } label: {
        Image(systemName: "ellipsis")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .opacity(isHovering || isMoreHovered ? 1 : 0)
    .onHover { isMoreHovered = $0 }
}
```

在 `ExpandedWorkspaceItem` 中添加私有方法：

```swift
private func showMoreMenu(onShowCreateForm: @escaping () -> Void) {
    let menu = NSMenu()
    let addItem = NSMenuItem(title: "Add Worktree…", action: nil, keyEquivalent: "")
    addItem.target = WorkspaceMoreMenuTarget.shared
    addItem.action = #selector(WorkspaceMoreMenuTarget.addWorktreeClicked(_:))
    WorkspaceMoreMenuTarget.shared.onAddWorktree = onShowCreateForm
    menu.addItem(addItem)
    if let event = NSApp.currentEvent {
        NSMenu.popUpContextMenu(menu, with: event, for: NSApp.keyWindow?.contentView ?? NSView())
    }
}
```

在文件底部（`GroupHeaderRow` 之前）添加 target 类：

```swift
private class WorkspaceMoreMenuTarget: NSObject {
    static let shared = WorkspaceMoreMenuTarget()
    var onAddWorktree: (() -> Void)?

    @objc func addWorktreeClicked(_ sender: NSMenuItem) {
        onAddWorktree?()
    }
}
```

- [ ] **Step 3: 更新 `WorkspaceSidebar` 两处 `ExpandedWorkspaceItem` 调用**

在 `ungroupedSection`（约第 303 行）的 `ExpandedWorkspaceItem(...)` 中，在 `availableGroups: manager.groups` 之后添加：

```swift
onShowCreateForm: workspace.id == currentWorkspaceId ? { showWorktreeCreateForm = true } : nil
```

在 `expandedContent` 分组内（约第 425 行）的 `ExpandedWorkspaceItem(...)` 中做相同添加。

- [ ] **Step 4: 确认两处 `WorktreeListView` 调用已不传 `onShowCreateForm`**

在 `ungroupedSection`（Task 3 已处理）和分组内（Task 3 已处理）的 `WorktreeListView` 调用中，确认无 `onShowCreateForm` 参数。

- [ ] **Step 5: 构建确认无编译错误**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build 2>&1 | tail -5
```

预期：`BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Workspace/WorktreeListView.swift \
        macos/Sources/Features/Workspace/WorkspaceSidebar.swift
git commit -m "feat(sidebar): move Add Worktree to workspace item context menu, remove bottom button"
```

---

## 验收检查

完成所有 Task 后，手动运行应用验证：

1. **Tab 分隔线**：打开多个 tab，非 active tab 之间有细竖线；active tab 两侧无竖线；active tab 有轻微背景色块；底部 accent 色条仍存在
2. **Tab hover**：hover 非 active tab 时有浅色背景，无分隔线突变
3. **Worktree 左边线**：展开 worktree 列表时，左侧有 workspace accent 色竖线；折叠时竖线消失
4. **`···` 菜单**：hover workspace item 时右侧出现 `···`；点击弹出菜单含"Add Worktree…"；点击后弹出创建表单
5. **底部按钮已移除**：worktree 列表底部无"+ Add Worktree"按钮
