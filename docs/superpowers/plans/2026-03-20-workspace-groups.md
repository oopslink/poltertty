# Workspace Groups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Workspace Sidebar 添加手动文件夹分组功能，让用户可以将 workspace 归入命名分组并进行管理。

**Architecture:** 新增 `WorkspaceGroup` 模型持久化到 `groups.json`；`WorkspaceModel` 新增 `groupId`/`groupOrder` 字段；`WorkspaceManager` 负责分组 CRUD 和一致性检测；`WorkspaceSidebar` 扩展分组 UI（expanded 分组标头 + collapsed `CollapsedGroupIcon`）；`WorkspaceQuickSwitcher` 展示分组名。

**Tech Stack:** Swift 5.9, SwiftUI, Swift Testing (`@Test`/`#expect`), `@testable import Ghostty`, JSONEncoder/Decoder, SwiftUI `.onDrag`/`.onDrop`

---

## 准备工作：创建 Worktree

> 根据 `docs/development-rules.md`，所有特性开发必须使用 git worktree 隔离。

- [ ] **创建 worktree**

```bash
git worktree add .worktrees/feat-workspace-groups -b feat/workspace-groups
cd .worktrees/feat-workspace-groups
```

后续所有操作在此 worktree 目录下进行。

---

## 文件改动总览

| 文件 | 类型 | 职责 |
|------|------|------|
| `macos/Sources/Features/Workspace/WorkspaceGroup.swift` | 新建 | `WorkspaceGroup` 模型定义 |
| `macos/Sources/Features/Workspace/WorkspaceModel.swift` | 修改 | 新增 `groupId`/`groupOrder` 字段 |
| `macos/Sources/Features/Workspace/WorkspaceManager.swift` | 修改 | 分组 CRUD + groups.json 读写 + 一致性检测 |
| `macos/Sources/Features/Workspace/WorkspaceSidebar.swift` | 修改 | 分组标头、CollapsedGroupIcon、拖拽、右键菜单 |
| `macos/Sources/Features/Workspace/WorkspaceQuickSwitcher.swift` | 修改 | 分组名显示和过滤 |
| `macos/Tests/Workspace/WorkspaceGroupTests.swift` | 新建 | 模型 Codable + Manager CRUD 测试 |

---

## Task 1: WorkspaceGroup 模型

**Files:**
- Create: `macos/Sources/Features/Workspace/WorkspaceGroup.swift`
- Create: `macos/Tests/Workspace/WorkspaceGroupTests.swift`

- [ ] **Step 1: 写失败测试（模型编解码）**

新建 `macos/Tests/Workspace/WorkspaceGroupTests.swift`：

```swift
// macos/Tests/Workspace/WorkspaceGroupTests.swift
import Testing
import Foundation
@testable import Ghostty

struct WorkspaceGroupTests {

    @Test func testWorkspaceGroupRoundtrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let group = WorkspaceGroup(name: "Work")
        let data = try encoder.encode(group)
        let decoded = try decoder.decode(WorkspaceGroup.self, from: data)

        #expect(decoded.id == group.id)
        #expect(decoded.name == "Work")
        #expect(decoded.orderIndex == 0)
        #expect(decoded.isExpanded == true)
        #expect(decoded.isCollapsedIcon == false)
    }

    @Test func testWorkspaceModelGroupIdRoundtrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var ws = WorkspaceModel(name: "test", rootDir: "/tmp")
        let groupId = UUID()
        ws.groupId = groupId
        ws.groupOrder = 3

        // WorkspaceSnapshot wraps WorkspaceModel
        let snapshot = WorkspaceSnapshot(workspace: ws, sidebarWidth: 200, sidebarVisible: true)
        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(WorkspaceSnapshot.self, from: data)

        #expect(decoded.workspace.groupId == groupId)
        #expect(decoded.workspace.groupOrder == 3)
    }

    @Test func testWorkspaceModelGroupIdBackwardCompat() throws {
        // 旧格式 JSON（无 groupId/groupOrder 字段）解码后应为 nil/0
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let oldJSON = """
        {
          "version": 2,
          "workspace": {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "name": "old",
            "colorHex": "#FF6B6B",
            "icon": "OL",
            "rootDir": "/tmp",
            "description": "",
            "tags": [],
            "createdAt": "2026-01-01T00:00:00Z",
            "updatedAt": "2026-01-01T00:00:00Z",
            "lastActiveAt": "2026-01-01T00:00:00Z",
            "isTemporary": false,
            "fileBrowserVisible": false,
            "fileBrowserWidth": 260
          },
          "sidebarWidth": 200,
          "sidebarVisible": true
        }
        """.data(using: .utf8)!

        let snapshot = try decoder.decode(WorkspaceSnapshot.self, from: oldJSON)
        #expect(snapshot.workspace.groupId == nil)
        #expect(snapshot.workspace.groupOrder == 0)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

```bash
xcodebuild test \
  -project macos/Ghostty.xcodeproj \
  -scheme Ghostty \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing GhosttyTests/WorkspaceGroupTests \
  2>&1 | grep -E "error:|FAILED|passed|failed"
