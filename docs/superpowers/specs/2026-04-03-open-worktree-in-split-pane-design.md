# 设计文档：在指定方向打开 Worktree 到新 Split Pane

**日期**：2026-04-03  
**状态**：已批准

---

## 背景

Poltertty 已有 `GitWorktreeMonitor` 监控 git worktrees，`WorktreeListView` 展示列表。当前用户若想在新 split pane 中查看某个 worktree，必须手动分屏再 `cd`。本功能将此流程合并为一步操作。

---

## 需求

- 用户可从 `WorktreeListView` 右键菜单，选择方向，将 worktree 在新 split pane 中打开
- AI Agent 可通过 MCP 工具 `open_worktree_in_split` 完成同等操作
- 新 pane 自动 `cd` 到 worktree 路径，无其他副作用

---

## 方案选择

采用**方案 A**：UI 右键菜单 + 新增专用 MCP 工具。

放弃方案 B（扩展 `split_pane` 加 `cwd`）：需确认上游 `SurfaceConfiguration` 支持，改动面大。  
放弃方案 C（文档化 `split_pane + command`）：API 语义不清晰。

---

## 架构

### UI 层：`WorktreeListView.swift`

每个 worktree 条目加 `.contextMenu`，结构如下：

```
右键 worktree 条目
└── "在新 Pane 中打开"（子菜单）
    ├── "向右打开"  →  direction: .right
    ├── "向左打开"  →  direction: .left
    ├── "向下打开"  →  direction: .down
    └── "向上打开"  →  direction: .up
```

**执行流程：**

1. 从 SwiftUI 环境获取当前窗口的 `BaseTerminalController`
2. 取 `focusedSurface`；若为 nil 则取第一个可用 surface
3. 调用 `tc.newSplit(at: surface, direction: direction)` → 得到 `newPaneId`
4. 调用 `tc.writeToSurface(text: "cd \(worktree.path)\n", surfaceId: newPaneId)`

**错误处理：**
- 若无可用 surface，静默不响应（与现有 split 行为一致）
- worktree 路径由 `GitWorktree.path` 提供，已经过验证

---

### MCP API 层：`CtrlToolHandler.swift`

新增工具 `open_worktree_in_split`。

**参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `paneId` | string (UUID) | 否 | 分屏基准 pane；不传则用当前 focused pane |
| `worktreePath` | string | 是 | worktree 绝对路径 |
| `direction` | string | 是 | `"left"` \| `"right"` \| `"up"` \| `"down"` |

**执行流程：**

1. 解析并验证参数；`direction` 非法则返回错误
2. 若有 `paneId`：`tc.switchToTab(containing: paneId)` + `tc.findSurface(id: paneId)`  
   若无 `paneId`：取 `tc.focusedSurface`
3. `tc.newSplit(at: surface, direction: direction)` → `newPaneId`
4. `tc.writeToSurface(text: "cd \(worktreePath)\n", surfaceId: newPaneId)`
5. 返回 `{"newPaneId": "<uuid>"}`

**错误响应：**
- `paneId` 不存在：`{"error": "pane not found"}`
- `direction` 非法：`{"error": "invalid direction: <value>"}`
- 分屏失败（无 surface）：`{"error": "split failed"}`

---

## 涉及文件

| 文件 | 改动内容 |
|------|---------|
| `macos/Sources/Features/Workspace/WorktreeListView.swift` | 为条目添加 `.contextMenu` |
| `macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift` | 新增 `callOpenWorktreeInSplit` 方法及工具注册 |

**不涉及：**
- `SplitTree.swift`、`BaseTerminalController.swift` — 直接复用现有 API，无需修改
- `GitWorktreeMonitor.swift` — 数据已满足需求

---

## 测试

- 手动：WorktreeListView 右键四个方向各验证一次，确认新 pane 落在正确位置且 `cd` 成功
- MCP：用 `curl` 调用 `open_worktree_in_split`，验证返回 `newPaneId` 且 pane 内目录正确
- 边界：无 worktree 时菜单不显示；无 surface 时静默处理
