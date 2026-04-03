# Open Worktree in Split Pane — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 WorktreeListView 右键菜单和 MCP API 中提供"在指定方向的新 split pane 中打开 worktree"功能。

**Architecture:** 沿现有 `onOpenInTab/onOpenInWindow` 回调链，新增 `onOpenInSplit(path:direction:)` 回调从 `TerminalController` → `PolterttyRootView` → `WorkspaceSidebar` → `WorktreeListView`。MCP 侧在 `CtrlToolHandler` 新增 `open_worktree_in_split` 工具，直接调用 `tc.newSplit(at:direction:baseConfig:)`，通过 `baseConfig.workingDirectory` 设置初始目录。

**Tech Stack:** Swift 5.10, SwiftUI, AppKit, `SplitTree<Ghostty.SurfaceView>.NewDirection`

**Design spec:** `docs/superpowers/specs/2026-04-03-open-worktree-in-split-pane-design.md`

---

## 文件变更地图

| 文件 | 操作 |
|------|------|
| `macos/Sources/Features/Workspace/WorktreeListView.swift` | 修改：添加 `onOpenInSplit` 回调 + context menu |
| `macos/Sources/Features/Workspace/WorkspaceSidebar.swift` | 修改：`WorkspaceSidebar` 和 `CollapsedWorkspaceIcon` 各添加属性并传递 |
| `macos/Sources/Features/Workspace/PolterttyRootView.swift` | 修改：添加属性 + init 参数，传给 `WorkspaceSidebar` |
| `macos/Sources/Features/Terminal/TerminalController.swift` | 修改：实现 `openInSplit(path:direction:)` 并在 `PolterttyRootView` 初始化中传回调 |
| `macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift` | 修改：添加 `callOpenWorktreeInSplit` + switch case |
| `macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift` | 修改：添加 `open_worktree_in_split` 工具 schema |

---

### Task 1: 创建开发用 git worktree

**Files:**
- 无文件变更，仅创建 worktree

- [ ] **Step 1: 在 .worktrees/ 下创建 worktree**

```bash
git worktree add .worktrees/feat/open-worktree-in-split -b feat/open-worktree-in-split
```

- [ ] **Step 2: 确认创建成功**

```bash
git worktree list
```

Expected: 显示 `.worktrees/feat/open-worktree-in-split` 条目

---

### Task 2: WorktreeListView — 添加 onOpenInSplit 回调和 context menu

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorktreeListView.swift`

- [ ] **Step 1: 在 `WorktreeListView` 中添加 `onOpenInSplit` 属性**

在 `WorktreeListView` struct 的 `let onDelete` 行后面添加：

```swift
// 文件: macos/Sources/Features/Workspace/WorktreeListView.swift

