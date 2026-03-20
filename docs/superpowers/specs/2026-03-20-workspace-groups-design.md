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

新增模型，存储路径：`~/.config/poltertty/workspaces/groups.json`（数组，一个文件）。

```swift
struct WorkspaceGroup: Codable, Identifiable {
    let id: UUID
    var name: String
    var orderIndex: Int       // 控制分组在 sidebar 中的顺序
    var isCollapsed: Bool     // expanded sidebar 中的展开/折叠状态
    var isCollapsedIcon: Bool // collapsed sidebar 中是否收起成单图标
    let createdAt: Date
    var updatedAt: Date
}
```

**groups.json 示例**：

```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "name": "Work",
    "orderIndex": 0,
    "isCollapsed": false,
    "isCollapsedIcon": false,
    "createdAt": "2026-03-20T10:00:00Z",
    "updatedAt": "2026-03-20T10:00:00Z"
  }
]
```

### 2.2 WorkspaceModel 变更

新增字段：

```swift
var groupId: UUID?  // nil = 未分组
```

使用 `decodeIfPresent` 读取，向后兼容旧版 snapshot 文件（旧文件读取时 groupId 自动为 nil）。

### 2.3 WorkspaceManager 变更

```swift
@Published var groups: [WorkspaceGroup] = []
```

新增方法：
- `createGroup(name:) -> WorkspaceGroup`
- `renameGroup(id:name:)`
- `deleteGroup(id:)` — 先将该分组下所有 workspace 的 groupId 置 nil
- `moveWorkspace(id:toGroup:)` — toGroup 为 nil 表示移入未分组
- `reorderGroups([WorkspaceGroup])` — 更新 orderIndex

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
- 左侧：`▾`/`▸` chevron（控制折叠）+ 分组名
- 右侧：`···` 按钮（hover 时显示），菜单项：Rename、Delete
- 右键标头等同于点击 `···`
- 点击标头任意位置切换折叠状态

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

**拖拽重排**：
- workspace 可在分组间、未分组区域之间拖拽
- 分组标头可拖拽改变分组顺序
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
[WK]      ← 分组收起时的缩写图标
─────
▾         ← 分组展开时（chevron 占位，下方显示 workspace 图标）
[ws-c]
[ws-d]
─────
+
```

### 4.2 交互细节

**分组分隔线**：组与组之间、未分组和第一个分组之间用 `Divider` 隔开。

**分组折叠图标**（`isCollapsedIcon = true`）：
- 圆角矩形图标，内容为分组名前两个字符（大写）
- 颜色：中性色（`Color.secondary.opacity(0.15)`），与 workspace 颜色不冲突
- 点击展开该分组（`isCollapsedIcon = false`，显示其下 workspace 图标）
- 右键：Rename、Delete

**分组展开态**（`isCollapsedIcon = false`）：
- 直接显示分组内 workspace 图标列表，样式与未分组图标一致
- 分组上方显示一个小 chevron（`▾`）点击可重新收起

**状态独立**：`isCollapsedIcon`（collapsed sidebar 中的收起状态）与 `isCollapsed`（expanded sidebar 中的折叠状态）相互独立，分别持久化。

---

## 5. 持久化与一致性

### 5.1 保存触发时机

| 操作 | 触发保存 |
|------|----------|
| 创建/删除/重命名分组 | groups.json |
| 拖拽改变分组顺序 | groups.json |
| 展开/折叠分组（任一 sidebar 模式） | groups.json |
| workspace 移入/移出分组 | groups.json + 对应 workspace snapshot |

### 5.2 一致性保证

| 情况 | 处理 |
|------|------|
| 删除分组 | 先将该分组所有 workspace 的 groupId 置 nil 并保存，再删除分组记录 |
| workspace 引用不存在的 groupId | 启动时检测，自动将 groupId 重置为 nil |
| groups.json 不存在 | 视为空数组，首次保存时创建 |
| groups.json 损坏/解析失败 | 忽略，视为空数组，下次保存时覆盖 |

### 5.3 向后兼容

旧版本 workspace snapshot 无 `groupId` 字段，`decodeIfPresent` 返回 nil，自动归入未分组，无需迁移脚本。

---

## 6. Quick Switcher 集成

`Cmd+Ctrl+W` Quick Switcher 中：
- workspace 行副标题显示所属分组名（未分组则不显示）
- 支持按分组名搜索/过滤

---

## 7. 边界情况

| 情况 | 处理 |
|------|------|
| 分组内所有 workspace 被删除 | 分组保留（空分组），用户手动删除 |
| 拖拽 workspace 到已折叠分组 | 目标分组自动展开，workspace 插入底部 |
| Temporary workspace | 始终在 Temporary 区域，不可拖入分组 |
| 分组名为空 | 创建/重命名时校验，不允许提交 |
| 分组名重复 | 允许（靠 UUID 区分），不做唯一性限制 |

---

## 8. 文件改动范围

| 文件 | 改动类型 |
|------|----------|
| `WorkspaceModel.swift` | 新增 `groupId: UUID?` 字段 |
| `WorkspaceManager.swift` | 新增 `groups` 属性 + 分组 CRUD 方法 + groups.json 读写 |
| `WorkspaceSidebar.swift` | 新增分组标头、折叠逻辑、拖拽支持、右键菜单扩展 |
| `WorkspaceQuickSwitcher.swift` | 副标题显示分组名 |
| 新文件 `WorkspaceGroup.swift` | `WorkspaceGroup` 模型定义 |

---

## 9. 不在本期范围内

- 分组颜色/图标自定义（可在后续版本扩展）
- 分组级别的快捷键
- 按分组批量操作 workspace
- 分组嵌套