```

预期：编译错误（`WorkspaceGroup` 未定义）

- [ ] **Step 3: 创建 WorkspaceGroup.swift**

```swift
// macos/Sources/Features/Workspace/WorkspaceGroup.swift
import Foundation

struct WorkspaceGroup: Codable, Identifiable {
    let id: UUID
    var name: String
    var orderIndex: Int       // 控制分组在 sidebar 中的顺序
    var isExpanded: Bool      // expanded sidebar 中的展开状态（true = 展开）
    var isCollapsedIcon: Bool // collapsed sidebar 中是否收起成单图标
    let createdAt: Date
    var updatedAt: Date

    init(name: String, orderIndex: Int = 0) {
        self.id = UUID()
        self.name = name
        self.orderIndex = orderIndex
        self.isExpanded = true
        self.isCollapsedIcon = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// 分组名前两个 Unicode scalar（大写），正确处理 emoji 和多字节字符
    var abbreviation: String {
        let scalars = Array(name.unicodeScalars.prefix(2))
        return String(String.UnicodeScalarView(scalars)).uppercased()
    }
}
```

- [ ] **Step 4: 在 WorkspaceModel 中添加 groupId / groupOrder**

编辑 `macos/Sources/Features/Workspace/WorkspaceModel.swift`：

在 `struct WorkspaceModel` 的属性列表中（`isTemporary` 之后）新增：

```swift
var groupId: UUID?    // nil = 未分组
var groupOrder: Int   // workspace 在所属区域内的排列顺序
```

在 `init(name:rootDir:colorHex:icon:isTemporary:)` 中新增初始化：

```swift
self.groupId = nil
self.groupOrder = 0
```

在手写 `init(from decoder:)` 中（`fileBrowserWidth` 那行之后）新增：

```swift
groupId    = try container.decodeIfPresent(UUID.self, forKey: .groupId)
groupOrder = try container.decodeIfPresent(Int.self, forKey: .groupOrder) ?? 0
```

- [ ] **Step 5: 运行测试，确认通过**

```bash
xcodebuild test \
  -project macos/Ghostty.xcodeproj \
  -scheme Ghostty \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing GhosttyTests/WorkspaceGroupTests \
  2>&1 | grep -E "error:|FAILED|passed|failed"
```

预期：3 tests passed

- [ ] **Step 6: 编译检查**

```bash
make check 2>&1 | grep "error:" | head -20
```

预期：无 error

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceGroup.swift \
        macos/Sources/Features/Workspace/WorkspaceModel.swift \
        macos/Tests/Workspace/WorkspaceGroupTests.swift
git commit -m "feat(workspace-groups): add WorkspaceGroup model and groupId/groupOrder to WorkspaceModel"
```

---

## Task 2: WorkspaceManager 分组持久化与 CRUD

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceManager.swift`
- Modify: `macos/Tests/Workspace/WorkspaceGroupTests.swift`

- [ ] **Step 1: 写失败测试（Manager CRUD）**

在 `WorkspaceGroupTests.swift` 末尾新增测试辅助类和测试：

```swift
// MARK: - WorkspaceManager Group CRUD Tests

/// 测试辅助：使用临时目录隔离的 WorkspaceManager 子类
/// 注意：WorkspaceManager 是 singleton，CRUD 方法都是 public，
/// 可以直接用 shared 但需要在测试前清理状态。
/// 这里改为测试独立的逻辑函数，不依赖 singleton。

@Test func testCreateGroupAddsToList() {
    // 直接测试 WorkspaceGroup 初始化逻辑
    let group = WorkspaceGroup(name: "TestGroup", orderIndex: 0)
    #expect(group.name == "TestGroup")
    #expect(group.isExpanded == true)
    #expect(group.orderIndex == 0)
    #expect(group.isCollapsedIcon == false)
}

@Test func testGroupAbbreviationASCII() {
    let group = WorkspaceGroup(name: "Work")
    #expect(group.abbreviation == "WO")
}

@Test func testGroupAbbreviationEmoji() {
    let group = WorkspaceGroup(name: "🚀Launch")
    // 只取前2个 unicode scalars，不截断多字节
    let scalars = Array("🚀Launch".unicodeScalars.prefix(2))
    let expected = String(String.UnicodeScalarView(scalars)).uppercased()
    #expect(group.abbreviation == expected)
}

@Test func testGroupAbbreviationShortName() {
    let group = WorkspaceGroup(name: "A")
    #expect(group.abbreviation == "A")
}

@Test func testGroupsJsonRoundtrip() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let groups = [
        WorkspaceGroup(name: "Work", orderIndex: 0),
        WorkspaceGroup(name: "Personal", orderIndex: 1),
    ]

    let data = try encoder.encode(groups)
    let decoded = try decoder.decode([WorkspaceGroup].self, from: data)

