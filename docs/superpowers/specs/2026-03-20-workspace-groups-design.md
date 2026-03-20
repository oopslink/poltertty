# Workspace 分组功能设计 Spec

**Date**: 2026-03-20
**Status**: Approved
**Platform**: macOS only

---

## 1. 概述

为 Poltertty 的 Workspace Sidebar 添加手动文件夹分组功能，允许用户将 workspace 归入命名分组，提升大量 workspace 时的组织效率。

**核心原则**：
- 两级扁平结构，不支持嵌套分组
- 每个 workspace 属于 0 或 1 个分组（nil = 未分组）
- 分组是用户手动创建和管理的，系统不自动分组
- Temporary workspace 不参与分组

---

## 2. 数据模型

### 2.1 WorkspaceGroup

新增模型，文件位置：`WorkspaceGroup.swift`（`macos/Sources/Features/Workspace/`）。

存储路径由 `WorkspaceManager` 计算：

```swift
private var groupsFilePath: String {
    (storageDir as NSString).appendingPathComponent("groups.json")
}
```

`storageDir` 与现有 workspace snapshot 使用相同的目录（`PolterttyConfig.shared.workspaceDir`，默认 `~/.config/poltertty/workspaces/`）。

**与现有 `loadAll()` 兼容性**：现有 `loadAll()` 扫描目录时会命中 `groups.json`（因为 `.hasSuffix(".json")`），但随后 `UUID(uuidString: "groups")` 返回 nil，该条目被 `continue` 跳过，不会崩溃也不会误读。新格式的扫描逻辑过滤"UUID 格式命名的子目录"，`groups.json` 不是目录，也不会被命中。两种路径均安全，但安全保证来自 UUID 解析失败，而非文件名结构性保护。实现时不得将 `groups.json` 移入 UUID 命名的子目录。

```swift
struct WorkspaceGroup: Codable, Identifiable {
    let id: UUID
    var name: String
    var orderIndex: Int       // 控制分组在 sidebar 中的顺序
    var isExpanded: Bool      // expanded sidebar 中的展开/折叠状态（true = 展开）
    var isCollapsedIcon: Bool // collapsed sidebar 中是否收起成单图标（true = 收起）
    let createdAt: Date
    var updatedAt: Date
}
```

注意：`isExpanded` 默认 `true`（新建分组默认展开）。命名刻意区别于 `WorkspaceSidebar` 已有的 `@Binding var isCollapsed: Bool`（表示 sidebar 整体折叠）。

**groups.json 示例**：

```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "name": "Work",
    "orderIndex": 0,
    "isExpanded": true,
    "isCollapsedIcon": false,
    "createdAt": "2026-03-20T10:00:00Z",
    "updatedAt": "2026-03-20T10:00:00Z"
  }
]
```

### 2.2 WorkspaceModel 变更

新增字段：

```swift
var groupId: UUID?    // nil = 未分组
var groupOrder: Int   // workspace 在所属区域（某分组或未分组区域）内的排列顺序
```

由于 `WorkspaceModel` 使用手写 `init(from decoder:)`（非 synthesized），必须在其中显式添加：

```swift
groupId    = try container.decodeIfPresent(UUID.self, forKey: .groupId)
groupOrder = try container.decodeIfPresent(Int.self, forKey: .groupOrder) ?? 0
```

旧版 snapshot 文件无这两个字段，解码后 `groupId = nil`、`groupOrder = 0`。

### 2.3 WorkspaceManager 变更

```swift
@Published var groups: [WorkspaceGroup] = []
```

新增方法：

| 方法 | 说明 |
|------|------|
| `createGroup(name:) -> WorkspaceGroup` | 创建分组，`orderIndex = groups.count`，`isExpanded = true` |
| `renameGroup(id:name:)` | 重命名，更新 `updatedAt`，保存 groups.json |
| `deleteGroup(id:)` | 先将该分组所有 workspace 的 `groupId` 置 nil 并各自保存 snapshot，再删除分组记录，保存 groups.json |
| `moveWorkspace(id:toGroup:insertAfter:)` | `toGroup` 为 nil 表示移入未分组；`insertAfter` 为目标位置前一个 workspace 的 id（nil = 插入末尾）；重新计算受影响 workspace 的 `groupOrder` 后批量保存 |
| `reorderGroups([UUID])` | 接受新的分组 id 顺序，重新计算 `orderIndex`，保存 groups.json |

### 2.4 workspace 在分组内的排序

`groupOrder: Int` 字段记录 workspace 在其所属区域（某个分组或未分组区域）内的位置。

