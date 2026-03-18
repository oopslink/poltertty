# Agent Monitor UI 重设计

**日期**: 2026-03-18
**状态**: 已通过用户审核，待实现

---

## 背景

当前 Agent Monitor 是固定宽度 280px 的侧边栏，session 多、subagent 多时信息密度过高，无法对比多个 subagent，缺乏 session 级别汇总视图。

---

## 设计目标

1. 在不破坏主终端区域的前提下，支持查看 subagent 详细活动
2. 支持多个 subagent 并排对比
3. 提供 session 级别的聚合摘要（耗时、cost、context）
4. 层次清晰：session 是分组，subagent 是主要操作对象

---

## 整体布局

```
┌─────────────────┬──────────────────────┬──────────┐
│   终端区域       │   Drawer（动态宽度）   │ 侧边栏   │
│   (flex: 1)     │   400 / 800 / 1200px  │  180px   │
└─────────────────┴──────────────────────┴──────────┘
```

- **侧边栏**：固定 180px，始终可见，列出所有 session 及其 subagent
- **Drawer**：从侧边栏左侧滑出，宽度随选中 subagent 数量自动扩展
- **终端区域**：Drawer 以 overlay 形式浮于终端上方，不占用 flex 空间、不压缩终端宽度

---

## 侧边栏结构

### Session 行（可点击）

```
● Code Reviewer    [2↑] ›
```

- 状态点（颜色反映聚合状态：running > error > idle > done）
- Session 名称
- Badge：活跃 subagent 数量（`2↑`）或 `done`
- 点击 → Drawer 显示该 Session 的 **Overview**

### Subagent 行（可点击，缩进）

```
  ● security-reviewer     42s
  ✗ code-reviewer         28s
  ✓ doc-updater           15s
```

- 单击 → Drawer 显示该 subagent 的详情（单 panel）
- **Cmd+Click** → 追加到 Drawer，形成 Split 对比（最多 3 个）
- 已在 Drawer 中显示的 subagent 行高亮（蓝色背景）

---

## Drawer

### 触发与关闭

| 操作 | 效果 |
|------|------|
| 点击 Session 行 | 打开 Overview（400px） |
| 点击 Subagent 行 | 打开详情（400px） |
| Cmd+Click 第 2 个 | 扩展为 Split 2（800px） |
| Cmd+Click 第 3 个 | 扩展为 Split 3（1200px） |
| 点 Panel 的 ✕ | 关闭该 panel，Drawer 收缩；若最后一个 panel 被关闭，Drawer 整体关闭 |
| 点 Drawer 全局 ✕ | 关闭整个 Drawer，清空所有 selectedItems |

### Drawer Header（全局工具栏）

```
[Session 名 / 对比模式]   [⫿⫿] [≡]   [✕]
```

- 标题：单 panel 时显示 session 名或 subagent 名；多 panel 时显示"对比模式"
- 布局切换：左右并排（`⫿⫿`）/ 上下分屏（`≡`）
- 全局关闭

### Session Overview Panel

**默认 tab：Overview**（不可切换，无 Trace/Prompt）

内容：
- 总耗时、累计 cost、context 用量（带进度条）
- Subagent 列表：状态点 + 名称 + 状态 badge + 耗时
- 底部提示：「点击 subagent 查看详情 · Cmd+Click 并排对比」

### Subagent 详情 Panel

**Tabs（默认 Output）**：

| Tab | 内容 |
|-----|------|
| **Output**（默认） | 最终回答或结果摘要；错误时显示错误信息和已完成步骤 |
| Trace | 工具调用序列：工具名、状态（✓ / ● / ✗）、耗时；树形连接线 |
| Prompt | 发给该 subagent 的完整 prompt，带滚动 |

**Panel Header**：

```
● security-reviewer   [✕]
⏱ 42s   🔧 7 calls
```

---

## 交互细节

### 高亮状态

- 侧边栏中当前在 Drawer 显示的 subagent 行：蓝色背景 `#152040`，名称 `#90bfff`
- 侧边栏中当前选中的 session 行：蓝色背景 `#1a2535`

### 状态颜色规范

| 状态 | 颜色 |
|------|------|
| running | `#4caf50`（绿，带 glow） |
| error | `#f44336`（红） |
| idle / waiting | `#ff9800`（橙） |
| done | `#555`（灰） |
| launching | `#666`（灰，无 glow） |

### Drawer 动画

- 滑入/滑出：`.easeInOut(duration: 0.2)` 横向 slide
- 宽度变化（panel 增减）：`.spring(response: 0.3)`
- 内容切换（tab）：`.opacity` 淡入淡出

---

## 组件拆分

| 组件 | 职责 |
|------|------|
| `AgentMonitorPanel` | 侧边栏容器，保持现有结构，宽度改为 180px |
| `AgentSessionGroup` | Session 分组行（可点击） + subagent 列表 |
| `AgentSubagentRow` | 单个 subagent 侧边栏行，处理 click / cmd+click |
| `AgentDrawer` | Drawer 容器，管理 selectedItems 状态、宽度动画 |
| `AgentDrawerPanel` | 单个详情 panel（header + tabs + content） |
| `SessionOverviewContent` | Session Overview tab 内容 |
| `SubagentOutputContent` | Output tab 内容 |
| `SubagentTraceContent` | Trace tab 内容（复用现有 tool call 树逻辑） |
| `SubagentPromptContent` | Prompt tab 内容 |

### 数据流

```
AgentSessionManager.$sessions
  └─ AgentMonitorViewModel（现有）
       └─ AgentMonitorPanel（侧边栏）
            └─ AgentDrawer（独立 @State：selectedItems: [DrawerItem]）
```

`DrawerItem` 是一个枚举：

```swift
enum DrawerItem: Identifiable, Equatable {
    case sessionOverview(AgentSession)
    case subagentDetail(AgentSession, SubagentInfo)
}
```

---

## 不在本次范围内

- Drawer 上下分屏布局（⬛≡）暂不实现，按钮保留但 disabled
- 超过 3 个 subagent 并排（保留 3 个上限，超出忽略）
- Drawer 可拖动调整宽度
- Subagent 输出的实时流式更新（基于现有 hook 轮询）

---

## 受影响文件

- `macos/Sources/Features/Agent/Monitor/AgentMonitorPanel.swift` — 重构
- `macos/Sources/Features/Agent/Monitor/AgentMonitorViewModel.swift` — 小改（width 移除）
- `macos/Sources/Features/Agent/Monitor/SubagentListView.swift` — 拆解为新组件
- 新增：`AgentDrawer.swift`, `AgentDrawerPanel.swift`, `AgentSessionGroup.swift`, `DrawerItem.swift`