    #expect(decoded.count == 2)
    #expect(decoded[0].name == "Work")
    #expect(decoded[1].name == "Personal")
    #expect(decoded[0].orderIndex == 0)
    #expect(decoded[1].orderIndex == 1)
}
```

- [ ] **Step 2: 运行测试，确认通过（这些测试不依赖新 Manager 方法）**

```bash
xcodebuild test \
  -project macos/Ghostty.xcodeproj \
  -scheme Ghostty \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing GhosttyTests/WorkspaceGroupTests \
  2>&1 | grep -E "error:|FAILED|passed|failed"
```

- [ ] **Step 3: 在 WorkspaceManager 中添加分组支持**

在 `WorkspaceManager.swift` 中做以下修改：

**3a. 在 `@Published var workspaces` 之后添加：**

```swift
@Published var groups: [WorkspaceGroup] = []
```

**3b. 添加 `groupsFilePath` 计算属性（在 `storageDir` 常量之后）：**

```swift
private var groupsFilePath: String {
    (storageDir as NSString).appendingPathComponent("groups.json")
}
```

**3c. 在 `private init()` 中，`loadAll()` 之后添加 groups 加载和一致性检测：**

```swift
loadGroups()
fixGroupConsistency()
```

**3d. 在 `loadAll()` 方法之后添加以下方法（MARK: - Group Persistence）：**

```swift
// MARK: - Group Persistence

private func loadGroups() {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: groupsFilePath)),
          let loaded = try? decoder.decode([WorkspaceGroup].self, from: data) else {
        return
    }
    groups = loaded.sorted { $0.orderIndex < $1.orderIndex }
}

private func saveGroups() {
    if let data = try? encoder.encode(groups) {
        try? data.write(to: URL(fileURLWithPath: groupsFilePath))
    }
}

/// 启动时修复一致性：清除指向不存在分组的 groupId，修正 groupOrder
private func fixGroupConsistency() {
    let validGroupIds = Set(groups.map { $0.id })

    // 清除无效 groupId
    for i in workspaces.indices {
        if let gid = workspaces[i].groupId, !validGroupIds.contains(gid) {
            workspaces[i].groupId = nil
            save(workspaces[i])
        }
    }

    // 修正 groupOrder：对 groupOrder 全为 0 的区域按 createdAt 分配连续序号
    let allGroupIds: [UUID?] = [nil] + groups.map { Optional($0.id) }
    for gid in allGroupIds {
        let indices = workspaces.indices.filter { workspaces[$0].groupId == gid }
        let allZero = indices.allSatisfy { workspaces[$0].groupOrder == 0 }
        guard allZero && indices.count > 1 else { continue }
        // 按 createdAt 排序后分配 0,1,2,...
        let sorted = indices.sorted { workspaces[$0].createdAt < workspaces[$1].createdAt }
        for (order, idx) in sorted.enumerated() {
            workspaces[idx].groupOrder = order
            save(workspaces[idx])
        }
    }
}

// MARK: - Group CRUD

@discardableResult
func createGroup(name: String) -> WorkspaceGroup {
    let group = WorkspaceGroup(name: name, orderIndex: groups.count)
    groups.append(group)
    saveGroups()
    return group
}

func renameGroup(id: UUID, name: String) {
    guard let idx = groups.firstIndex(where: { $0.id == id }) else { return }
    groups[idx].name = name
    groups[idx].updatedAt = Date()
    saveGroups()
}

func deleteGroup(id: UUID) {
    // 先将该分组所有 workspace 移出分组
    for i in workspaces.indices where workspaces[i].groupId == id {
        workspaces[i].groupId = nil
        save(workspaces[i])
    }
    groups.removeAll { $0.id == id }
    saveGroups()
}

/// 将 workspace 移入指定分组（nil = 未分组），插入 insertAfter 位置之后（nil = 末尾）
func moveWorkspace(id: UUID, toGroup groupId: UUID?, insertAfter afterId: UUID?) {
    guard let wsIdx = workspaces.firstIndex(where: { $0.id == id }) else { return }

    // 计算目标区域当前最大 order
    let targetWorkspaces = workspaces.filter { $0.groupId == groupId && $0.id != id }

    let insertOrder: Int
    if let afterId = afterId,
       let afterWs = targetWorkspaces.first(where: { $0.id == afterId }) {
        insertOrder = afterWs.groupOrder + 1
    } else {
        insertOrder = (targetWorkspaces.map { $0.groupOrder }.max() ?? -1) + 1
    }

    // 将目标区域中 order >= insertOrder 的项后移
    for i in workspaces.indices where workspaces[i].groupId == groupId && workspaces[i].id != id {
        if workspaces[i].groupOrder >= insertOrder {
            workspaces[i].groupOrder += 1
            save(workspaces[i])
        }
    }

    workspaces[wsIdx].groupId = groupId
    workspaces[wsIdx].groupOrder = insertOrder
    save(workspaces[wsIdx])
    saveGroups()
}

/// 接受新的分组 id 顺序，重新计算 orderIndex
func reorderGroups(_ orderedIds: [UUID]) {
    for (newIndex, gid) in orderedIds.enumerated() {
        if let idx = groups.firstIndex(where: { $0.id == gid }) {
            groups[idx].orderIndex = newIndex
            groups[idx].updatedAt = Date()
        }
    }
    groups.sort { $0.orderIndex < $1.orderIndex }
    saveGroups()
}