struct WorktreeListView: View {
    @ObservedObject var monitor: GitWorktreeMonitor
    let onOpenInTab: (String) -> Void
    let onOpenInWindow: (String) -> Void
    let onDelete: (String, Bool) -> Void  // path, force
    var onOpenInSplit: ((String, SplitTree<Ghostty.SurfaceView>.NewDirection) -> Void)? = nil  // 新增
```

- [ ] **Step 2: 在 `WorktreeListView.body` 的 `WorktreeRow` 调用中传递 `onOpenInSplit`**

```swift
// 原来的 WorktreeRow 调用（在 ForEach 内）
WorktreeRow(
    worktree: worktree,
    monitor: monitor,
    onOpenInTab: onOpenInTab,
    onOpenInWindow: onOpenInWindow,
    onDelete: onDelete,
    onOpenInSplit: onOpenInSplit   // 新增这一行
)
```

- [ ] **Step 3: 在 `WorktreeRow` struct 声明中添加 `onOpenInSplit` 属性**

```swift
private struct WorktreeRow: View {
    let worktree: GitWorktree
    let monitor: GitWorktreeMonitor
    let onOpenInTab: (String) -> Void
    let onOpenInWindow: (String) -> Void
    let onDelete: (String, Bool) -> Void
    var onOpenInSplit: ((String, SplitTree<Ghostty.SurfaceView>.NewDirection) -> Void)? = nil  // 新增
```

- [ ] **Step 4: 在 `WorktreeRow.contextMenu` 中添加"在新 Pane 中打开"子菜单**

在现有 `Button("Open in New Window")` 行之后、`Divider()` 之前添加：

```swift
.contextMenu {
    if worktree.exists {
        Button(String(localized: "Open in New Tab")) { onOpenInTab(worktree.path) }
        Button(String(localized: "Open in New Window")) { onOpenInWindow(worktree.path) }
        // 新增：在新 pane 中打开子菜单
        if onOpenInSplit != nil {
            Menu(String(localized: "Open in New Pane")) {
                Button(String(localized: "To the Right")) {
                    onOpenInSplit?(worktree.path, .right)
                }
                Button(String(localized: "To the Left")) {
                    onOpenInSplit?(worktree.path, .left)
                }
                Button(String(localized: "Below")) {
                    onOpenInSplit?(worktree.path, .down)
                }
                Button(String(localized: "Above")) {
                    onOpenInSplit?(worktree.path, .up)
                }
            }
        }
        Divider()
        Button(String(localized: "Reveal in Finder")) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.path)
        }
        Button(String(localized: "Copy Path")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(worktree.path, forType: .string)
        }
    }
    if !worktree.isMain && !worktree.isCurrent {
        Divider()
        Button(String(localized: "Delete Worktree"), role: .destructive) {
            onDelete(worktree.path, false)
        }
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Workspace/WorktreeListView.swift
git commit -m "feat(workspace): add open-in-split context menu to WorktreeRow"
```

---

### Task 3: WorkspaceSidebar — 传递 onOpenWorktreeInSplit 回调

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceSidebar.swift`

- [ ] **Step 1: 在 `WorkspaceSidebar` 声明中添加 `onOpenWorktreeInSplit` 属性**

在 `var onOpenWorktreeInWindow` 行后面添加：

```swift
var onOpenWorktreeInTab: ((String) -> Void)? = nil
var onOpenWorktreeInWindow: ((String) -> Void)? = nil
var onOpenWorktreeInSplit: ((String, SplitTree<Ghostty.SurfaceView>.NewDirection) -> Void)? = nil  // 新增
```

- [ ] **Step 2: 在第一处 `WorktreeListView` 调用（约第 350 行，collapsed 区域）中传递**

```swift
WorktreeListView(
    monitor: monitor,
    onOpenInTab: { path in onOpenWorktreeInTab?(path) },
    onOpenInWindow: { path in onOpenWorktreeInWindow?(path) },
    onDelete: { path, _ in confirmDeleteWorktree(path: path, monitor: monitor) },
    onOpenInSplit: onOpenWorktreeInSplit   // 新增
)
```

- [ ] **Step 3: 在第二处 `WorktreeListView` 调用（约第 481 行，expanded 区域）中传递**

```swift
WorktreeListView(
    monitor: monitor,
    onOpenInTab: { path in onOpenWorktreeInTab?(path) },
    onOpenInWindow: { path in onOpenWorktreeInWindow?(path) },
    onDelete: { path, _ in confirmDeleteWorktree(path: path, monitor: monitor) },
    onOpenInSplit: onOpenWorktreeInSplit   // 新增
)
```

- [ ] **Step 4: 在 `CollapsedWorkspaceIcon` 声明中添加属性（约第 648 行）**

```swift
var onOpenWorktreeInTab: ((String) -> Void)? = nil
var onOpenWorktreeInWindow: ((String) -> Void)? = nil
var onOpenWorktreeInSplit: ((String, SplitTree<Ghostty.SurfaceView>.NewDirection) -> Void)? = nil  // 新增
var onDeleteWorktree: ((String) -> Void)? = nil
```

- [ ] **Step 5: 在 `CollapsedWorkspaceIcon` 的 contextMenu 中添加子菜单（约第 723 行）**

在 `Button("Open in New Window")` 后添加：

```swift
Button(String(localized: "Open in New Tab")) { onOpenWorktreeInTab?(wt.path) }
Button(String(localized: "Open in New Window")) { onOpenWorktreeInWindow?(wt.path) }
// 新增：在新 pane 中打开子菜单
if onOpenWorktreeInSplit != nil {
    Menu(String(localized: "Open in New Pane")) {
        Button(String(localized: "To the Right")) { onOpenWorktreeInSplit?(wt.path, .right) }
        Button(String(localized: "To the Left"))  { onOpenWorktreeInSplit?(wt.path, .left) }
        Button(String(localized: "Below"))        { onOpenWorktreeInSplit?(wt.path, .down) }
        Button(String(localized: "Above"))        { onOpenWorktreeInSplit?(wt.path, .up) }
    }
}
```

- [ ] **Step 6: 在 `CollapsedWorkspaceIcon` 的三处调用点均传递属性**

`WorkspaceSidebar.swift` 中有三处 `CollapsedWorkspaceIcon(...)` 调用：
- 约第 173 行（未分组 workspace）
- 约第 220 行（分组内 workspace）  
- 约第 253 行（临时 workspace）

每处都要在 `onOpenWorktreeInWindow:` 行后添加：

```swift
onOpenWorktreeInTab: workspace.id == currentWorkspaceId ? onOpenWorktreeInTab : nil,
onOpenWorktreeInWindow: workspace.id == currentWorkspaceId ? onOpenWorktreeInWindow : nil,
onOpenWorktreeInSplit: workspace.id == currentWorkspaceId ? onOpenWorktreeInSplit : nil,  // 新增
onDeleteWorktree: workspace.id == currentWorkspaceId ? { path in ...
```

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceSidebar.swift
git commit -m "feat(workspace): propagate onOpenWorktreeInSplit through WorkspaceSidebar"
```

---

### Task 4: PolterttyRootView — 声明并传递 onOpenWorktreeInSplit

**Files:**
- Modify: `macos/Sources/Features/Workspace/PolterttyRootView.swift`

- [ ] **Step 1: 在属性声明区域添加 `onOpenWorktreeInSplit`（约第 39 行）**

```swift
var onOpenWorktreeInTab: ((String) -> Void)? = nil
var onOpenWorktreeInWindow: ((String) -> Void)? = nil
var onOpenWorktreeInSplit: ((String, SplitTree<Ghostty.SurfaceView>.NewDirection) -> Void)? = nil  // 新增
```

- [ ] **Step 2: 在 `init` 参数列表末尾添加（约第 84 行）**

```swift
onOpenWorktreeInTab: ((String) -> Void)? = nil,
onOpenWorktreeInWindow: ((String) -> Void)? = nil,
onOpenWorktreeInSplit: ((String, SplitTree<Ghostty.SurfaceView>.NewDirection) -> Void)? = nil  // 新增
```

- [ ] **Step 3: 在 `init` 体中赋值（约第 102 行）**

```swift
self.onOpenWorktreeInTab = onOpenWorktreeInTab
self.onOpenWorktreeInWindow = onOpenWorktreeInWindow
self.onOpenWorktreeInSplit = onOpenWorktreeInSplit  // 新增
```

- [ ] **Step 4: 在 `WorkspaceSidebar(...)` 调用中传递（约第 186 行）**

```swift
WorkspaceSidebar(
    ...
    onOpenWorktreeInTab: onOpenWorktreeInTab,
    onOpenWorktreeInWindow: onOpenWorktreeInWindow,
    onOpenWorktreeInSplit: onOpenWorktreeInSplit   // 新增
)
```

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Workspace/PolterttyRootView.swift
git commit -m "feat(workspace): propagate onOpenWorktreeInSplit through PolterttyRootView"
```

---

### Task 5: TerminalController — 实现 openInSplit 并接通回调

**Files:**
- Modify: `macos/Sources/Features/Terminal/TerminalController.swift`

- [ ] **Step 1: 在 `openNewWindow(cdTo:)` 函数之后（约第 2646 行）添加 `openInSplit(path:direction:)`**

```swift
func openInSplit(path: String, direction: SplitTree<Ghostty.SurfaceView>.NewDirection) {
    guard let surface = focusedSurface else { return }
    var config = Ghostty.SurfaceConfiguration()
    config.workingDirectory = path
    _ = newSplit(at: surface, direction: direction, baseConfig: config)
}
```

注：`newSplit` 内部已自动注入 `workspaceId`，无需手动设置。

- [ ] **Step 2: 在 `PolterttyRootView(...)` 初始化调用中（约第 1650 行），添加 `onOpenWorktreeInSplit` 回调**

在现有 `onOpenWorktreeInWindow:` 参数后面添加：

```swift
onOpenWorktreeInTab: { [weak self] path in
    self?.openNewTab(cdTo: path)
},
onOpenWorktreeInWindow: { [weak self] path in
    self?.openNewWindow(cdTo: path)
},
onOpenWorktreeInSplit: { [weak self] path, direction in   // 新增
    self?.openInSplit(path: path, direction: direction)
}
```

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Terminal/TerminalController.swift
git commit -m "feat(terminal): implement openInSplit(path:direction:) for worktree"
```

---

### Task 6: CtrlToolHandler — 添加 open_worktree_in_split 工具

**Files:**
- Modify: `macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift`

- [ ] **Step 1: 在 `callTool` 的 `switch` 中添加 case（约第 41 行 `create_worktree` 之后）**

```swift
case "create_worktree":           return try await callCreateWorktree(arguments: arguments)
case "open_worktree_in_split":    return try await callOpenWorktreeInSplit(arguments: arguments)  // 新增
case "get_git_status":            return try await callGetGitStatus(arguments: arguments)
```

- [ ] **Step 2: 在 `// MARK: - create_worktree` 之后、`// MARK: - get_git_status` 之前，添加新方法**

```swift
// MARK: - open_worktree_in_split

private func callOpenWorktreeInSplit(arguments: [String: Any]) async throws -> String {
    guard let worktreePath = arguments["worktreePath"] as? String, !worktreePath.isEmpty else {
        throw RPCError(code: -32602, message: "open_worktree_in_split: missing required parameter 'worktreePath'")
    }
    guard let dirStr = arguments["direction"] as? String,
          let direction = Self.parseDirection(dirStr) else {
        throw RPCError(code: -32602, message: "open_worktree_in_split: missing or invalid direction (left|right|up|down)")
    }

    let newPaneId: UUID = try await withCheckedThrowingContinuation { cont in
        Task { @MainActor in
            // 解析 paneId（可选，默认用 focusedSurface）
            let tc: TerminalController?
            let surface: Ghostty.SurfaceView?

            if let paneIdStr = arguments["paneId"] as? String,
               let paneId = UUID(uuidString: paneIdStr) {
                tc = Self.tcContaining(paneId: paneId)
                guard let foundTC = tc else {
                    cont.resume(throwing: RPCError(code: -32603, message: "open_worktree_in_split: pane not found"))
                    return
                }
                foundTC.switchToTab(containing: paneId)
                surface = foundTC.findSurface(id: paneId)
            } else {
                let window = (NSApp.keyWindow as? TerminalWindow)
                    ?? NSApp.windows.first(where: { $0 is TerminalWindow }) as? TerminalWindow
                tc = window?.terminalController
                surface = tc?.focusedSurface
            }

            guard let resolvedTC = tc, let resolvedSurface = surface else {
                cont.resume(throwing: RPCError(code: -32603, message: "open_worktree_in_split: no surface available"))
                return
            }

            var config = Ghostty.SurfaceConfiguration()
            config.workingDirectory = worktreePath

            guard let newView = resolvedTC.newSplit(at: resolvedSurface, direction: direction, baseConfig: config) else {
                cont.resume(throwing: RPCError(code: -32603, message: "open_worktree_in_split: split failed"))
                return
            }
            cont.resume(returning: newView.id)
        }
    }
    return #"{"newPaneId":"\#(newPaneId.uuidString)"}"#
}
```

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift
git commit -m "feat(ctrl): add open_worktree_in_split MCP tool"
```

---

### Task 7: CtrlServer — 注册工具 schema

**Files:**
- Modify: `macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift`

- [ ] **Step 1: 在 `create_worktree` 工具 schema 之后（约第 542 行）插入新工具 schema**

```swift
// 紧跟在 create_worktree 的 ] 之后：
,
[
    "name": "open_worktree_in_split",
    "description": "Open a git worktree in a new split pane at the specified direction; the new pane starts in the worktree directory",
    "inputSchema": [
        "type": "object",
        "properties": [
            "worktreePath": ["type": "string", "description": "Absolute path to the worktree directory"],
            "direction": ["type": "string", "enum": ["left", "right", "up", "down"], "description": "Direction to split relative to the current or specified pane"],
            "paneId": ["type": "string", "description": "UUID of the base pane to split (optional; defaults to current focused pane)"]
        ],
        "required": ["worktreePath", "direction"]
    ]
],
```

- [ ] **Step 2: Commit**

```bash
git add macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift
git commit -m "feat(ctrl): register open_worktree_in_split in MCP tool list"
```

---

### Task 8: 构建验证

**Files:**
- 无文件变更

- [ ] **Step 1: 在 Xcode 中构建（⌘B）确认编译通过**

预期：0 errors, 0 warnings（如有新增 warnings 需逐一检查）

- [ ] **Step 2: 启动应用，打开有 git worktrees 的 workspace**

确认 WorktreeListView 中右键菜单出现 "Open in New Pane" 子菜单，包含 Right/Left/Below/Above 四项。

- [ ] **Step 3: 测试 UI — 向右分屏**

右键 worktree 条目 → "Open in New Pane" → "To the Right"  
预期：新 pane 出现在当前 pane 右侧，工作目录为 worktree 路径（执行 `pwd` 验证）

- [ ] **Step 4: 测试 MCP API**

```bash
# 先用 list_panes 获取一个 paneId 和 worktree 路径
curl -s -X POST http://localhost:<PORT>/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"open_worktree_in_split","arguments":{"worktreePath":"<ABSOLUTE_PATH>","direction":"right"}}}'
```

预期响应：`{"newPaneId":"<uuid>"}`，新 pane 目录正确

- [ ] **Step 5: 测试边界 — 无效方向**

```bash
curl -s -X POST http://localhost:<PORT>/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"open_worktree_in_split","arguments":{"worktreePath":"/tmp","direction":"diagonal"}}}'
```

预期：返回错误 `"invalid direction"`

---

### Task 9: 完成 — 合并和 PR

**Files:**
- 无文件变更

- [ ] **Step 1: 确认所有 commit 都在 feat 分支上**

```bash
git log --oneline main..HEAD
```

- [ ] **Step 2: Push 分支并创建 PR**

```bash
git push -u origin feat/open-worktree-in-split
gh pr create \
  --title "feat(workspace): open worktree in new split pane" \
  --body "$(cat <<'EOF'
## Summary

- `WorktreeListView` 右键菜单新增 "Open in New Pane" 子菜单（右/左/下/上）
- `CollapsedWorkspaceIcon` 的 worktree 子菜单同步新增相同选项
- MCP 工具 `open_worktree_in_split(worktreePath, direction, paneId?)` 供 AI Agent 调用
- 新 pane 通过 `baseConfig.workingDirectory` 直接启动在 worktree 目录，无需写 `cd` 命令

## Test plan

- [ ] Xcode 构建通过，无新增 errors
- [ ] WorktreeListView 右键菜单显示 4 个方向选项
- [ ] 各方向分屏后新 pane 工作目录正确（`pwd` 验证）
- [ ] CollapsedWorkspaceIcon 的 worktree 菜单同样可用
- [ ] MCP `open_worktree_in_split` 调用返回正确 `newPaneId`
- [ ] 无效方向参数返回明确错误信息
- [ ] `paneId` 为空时使用 focused pane 正常工作

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