**初始化策略（解决旧 workspace 全为 0 的问题）**：在 `loadAll()` 加载完所有 workspace 和 groups 后，对 `groupOrder == 0` 的 workspace 执行一次修正 pass：按 `createdAt` 升序为同一区域内的 workspace 重新分配连续的 `groupOrder`（0, 1, 2, …），并静默保存。此 pass 仅在检测到同一区域内有多于一个 `groupOrder == 0` 的 workspace 时触发。

Sidebar 渲染时按 `groupOrder` 升序排列；拖拽操作结束后 `WorkspaceManager` 重新计算受影响 workspace 的 `groupOrder` 并批量保存 snapshot。

### 2.5 启动时一致性检测

在 `WorkspaceManager.init()` 的 `loadAll()` 之后，执行一次一致性检测 pass：

```swift
private func fixGroupConsistency() {
    var dirty = false
    for i in workspaces.indices {
        if let gid = workspaces[i].groupId,
           !groups.contains(where: { $0.id == gid }) {
            workspaces[i].groupId = nil
            save(workspaces[i])
            dirty = true
        }
    }
    // groupOrder 修正（见 2.4）
}
```

此方法在 `loadGroups()` 和 `loadAll()` 均完成后调用，确保 groups 和 workspaces 都已载入。

---

## 3. Expanded Sidebar UI

### 3.1 布局结构

```
WORKSPACES                    ✦ ‹ +
─────────────────────────────────
[未分组区域]
  workspace-a
  workspace-b

▾ Work                        ···
  workspace-c
  workspace-d

▾ Personal                    ···
  workspace-e

─────────────────────────────────
[New] | [Temporary]
```

### 3.2 交互细节

**未分组区域**：始终显示在分组列表顶部，无标头，无折叠能力。

**分组标头行**：
- 左侧：`▾`/`▸` chevron（控制折叠，对应 `isExpanded`）+ 分组名
- 右侧：`···` 按钮（hover 时显示），菜单项：Rename、Delete
- 右键标头等同于点击 `···`
- 点击标头任意位置切换 `isExpanded`，立即保存 groups.json

**创建分组入口**：在未分组 workspace 上右键，新增菜单项：
```
Move to Group ▸
  [现有分组列表]
  ─────
  New Group…
```

在已分组 workspace 上右键，增加：
```
Move to Group ▸
  [其他分组列表]
  Ungrouped
  ─────
  New Group…
```

"New Group…" 触发一个 `NSAlert` sheet（以 `beginSheetModal(for: NSApp.keyWindow)` 方式 attach），包含文本输入框，点击 OK 创建分组并将该 workspace 移入。同一交互模式用于 `CollapsedGroupIcon` 的 Rename 操作。

**拖拽重排**：
- workspace 可在分组间、未分组区域之间拖拽，松手位置决定插入点
- 拖拽时显示插入线（drop indicator，高度 2px，颜色 `Color.accentColor`）
- 拖拽 workspace 悬停在已折叠分组标头超过 0.8 秒后，该分组自动预览展开（仅 UI 临时展开，`isExpanded` 不变）；若松手在其中则永久展开并插入，若拖离则收回
- 分组标头可拖拽改变分组顺序，同样显示插入线
- 使用 SwiftUI `.onDrag` / `.onDrop`

---

## 4. Collapsed Sidebar UI

### 4.1 布局结构

```
‹  ✦
─────
[ws-a]    ← 未分组
[ws-b]
─────     ← 分组分隔线
[WK]      ← 分组收起时的缩写图标（CollapsedGroupIcon）
─────
▾         ← 分组展开时（chevron 占位，下方显示 workspace 图标）
[ws-c]
[ws-d]
─────
+
```

### 4.2 新增 View：CollapsedGroupIcon

Collapsed sidebar 中的分组图标是**独立的新 View `CollapsedGroupIcon`**，不是 `CollapsedWorkspaceIcon` 的变体。它代表分组而非 workspace，因此不需要 `onClose`/`onEdit` 等 workspace 专属回调，不受 `workspace-rules.md` 中"两种模式同步"规则约束（该规则针对 workspace 操作）。`CollapsedGroupIcon` 在 `WorkspaceSidebar.swift` 中实现（与 `CollapsedWorkspaceIcon`、`ExpandedWorkspaceItem` 同文件）。

```swift
struct CollapsedGroupIcon: View {
    let group: WorkspaceGroup
    let onToggle: () -> Void   // 展开/折叠（切换 isCollapsedIcon）
    let onRename: () -> Void   // 触发 NSAlert sheet
    let onDelete: () -> Void   // 触发删除确认 alert
}
```