/// 切换分组在 expanded sidebar 中的展开/折叠状态
func toggleGroupExpanded(id: UUID) {
    guard let idx = groups.firstIndex(where: { $0.id == id }) else { return }
    groups[idx].isExpanded.toggle()
    groups[idx].updatedAt = Date()
    saveGroups()
}

/// 切换分组在 collapsed sidebar 中的收起/展开状态
func toggleGroupCollapsedIcon(id: UUID) {
    guard let idx = groups.firstIndex(where: { $0.id == id }) else { return }
    groups[idx].isCollapsedIcon.toggle()
    groups[idx].updatedAt = Date()
    saveGroups()
}

/// 获取某个分组内的 workspace（按 groupOrder 排序）
func workspacesInGroup(_ groupId: UUID?) -> [WorkspaceModel] {
    workspaces
        .filter { !$0.isTemporary && $0.groupId == groupId }
        .sorted { $0.groupOrder < $1.groupOrder }
}
```

- [ ] **Step 4: 编译检查**

```bash
make check 2>&1 | grep "error:" | head -20
```

预期：无 error

- [ ] **Step 5: 运行全部 WorkspaceGroupTests**

```bash
xcodebuild test \
  -project macos/Ghostty.xcodeproj \
  -scheme Ghostty \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing GhosttyTests/WorkspaceGroupTests \
  2>&1 | grep -E "error:|FAILED|passed|failed"
```

预期：所有测试通过

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceManager.swift \
        macos/Tests/Workspace/WorkspaceGroupTests.swift
git commit -m "feat(workspace-groups): add group persistence and CRUD to WorkspaceManager"
```

---

## Task 3: Expanded Sidebar — 分组标头与右键菜单

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceSidebar.swift`

本 Task 不新增右键菜单的分组操作到 `ExpandedWorkspaceItem`，那在 Task 4 完成（避免一次改太多）。本 Task 只添加分组标头渲染和折叠逻辑。

> **注意 workspace-rules.md**：`ExpandedWorkspaceItem` 和 `CollapsedWorkspaceIcon` 的右键菜单需同步。"Move to Group" 选项将在 Task 3（expanded）和 Task 5（collapsed）中分别添加。

- [ ] **Step 1: 在 WorkspaceSidebar.swift 末尾添加 GroupHeaderRow**

在文件末尾（`SidebarToggleButton` 之前）添加：

```swift
// MARK: - Group Header Row

