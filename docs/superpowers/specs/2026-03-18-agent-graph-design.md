# Agent 关系图可视化 Design Spec

## 概述

在 Session Overview Drawer panel 底部添加一个水平树状 Agent 关系图，将 session 与其 subagent 的关系以可视化方式呈现，支持点击 subagent 节点跳转到对应详情。

---

## 需求背景

当前 Session Overview 以列表形式展示 subagent，缺乏视觉上的层次感和关系感。当 subagent 数量较多时，用户难以快速感知整体运行结构。关系图提供更直观的视角。

---

## 范围

**包含：**
- 水平树状图，session 节点在左，subagent 节点在右
- 节点显示：状态色点 + 名称 + 耗时 + 工具调用数
- 连接线：从 session 节点引出水平线，垂直分叉到各 subagent
- 点击 subagent 节点：跳转到该 subagent 的 detail panel
- 耗时实时刷新（复用现有 3s tick）
- 仅当 subagents 非空时显示该区域

**不包含：**
- 嵌套 subagent（架构为 flat，不支持多层）
- 拖拽、缩放、滚动（图形适配 panel 宽度）
- Hover tooltip
- 动画（节点 fade-in 除外）

---

## 视觉设计

### 整体布局

```
── AGENT GRAPH ─────────────────────────

  ┌──────────┐          ┌──────────┐
  │ • Session │────┬─────│ • Sub-1  │
  │  My Agent │    │     │ file-rdr │
  │    2m30s  │    │     │  32s·3✦  │
  └──────────┘    │     └──────────┘
                  │
                  ├─────┌──────────┐
                  │     │ • Sub-2  │
                  │     │ code-wrt │
                  │     │  1m·8✦   │
                  │     └──────────┘
                  │
                  └─────┌──────────┐
                        │ • Sub-3  │
                        │  search  │
                        │  10s·2✦  │
                        └──────────┘
```

### 节点规格

| 属性 | Session 节点 | Subagent 节点 |
|------|-------------|--------------|
| 宽度 | 100px | 110px |
| 高度 | 52px | 52px |
| 圆角 | 8px | 8px |
| 背景 | `.tertiarySystemFill` | `.quaternarySystemFill` |
| 边框 | 无 | 无 |

### 节点内容（从上到下，左对齐）

```
● Name (truncated to 10 chars)
  duration · N✦
```

- **状态色点**：使用 `AgentStateDot`（与侧边栏保持一致）
- **名称**：`.font(.system(size: 9, weight: .semibold))`，超出截断
- **耗时**：格式同现有（`Xs` / `Xm Xs`），`.font(.system(size: 8))`，`.foregroundStyle(.secondary)`
- **工具调用数**：`N✦`，仅当 count > 0 显示，`✦` 用 `⚙` 或 wrench SF symbol

### 连接线

- 颜色：`.quaternaryLabel`（约 25% 透明度），lineWidth: 1
- 路径：session 右边中心 → 水平延伸 20px → 垂直段覆盖所有 subagent → 各自水平延伸至 subagent 左边中心

---

## 实现方案

### 新文件

**`macos/Sources/Features/Agent/Monitor/AgentGraphView.swift`**

包含：
- `struct AgentGraphView: View` — 顶层容器，计算布局尺寸，渲染节点 + Canvas 连接线
- `struct AgentGraphNode: View` — 单个节点，可点击

### 集成位置

`SessionOverviewContent.swift` 底部，在现有 hint 文字后追加：

```swift
if !session.subagents.isEmpty {
    section(title: "AGENT GRAPH") {
        AgentGraphView(session: session, tick: tick) { sub in
            // onSubagentTap
        }
    }
}
```

### 布局算法

```
nodeH = 52
gap   = 8
totalH = max(sessionNodeH, subagents.count * (nodeH + gap) - gap)

// Session 节点 Y 中心
sessionCY = totalH / 2

// Subagent 节点 Y（从上到下均匀排列）
subCY[i] = i * (nodeH + gap) + nodeH / 2

// 连接线路径
branchX = sessionNodeW + 20   // 垂直干线 X
subLeft = branchX + 20        // subagent 节点起点 X
```

### Canvas 连接线绘制

```swift
Canvas { context, size in
    var path = Path()
    // 从 session 右侧中心出发
    path.move(to: CGPoint(x: sessionNodeW, y: sessionCY))
    path.addLine(to: CGPoint(x: branchX, y: sessionCY))
    // 垂直干线
    path.move(to: CGPoint(x: branchX, y: subCY.first!))
    path.addLine(to: CGPoint(x: branchX, y: subCY.last!))
    // 各分支
    for cy in subCY {
        path.move(to: CGPoint(x: branchX, y: cy))
        path.addLine(to: CGPoint(x: subLeft, y: cy))
    }
    context.stroke(path, with: .color(.secondary.opacity(0.3)), lineWidth: 1)
}
```

### 点击交互

`AgentGraphNode` 使用 `Button(action: onTap)` + `.buttonStyle(.plain)` + `.contentShape(Rectangle())`，点击时调用外部传入的 closure，由 `SessionOverviewContent` 转发到 `viewModel.select(.subagentDetail(session, sub))`。

### 实时刷新

`AgentGraphView` 接受 `tick: Date` 参数，由 `SessionOverviewContent` 的 `@State tick` 传入，SwiftUI 因参数变化自动重绘。

---

## 数据依赖

- `AgentSession.subagents: [String: SubagentInfo]` — 已有，无需修改
- `SubagentInfo.state`, `.startedAt`, `.finishedAt`, `.toolCalls` — 已有
- `AgentStateDot` — 已有
- `AgentMonitorViewModel.select()` — 已有

无需修改任何数据层文件。

---

## 文件变更清单

| 文件 | 操作 |
|------|------|
| `AgentGraphView.swift` | 新建 |
| `SessionOverviewContent.swift` | 修改（追加 agentGraphSection） |

---

## 测试验证

- 无 subagent 时：图形区域不显示
- 1 个 subagent：session 节点 → 单条水平线 → subagent 节点
- 多个 subagent：垂直干线 + 多条分支
- 点击 subagent 节点：Drawer 切换到该 subagent 的 Output tab
- 运行中 subagent：耗时每 3s 刷新
- 完成后：显示最终耗时