**分组折叠图标**（`isCollapsedIcon = true`）：
- 圆角矩形图标，内容取分组名的前两个 Unicode scalar（大写），正确处理 emoji 和多字节字符
- 颜色：中性色（`Color.secondary.opacity(0.15)`），与 workspace 颜色不冲突
- 点击将 `isCollapsedIcon = false`，显示其下 workspace 图标
- 右键：Rename（NSAlert sheet）、Delete（确认 alert）

**分组展开态**（`isCollapsedIcon = false`）：
- 分组上方显示一个小 `▾` chevron，点击将 `isCollapsedIcon = true`
- 直接显示分组内 workspace 图标列表，使用 `CollapsedWorkspaceIcon`

**状态独立**：`isCollapsedIcon`（collapsed sidebar 收起状态）与 `isExpanded`（expanded sidebar 折叠状态）相互独立，分别持久化到 groups.json。

---

## 5. 持久化与一致性

### 5.1 保存触发时机

| 操作 | 触发保存 |
|------|----------|
| 创建/删除/重命名分组 | groups.json |
| 拖拽改变分组顺序 | groups.json |
| 切换分组展开/折叠（任一 sidebar 模式） | groups.json |
| workspace 移入/移出分组 | groups.json + 受影响 workspace snapshots |
| 拖拽改变 workspace 在区域内的顺序 | 受影响 workspace snapshots |

### 5.2 一致性保证

| 情况 | 处理 |
|------|------|
| 删除分组 | 先将该分组所有 workspace 的 groupId 置 nil 并保存，再删除分组记录 |
| workspace 引用不存在的 groupId | `fixGroupConsistency()` 于启动时检测并重置为 nil（见 §2.5） |
| groups.json 不存在 | 视为空数组，首次保存时创建 |
| groups.json 损坏/解析失败 | 忽略，视为空数组，下次保存时覆盖 |

### 5.3 向后兼容

旧版本 workspace snapshot 无 `groupId` / `groupOrder` 字段，解码后分别为 nil / 0，自动归入未分组。`fixGroupConsistency()` 中的 groupOrder 修正 pass 会按 `createdAt` 重建排序，保持相对顺序。

---

## 6. Quick Switcher 集成

`Cmd+Ctrl+W` Quick Switcher（`WorkspaceQuickSwitcher`）：
- workspace 行在 `rootDir` 下方新增第三行显示所属分组名（未分组则不显示第三行），字体 `system(size: 9)`，颜色 `secondary.opacity(0.6)`
- `filtered` 计算属性在现有 `name` / `tags` OR 条件中新增：通过 `WorkspaceManager.shared.groups.first(where: { $0.id == ws.groupId })?.name` 获取分组名，加入过滤逻辑

---

## 7. 边界情况

| 情况 | 处理 |
|------|------|
| 分组内所有 workspace 被删除 | 分组保留（空分组），用户手动删除 |
| 拖拽 workspace 到已折叠分组（expanded sidebar）| 悬停 0.8s 后预览展开；松手后永久展开（`isExpanded = true`），workspace 插入目标位置，保存 groups.json |
| Temporary workspace | 始终在 Temporary 区域，不可拖入分组 |
| 分组名为空 | 创建/重命名时校验，不允许提交（OK 按钮 disabled） |
| 分组名重复 | 允许（靠 UUID 区分），不做唯一性限制 |
| 分组名首字符为 emoji | 缩写图标取前两个 Unicode scalar，不截断多字节字符 |

---

## 8. 文件改动范围

| 文件 | 改动类型 |
|------|----------|
| `WorkspaceGroup.swift`（新建） | `WorkspaceGroup` 模型定义 |
| `WorkspaceModel.swift` | 新增 `groupId: UUID?`、`groupOrder: Int`；在手写 `init(from:)` 中添加 `decodeIfPresent` |
| `WorkspaceManager.swift` | 新增 `groups` 属性、`groupsFilePath`、分组 CRUD 方法、groups.json 读写、`fixGroupConsistency()` |
| `WorkspaceSidebar.swift` | 新增分组标头 View、`isExpanded` 折叠逻辑、拖拽支持（含插入线）、右键菜单扩展；新增 `CollapsedGroupIcon` |
| `WorkspaceQuickSwitcher.swift` | 副标题显示分组名（第三行）；`filtered` 加入分组名搜索条件 |

---

## 9. 不在本期范围内

- 分组颜色/图标自定义（可在后续版本扩展）
- 分组级别的快捷键
- 按分组批量操作 workspace
- 分组嵌套