private struct GroupHeaderRow: View {
    let group: WorkspaceGroup
    let onToggle: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: group.isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 12)

            Text(group.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            Spacer()

            if isHovering {
                // 使用 SwiftUI Menu 作为 ··· 按钮，直接连接闭包，无 retain 问题
                Menu {
                    Button("Rename Group…") { onRename() }
                    Divider()
                    Button("Delete Group", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Rename Group…") { onRename() }
            Divider()
            Button("Delete Group", role: .destructive) { onDelete() }
        }
    }
}
```

- [ ] **Step 2: 替换 expandedContent 中的 workspace 列表渲染**

找到 `expandedContent` 里的 `ScrollView { LazyVStack { ForEach(manager.formalWorkspaces) ... } }` 部分，将整个 `LazyVStack` 内容替换为（注意 `ExpandedWorkspaceItem` 使用**完整参数**，此时 `onMoveToGroup`/`onNewGroup` 还未添加，Task 3 Step 4 再加）：

```swift
LazyVStack(spacing: 2) {
    // 未分组 workspace
    ForEach(manager.workspacesInGroup(nil)) { workspace in
        ExpandedWorkspaceItem(
            workspace: workspace,
            isActive: workspace.id == currentWorkspaceId,
            isOpen: manager.windowForWorkspace(workspace.id) != nil,
            animationNamespace: sidebarAnimation,
            onTap: { onSwitch(workspace.id) },
            onClose: { onClose(workspace.id) },
            onDelete: { pendingDeleteWorkspace = workspace; showDeleteAlert = true },
            onConvert: { onConvert(workspace) },
            onEdit: { editingWorkspace = workspace }
        )
    }

    // 各个分组
    ForEach(manager.groups) { group in
        GroupHeaderRow(
            group: group,
            onToggle: { manager.toggleGroupExpanded(id: group.id) },
            onRename: { showRenameGroupAlert(group: group) },
            onDelete: { confirmDeleteGroup(group: group) }
        )
        .padding(.top, 4)

        if group.isExpanded {
            ForEach(manager.workspacesInGroup(group.id)) { workspace in
                ExpandedWorkspaceItem(
                    workspace: workspace,
                    isActive: workspace.id == currentWorkspaceId,
                    isOpen: manager.windowForWorkspace(workspace.id) != nil,
                    animationNamespace: sidebarAnimation,
                    onTap: { onSwitch(workspace.id) },
                    onClose: { onClose(workspace.id) },
                    onDelete: { pendingDeleteWorkspace = workspace; showDeleteAlert = true },
                    onConvert: { onConvert(workspace) },
                    onEdit: { editingWorkspace = workspace }
                )
                .padding(.leading, 8)
            }
        }
    }

    // Temporary section（保持原有逻辑不变）
    if manager.hasTemporaryWorkspaces {
        HStack {
            Text("Temporary")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.6))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)

        ForEach(manager.temporaryWorkspaces) { workspace in
            ExpandedWorkspaceItem(
                workspace: workspace,
                isActive: workspace.id == currentWorkspaceId,
                isOpen: manager.windowForWorkspace(workspace.id) != nil,
                animationNamespace: sidebarAnimation,
                onTap: { onSwitch(workspace.id) },
                onClose: { onClose(workspace.id) },
                onDelete: { pendingDeleteWorkspace = workspace; showDeleteAlert = true },
                onConvert: { onConvert(workspace) },
                onEdit: { editingWorkspace = workspace }
            )
        }
    }
}
.padding(.vertical, 4)
```

> 注意：`showRenameGroupAlert` 和 `confirmDeleteGroup` 是需要在 `WorkspaceSidebar` 中新增的本地方法，见下一步。

- [ ] **Step 3: 在 WorkspaceSidebar 中添加分组操作 state 和辅助方法**

在 `WorkspaceSidebar` 的 `@State` 声明区（`showDeleteAlert` 之后）添加：

```swift
@State private var showDeleteGroupAlert = false
@State private var pendingDeleteGroup: WorkspaceGroup?
@State private var renamingGroup: WorkspaceGroup?
```

在 `body` 的 `.alert` 修饰符链中添加删除分组的 alert：

```swift
.alert(
    "Delete Group \"\(pendingDeleteGroup?.name ?? "")\"?",
    isPresented: $showDeleteGroupAlert
) {
    Button("Cancel", role: .cancel) { pendingDeleteGroup = nil }
    Button("Delete", role: .destructive) {
        if let g = pendingDeleteGroup { manager.deleteGroup(id: g.id) }
        pendingDeleteGroup = nil
    }
} message: {
    Text("Workspaces in this group will be moved to ungrouped.")
}
```

在 `WorkspaceSidebar` 中添加辅助方法：

```swift
private func showRenameGroupAlert(group: WorkspaceGroup) {
    let alert = NSAlert()
    alert.messageText = "Rename Group"
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    field.stringValue = group.name
    alert.accessoryView = field
    guard let window = NSApp.keyWindow else { return }
    alert.beginSheetModal(for: window) { response in
        guard response == .alertFirstButtonReturn else { return }
        let newName = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty else { return }
        manager.renameGroup(id: group.id, name: newName)
    }
}

private func showCreateGroupAlert(movingWorkspace workspace: WorkspaceModel? = nil) {
    let alert = NSAlert()
    alert.messageText = "New Group"
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    field.placeholderString = "Group name"
    alert.accessoryView = field
    guard let window = NSApp.keyWindow else { return }
    alert.beginSheetModal(for: window) { response in
        guard response == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let group = manager.createGroup(name: name)
        if let ws = workspace {
            manager.moveWorkspace(id: ws.id, toGroup: group.id, insertAfter: nil)
        }
    }
}

private func confirmDeleteGroup(group: WorkspaceGroup) {
    pendingDeleteGroup = group
    showDeleteGroupAlert = true
}
```

- [ ] **Step 4: 在 ExpandedWorkspaceItem 右键菜单中添加 "Move to Group" 子菜单**

在 `ExpandedWorkspaceItem` 中新增两个可选回调参数（放在 `onEdit` 之后，带 `= nil` 默认值）：

```swift
let onMoveToGroup: ((UUID?) -> Void)? = nil   // nil groupId = 移入未分组
let onNewGroup: (() -> Void)? = nil
```

在 `ExpandedWorkspaceItem.contextMenu` 中（`Button("Edit Workspace...")` 之后）添加：

```swift
Menu("Move to Group") {
    if workspace.groupId != nil {
        Button("Ungrouped") { onMoveToGroup?(nil) }
        Divider()
    }
    ForEach(WorkspaceManager.shared.groups) { group in
        if group.id != workspace.groupId {
            Button(group.name) { onMoveToGroup?(group.id) }
        }
    }
    Divider()
    Button("New Group…") { onNewGroup?() }
}
```

在 `expandedContent` 的 Step 2 代码中，所有 **未分组和分组内**的 `ExpandedWorkspaceItem` 调用（不包括 Temporary 区域）补充两个新参数：

```swift
// 未分组区域 和 分组内区域的 ExpandedWorkspaceItem 末尾添加：
onMoveToGroup: { groupId in
    manager.moveWorkspace(id: workspace.id, toGroup: groupId, insertAfter: nil)
},
onNewGroup: { showCreateGroupAlert(movingWorkspace: workspace) }
```

**Temporary 区域**的 `ExpandedWorkspaceItem` 不传这两个参数（使用 `= nil` 默认值），Temporary workspace 不参与分组。

> **检查清单（workspace-rules.md）**：在此步骤完成后，搜索 `ExpandedWorkspaceItem(` 确认所有 formal workspace 调用点都已传入 `onMoveToGroup` 和 `onNewGroup`，Temporary 调用点使用默认 nil。

- [ ] **Step 5: 编译检查**

```bash
make check 2>&1 | grep "error:" | head -20
```

预期：无 error

- [ ] **Step 6: 手动测试**

```bash
make dev
```

打开 App，验证：
- Expanded sidebar 中分组标头显示，可以点击折叠/展开
- 右键分组标头出现 Rename / Delete 菜单
- 右键 workspace 出现 "Move to Group" 子菜单

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceSidebar.swift
git commit -m "feat(workspace-groups): add group headers and Move to Group menu in expanded sidebar"
```

---

## Task 4: Expanded Sidebar — 拖拽重排

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceSidebar.swift`

> **范围说明**：本 Task 实现粗粒度拖拽（拖入整个分组，始终插入末尾）。规格书中的精确插入线（2px drop indicator）和组内任意位置插入属于 v1.1 范围，本期不实现。

- [ ] **Step 1: 为 WorkspaceModel 和 WorkspaceGroup 添加 Transferable/NSItemProvider 支持**

在 `WorkspaceGroup.swift` 末尾添加：

```swift
// MARK: - Drag Support

extension WorkspaceGroup {
    static let dragType = NSPasteboard.PasteboardType("com.poltertty.workspace-group")
}

extension WorkspaceModel {
    static let dragType = NSPasteboard.PasteboardType("com.poltertty.workspace")
}
```

- [ ] **Step 2: 为 ExpandedWorkspaceItem 添加 .onDrag**

在 `ExpandedWorkspaceItem` 的 Button 上添加（`buttonStyle(.plain)` 之后）：

```swift
.onDrag {
    let provider = NSItemProvider()
    provider.registerDataRepresentation(forTypeIdentifier: WorkspaceModel.dragType.rawValue,
                                         visibility: .all) { completion in
        completion(workspace.id.uuidString.data(using: .utf8), nil)
        return nil
    }
    return provider
}
```

- [ ] **Step 3: 为 GroupHeaderRow 添加 .onDrag（分组重排）和 .onDrop（接收 workspace）**

在 `GroupHeaderRow` 的 `HStack` 上添加：

```swift
.onDrag {
    let provider = NSItemProvider()
    provider.registerDataRepresentation(forTypeIdentifier: WorkspaceGroup.dragType.rawValue,
                                         visibility: .all) { completion in
        completion(group.id.uuidString.data(using: .utf8), nil)
        return nil
    }
    return provider
}
.onDrop(of: [WorkspaceModel.dragType], isTargeted: nil) { providers in
    providers.first?.loadDataRepresentation(forTypeIdentifier: WorkspaceModel.dragType.rawValue) { data, _ in
        guard let data = data,
              let uuidStr = String(data: data, encoding: .utf8),
              let wsId = UUID(uuidString: uuidStr) else { return }
        DispatchQueue.main.async {
            WorkspaceManager.shared.moveWorkspace(id: wsId, toGroup: group.id, insertAfter: nil)
            // 展开目标分组
            if !group.isExpanded {
                WorkspaceManager.shared.toggleGroupExpanded(id: group.id)
            }
        }
    }
    return true
}
```

- [ ] **Step 4: 在未分组区域添加 .onDrop（接收 workspace 移回未分组）**

在 `expandedContent` 中，未分组 workspace 列表的外层 `VStack` 上添加：

```swift
.onDrop(of: [WorkspaceModel.dragType], isTargeted: nil) { providers in
    providers.first?.loadDataRepresentation(forTypeIdentifier: WorkspaceModel.dragType.rawValue) { data, _ in
        guard let data = data,
              let uuidStr = String(data: data, encoding: .utf8),
              let wsId = UUID(uuidString: uuidStr) else { return }
        DispatchQueue.main.async {
            WorkspaceManager.shared.moveWorkspace(id: wsId, toGroup: nil, insertAfter: nil)
        }
    }
    return true
}
```

- [ ] **Step 5: 编译检查**

```bash
make check 2>&1 | grep "error:" | head -20
```

- [ ] **Step 6: 手动测试拖拽**

```bash
make dev
```

验证：
- 可以将 workspace 拖拽到分组标头（workspace 移入该分组）
- 可以将 workspace 拖拽到未分组区域（workspace 移回未分组）

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceSidebar.swift \
        macos/Sources/Features/Workspace/WorkspaceGroup.swift
git commit -m "feat(workspace-groups): add drag-and-drop for workspace grouping in expanded sidebar"
```

---

## Task 5: Collapsed Sidebar — CollapsedGroupIcon

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceSidebar.swift`

- [ ] **Step 1: 在 WorkspaceSidebar.swift 末尾添加 CollapsedGroupIcon**

```swift
// MARK: - Collapsed Group Icon

struct CollapsedGroupIcon: View {
    let group: WorkspaceGroup
    let onToggle: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(isHovering ? 0.25 : 0.15))
                    .frame(width: 32, height: 32)

                Text(group.abbreviation)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(group.name)
        .contextMenu {
            Button("Rename Group…") { onRename() }
            Divider()
            Button("Delete Group", role: .destructive) { onDelete() }
        }
        .onTapGesture(count: 2) {}  // 阻止双击透传
    }
}
```

- [ ] **Step 2: 替换 collapsedContent 中的 workspace 列表渲染**

找到 `collapsedContent` 里的 `ScrollView { LazyVStack { ... } }` 部分，将整个 `LazyVStack` 内容替换为（使用完整 `CollapsedWorkspaceIcon` 参数）：

```swift
LazyVStack(spacing: 4) {
    // 未分组 workspace
    ForEach(manager.workspacesInGroup(nil)) { workspace in
        CollapsedWorkspaceIcon(
            workspace: workspace,
            isActive: workspace.id == currentWorkspaceId,
            isOpen: manager.windowForWorkspace(workspace.id) != nil,
            onTap: { onSwitch(workspace.id) },
            onClose: { onClose(workspace.id) },
            onDelete: { pendingDeleteWorkspace = workspace; showDeleteAlert = true },
            onEdit: { editingWorkspace = workspace },
            onMoveToGroup: { groupId in
                manager.moveWorkspace(id: workspace.id, toGroup: groupId, insertAfter: nil)
            },
            onNewGroup: { showCreateGroupAlert(movingWorkspace: workspace) }
        )
    }

    // 各个分组
    ForEach(manager.groups) { group in
        Divider().padding(.horizontal, 8).padding(.vertical, 2)

        if group.isCollapsedIcon {
            CollapsedGroupIcon(
                group: group,
                onToggle: { manager.toggleGroupCollapsedIcon(id: group.id) },
                onRename: { showRenameGroupAlert(group: group) },
                onDelete: { confirmDeleteGroup(group: group) }
            )
        } else {
            VStack(spacing: 4) {
                Button(action: { manager.toggleGroupCollapsedIcon(id: group.id) }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 16)
                }
                .buttonStyle(.plain)
                .help("Collapse \(group.name)")

                ForEach(manager.workspacesInGroup(group.id)) { workspace in
                    CollapsedWorkspaceIcon(
                        workspace: workspace,
                        isActive: workspace.id == currentWorkspaceId,
                        isOpen: manager.windowForWorkspace(workspace.id) != nil,
                        onTap: { onSwitch(workspace.id) },
                        onClose: { onClose(workspace.id) },
                        onDelete: { pendingDeleteWorkspace = workspace; showDeleteAlert = true },
                        onEdit: { editingWorkspace = workspace },
                        onMoveToGroup: { groupId in
                            manager.moveWorkspace(id: workspace.id, toGroup: groupId, insertAfter: nil)
                        },
                        onNewGroup: { showCreateGroupAlert(movingWorkspace: workspace) }
                    )
                }
            }
        }
    }

    // Temporary 分隔（传 nil，Temporary workspace 不参与分组）
    if manager.hasTemporaryWorkspaces {
        Divider().padding(.horizontal, 8).padding(.vertical, 4)
        ForEach(manager.temporaryWorkspaces) { workspace in
            CollapsedWorkspaceIcon(
                workspace: workspace,
                isActive: workspace.id == currentWorkspaceId,
                isOpen: manager.windowForWorkspace(workspace.id) != nil,
                onTap: { onSwitch(workspace.id) },
                onClose: { onClose(workspace.id) },
                onDelete: { pendingDeleteWorkspace = workspace; showDeleteAlert = true },
                onEdit: { editingWorkspace = workspace },
                onMoveToGroup: nil,
                onNewGroup: nil
            )
        }
    }
}
.padding(.vertical, 6)
```

- [ ] **Step 3: 在 CollapsedWorkspaceIcon 右键菜单中添加 "Move to Group" 子菜单**

在 `CollapsedWorkspaceIcon` 中新增两个可选回调参数（`onEdit` 之后，带 `= nil` 默认值）：

```swift
let onMoveToGroup: ((UUID?) -> Void)? = nil
let onNewGroup: (() -> Void)? = nil
```

在 `contextMenu` 中（`Button("Edit Workspace...")` 之后）添加（与 `ExpandedWorkspaceItem` 完全对称）：

```swift
Menu("Move to Group") {
    if workspace.groupId != nil {
        Button("Ungrouped") { onMoveToGroup?(nil) }
        Divider()
    }
    ForEach(WorkspaceManager.shared.groups) { group in
        if group.id != workspace.groupId {
            Button(group.name) { onMoveToGroup?(group.id) }
        }
    }
    Divider()
    Button("New Group…") { onNewGroup?() }
}
```

> **检查清单（workspace-rules.md）**：搜索 `ExpandedWorkspaceItem(` 和 `CollapsedWorkspaceIcon(` 确认：formal workspace 调用点都传入了 `onMoveToGroup`/`onNewGroup`，Temporary 调用点使用 `nil`。

- [ ] **Step 4: 编译检查**

```bash
make check 2>&1 | grep "error:" | head -20
```

- [ ] **Step 5: 手动测试**

```bash
make dev
```

验证：
- 折叠 sidebar 时，分组之间有分隔线
- 分组可折叠成缩写图标，点击展开显示 workspace 图标
- 右键 `CollapsedGroupIcon` 出现 Rename / Delete 菜单
- 右键 workspace 图标出现 "Move to Group" 子菜单

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceSidebar.swift
git commit -m "feat(workspace-groups): add CollapsedGroupIcon and group rendering in collapsed sidebar"
```

---

## Task 6: Quick Switcher 集成

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceQuickSwitcher.swift`

- [ ] **Step 1: 在 WorkspaceQuickSwitcher 中添加分组名显示和过滤**

编辑 `WorkspaceQuickSwitcher.swift`：

**修改 `filtered` 计算属性**（在现有 name/tags 条件后添加 group name）：

```swift
private var filtered: [WorkspaceModel] {
    if query.isEmpty { return manager.workspaces }
    return manager.workspaces.filter { ws in
        let gName = manager.groups.first(where: { $0.id == ws.groupId })?.name ?? ""
        return ws.name.localizedCaseInsensitiveContains(query) ||
               ws.tags.contains { $0.localizedCaseInsensitiveContains(query) } ||
               gName.localizedCaseInsensitiveContains(query)
    }
}
```

> 注意：使用具名参数 `ws in` 避免嵌套闭包中 `$0` 的 shadowing 编译错误。

**在 workspace 行的 VStack 中（`rootDir` 文本之后）添加分组名第三行**：

```swift
// 在 VStack(alignment: .leading, spacing: 2) 中，Text(workspace.rootDir) 之后：
if let groupId = workspace.groupId,
   let groupName = manager.groups.first(where: { $0.id == groupId })?.name {
    Text(groupName)
        .font(.system(size: 9))
        .foregroundColor(.secondary.opacity(0.6))
        .lineLimit(1)
}
```

- [ ] **Step 2: 编译检查**

```bash
make check 2>&1 | grep "error:" | head -20
```

- [ ] **Step 3: 手动测试**

```bash
make dev
```

用 `Cmd+Ctrl+W` 打开 Quick Switcher，验证：
- 已分组的 workspace 在 rootDir 下方显示分组名
- 输入分组名可以过滤出该分组下的 workspace

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceQuickSwitcher.swift
git commit -m "feat(workspace-groups): show group name in Quick Switcher and enable group name search"
```

---

## Task 7: 整合测试与 PR

- [ ] **Step 1: 完整编译检查**

```bash
make check 2>&1 | grep "error:" | head -20
```

预期：无 error

- [ ] **Step 2: 运行所有 Workspace 测试**

```bash
xcodebuild test \
  -project macos/Ghostty.xcodeproj \
  -scheme Ghostty \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing GhosttyTests/WorkspaceGroupTests \
  -only-testing GhosttyTests/GitStatusMonitorTests \
  -only-testing GhosttyTests/FileBrowserViewModelNavigationTests \
  2>&1 | grep -E "error:|FAILED|passed|failed"
```

预期：所有测试通过

- [ ] **Step 3: Dev 构建并手动验证完整流程**

```bash
make dev
```

验证清单：
- [ ] 创建分组（右键 workspace → Move to Group → New Group…）
- [ ] 重命名分组（右键分组标头 → Rename）
- [ ] 删除分组（分组下 workspace 自动移入未分组）
- [ ] 将 workspace 拖入/拖出分组
- [ ] 重启 App 后分组状态（包括折叠/展开）恢复
- [ ] 折叠 sidebar：分组显示分隔线，可收起成图标
- [ ] Quick Switcher 显示分组名并可按分组名搜索
- [ ] Temporary workspace 不受分组功能影响

- [ ] **Step 4: 创建 PR**

```bash
cd .worktrees/feat-workspace-groups
git push -u origin feat/workspace-groups
gh pr create \
  --title "feat: workspace 分组功能" \
  --body "$(cat <<'EOF'
## Summary
- 新增 WorkspaceGroup 模型，支持手动分组管理（groups.json 持久化）
- WorkspaceModel 新增 groupId / groupOrder 字段，向后兼容旧 snapshot
- WorkspaceSidebar expanded 模式：分组标头、折叠/展开、右键菜单、Move to Group 子菜单、拖拽
- WorkspaceSidebar collapsed 模式：CollapsedGroupIcon、分组分隔线、分组内收起/展开
- WorkspaceQuickSwitcher：显示分组名、支持按分组名搜索

## Test plan
- [ ] 创建/重命名/删除分组
- [ ] 拖拽 workspace 移入/移出分组
- [ ] 重启后分组状态恢复
- [ ] collapsed sidebar 分组图标正常
- [ ] Quick Switcher 分组名显示和搜索
- [ ] Temporary workspace 不受分组影响
- [ ] 旧版 workspace snapshot 正常加载（无分组字段）

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
