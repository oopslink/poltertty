# Agent 关系图可视化 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Session Overview Drawer panel 底部添加水平树状 Agent 关系图，session 节点在左，subagent 节点在右，支持点击跳转详情。

**Architecture:** 新建 `AgentGraphView.swift` 包含 `AgentGraphNode`（节点）和 `AgentGraphView`（布局 + Canvas 连接线）。为把点击事件路由到 `viewModel.select()`，需在 `AgentDrawerPanel` 新增 `viewModel` 参数，由 `AgentDrawer` 传入；`SessionOverviewContent` 新增 `onSubagentTap` 回调，由 `AgentDrawerPanel` 传入。

**Tech Stack:** SwiftUI, Canvas (连接线), ZStack + offset (节点定位)

---

## 文件变更一览

| 文件 | 操作 | 说明 |
|------|------|------|
| `macos/Sources/Features/Agent/Monitor/AgentGraphView.swift` | 新建 | 节点 + 图形布局 |
| `macos/Sources/Features/Agent/Monitor/SessionOverviewContent.swift` | 修改 | 新增 `onSubagentTap` 参数，追加 graph 区域 |
| `macos/Sources/Features/Agent/Monitor/AgentDrawerPanel.swift` | 修改 | 新增 `viewModel` 参数，传给 `SessionOverviewContent` |
| `macos/Sources/Features/Agent/Monitor/AgentDrawer.swift` | 修改 | 实例化 `AgentDrawerPanel` 时传入 `viewModel` |

---

## Task 1: 给 AgentDrawerPanel 增加 viewModel 参数

**Files:**
- Modify: `macos/Sources/Features/Agent/Monitor/AgentDrawerPanel.swift`
- Modify: `macos/Sources/Features/Agent/Monitor/AgentDrawer.swift`

**背景：**
`AgentDrawerPanel` 目前只有 `item` 和 `onClose`，没有 `viewModel`。需要它持有 `viewModel` 以便后续把 `onSubagentTap` 传给 `SessionOverviewContent`。

- [ ] **Step 1: 在 AgentDrawerPanel 增加 viewModel 属性**

  打开 `macos/Sources/Features/Agent/Monitor/AgentDrawerPanel.swift`，在 `let onClose` 后新增一行：

  ```swift
  struct AgentDrawerPanel: View {
      let item: DrawerItem
      let onClose: () -> Void
      let viewModel: AgentMonitorViewModel   // ← 新增
      @State private var tab: DrawerTab
      @State private var tick = Date()
      private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

      init(item: DrawerItem, onClose: @escaping () -> Void, viewModel: AgentMonitorViewModel) {  // ← 新增参数
          self.item = item
          self.onClose = onClose
          self.viewModel = viewModel   // ← 新增
          switch item {
          case .sessionOverview:   _tab = State(initialValue: .overview)
          case .subagentDetail:    _tab = State(initialValue: .output)
          }
      }
  ```

  其余部分保持不变。

- [ ] **Step 2: 更新 AgentDrawer 传入 viewModel**

  打开 `macos/Sources/Features/Agent/Monitor/AgentDrawer.swift`，找到实例化 `AgentDrawerPanel` 的行（约第 16 行）：

  ```swift
  // 修改前
  AgentDrawerPanel(item: item) {
      viewModel.closePanel(item)
  }

  // 修改后
  AgentDrawerPanel(item: item, viewModel: viewModel) {
      viewModel.closePanel(item)
  }
  ```

- [ ] **Step 3: 构建验证**

  ```bash
  cd /Users/aaronlin/works/codes/oss/poltertty/.worktrees/workspace-ai-agent
  xcodebuild -workspace macos/Poltertty.xcworkspace \
    -scheme Poltertty \
    -configuration Debug \
    -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Ghostty-atmjlipvxcedomdfuzmhsntvcxpe \
    build 2>&1 | tail -5
  ```

  期望：`BUILD SUCCEEDED`

- [ ] **Step 4: 提交**

  ```bash
  cd /Users/aaronlin/works/codes/oss/poltertty/.worktrees/workspace-ai-agent
  git add macos/Sources/Features/Agent/Monitor/AgentDrawerPanel.swift \
          macos/Sources/Features/Agent/Monitor/AgentDrawer.swift
  git commit -m "feat: pass viewModel to AgentDrawerPanel for graph tap routing"
  ```

---

## Task 2: 给 SessionOverviewContent 增加 onSubagentTap 回调

**Files:**
- Modify: `macos/Sources/Features/Agent/Monitor/SessionOverviewContent.swift`

**背景：**
`SessionOverviewContent` 目前没有回调参数，需要新增 `onSubagentTap: ((SubagentInfo) -> Void)?`，由 `AgentDrawerPanel.contentArea` 传入。

- [ ] **Step 1: 在 SessionOverviewContent 增加回调参数**

  打开 `macos/Sources/Features/Agent/Monitor/SessionOverviewContent.swift`，在 `let session` 后新增：

  ```swift
  struct SessionOverviewContent: View {
      let session: AgentSession
      var onSubagentTap: ((SubagentInfo) -> Void)? = nil   // ← 新增（默认 nil，向后兼容）

      @State private var tick = Date()
      // ... 其余不变
  ```

- [ ] **Step 2: 在 AgentDrawerPanel.contentArea 传入回调**

  打开 `macos/Sources/Features/Agent/Monitor/AgentDrawerPanel.swift`，找到 `contentArea`（约第 137 行）：

  ```swift
  // 修改前
  case .sessionOverview(let session):
      SessionOverviewContent(session: session)

  // 修改后
  case .sessionOverview(let session):
      SessionOverviewContent(session: session) { sub in
          viewModel.select(.subagentDetail(session, sub))
      }
  ```

- [ ] **Step 3: 构建验证**

  ```bash
  xcodebuild -workspace macos/Poltertty.xcworkspace \
    -scheme Poltertty \
    -configuration Debug \
    -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Ghostty-atmjlipvxcedomdfuzmhsntvcxpe \
    build 2>&1 | tail -5
  ```

  期望：`BUILD SUCCEEDED`

- [ ] **Step 4: 提交**

  ```bash
  git add macos/Sources/Features/Agent/Monitor/SessionOverviewContent.swift \
          macos/Sources/Features/Agent/Monitor/AgentDrawerPanel.swift
  git commit -m "feat: add onSubagentTap callback to SessionOverviewContent"
  ```

---

## Task 3: 新建 AgentGraphView.swift

**Files:**
- Create: `macos/Sources/Features/Agent/Monitor/AgentGraphView.swift`

**背景：**
核心图形组件。`AgentGraphNode` 渲染单个节点（状态色点 + 名称 + 耗时 + 工具调用数），`AgentGraphView` 用 ZStack + Canvas 实现布局和连接线。

**节点尺寸：** session 节点 100×52px，subagent 节点 110×52px，圆角 8px，垂直间距 8px。
**连接线：** session 右边中心 → branchX（+20px）→ 垂直干线（多 subagent 时）→ 各 subagent 左边中心（+20px）。
**`AgentStateDot`** 定义于 `macos/Sources/Features/Workspace/TabBar/TerminalTabItem.swift`，直接使用。

- [ ] **Step 1: 创建文件**

  新建 `macos/Sources/Features/Agent/Monitor/AgentGraphView.swift`，内容如下：

  ```swift
  // macos/Sources/Features/Agent/Monitor/AgentGraphView.swift
  import SwiftUI

  // MARK: - 单节点视图

  struct AgentGraphNode: View {
      let name: String
      let state: AgentState
      let elapsed: String
      let toolCount: Int
      let width: CGFloat
      let isSession: Bool           // session 节点不可点击，背景色不同
      let onTap: (() -> Void)?

      var body: some View {
          Button(action: { onTap?() }) {
              VStack(alignment: .leading, spacing: 3) {
                  HStack(spacing: 4) {
                      AgentStateDot(state: state)
                      Text(name)
                          .font(.system(size: 9, weight: .semibold))
                          .lineLimit(1)
                          .truncationMode(.tail)
                  }
                  HStack(spacing: 4) {
                      Text(elapsed)
                          .font(.system(size: 8))
                          .foregroundStyle(.secondary)
                      if toolCount > 0 {
                          Label("\(toolCount)", systemImage: "wrench.fill")
                              .font(.system(size: 8))
                              .foregroundStyle(.secondary)
                      }
                  }
              }
              .padding(.horizontal, 8)
              .padding(.vertical, 6)
              .frame(width: width, height: 52, alignment: .leading)
              .background(isSession
                  ? Color(.tertiarySystemFill)
                  : Color(.quaternarySystemFill))
              .clipShape(RoundedRectangle(cornerRadius: 8))
          }
          .buttonStyle(.plain)
          .contentShape(Rectangle())
          .disabled(onTap == nil)
      }
  }

  // MARK: - 图形容器

  struct AgentGraphView: View {
      let session: AgentSession
      let tick: Date
      let onSubagentTap: (SubagentInfo) -> Void

      // 布局常量
      private let sessionNodeW: CGFloat = 100
      private let subNodeW: CGFloat = 110
      private let nodeH: CGFloat = 52
      private let gap: CGFloat = 8
      private let hGap: CGFloat = 20   // session 右边 → 垂直干线；垂直干线 → subagent 左边

      // subagents 按 startedAt 排序
      private var subagents: [SubagentInfo] {
          Array(session.subagents.values).sorted { $0.startedAt < $1.startedAt }
      }

      // Canvas 高度 = max(session 节点高, 所有 subagent 节点堆叠高)
      private var totalHeight: CGFloat {
          let n = subagents.count
          if n == 0 { return nodeH }
          return max(nodeH, CGFloat(n) * nodeH + CGFloat(n - 1) * gap)
      }

      private var sessionCY: CGFloat { totalHeight / 2 }

      private func subCY(at index: Int) -> CGFloat {
          CGFloat(index) * (nodeH + gap) + nodeH / 2
      }

      private var branchX: CGFloat { sessionNodeW + hGap }
      private var subLeft: CGFloat { branchX + hGap }

      // 耗时格式化（与现有一致）
      private func elapsedString(from start: Date, to end: Date) -> String {
          let s = max(0, Int(end.timeIntervalSince(start)))
          return s < 60 ? "\(s)s" : "\(s/60)m\(s%60)s"
      }

      var body: some View {
          ZStack(alignment: .topLeading) {
              // ── 连接线 Canvas ──────────────────────────────────────
              Canvas { context, _ in
                  var path = Path()
                  let sCY   = sessionCY
                  let bX    = branchX
                  let sL    = subLeft
                  let cys   = subagents.indices.map { subCY(at: $0) }

                  // session 右边中心 → branchX
                  path.move(to: CGPoint(x: sessionNodeW, y: sCY))
                  path.addLine(to: CGPoint(x: bX, y: sCY))

                  if cys.count > 1, let first = cys.first, let last = cys.last {
                      // 垂直干线（仅多个 subagent 时绘制）
                      path.move(to: CGPoint(x: bX, y: first))
                      path.addLine(to: CGPoint(x: bX, y: last))
                  }

                  // 各分支水平线 → subagent 左边中心
                  for cy in cys {
                      path.move(to: CGPoint(x: bX, y: cy))
                      path.addLine(to: CGPoint(x: sL, y: cy))
                  }

                  context.stroke(path, with: .color(.secondary.opacity(0.3)), lineWidth: 1)
              }
              .frame(height: totalHeight)

              // ── Session 节点（垂直居中）─────────────────────────────
              AgentGraphNode(
                  name: session.definition.name,
                  state: session.state,
                  elapsed: elapsedString(from: session.startedAt, to: tick),
                  toolCount: session.subagents.values.reduce(0) { $0 + $1.toolCalls.count },
                  width: sessionNodeW,
                  isSession: true,
                  onTap: nil
              )
              .offset(y: sessionCY - nodeH / 2)

              // ── Subagent 节点（从上到下排列）──────────────────────
              ForEach(Array(subagents.enumerated()), id: \.element.id) { index, sub in
                  AgentGraphNode(
                      name: sub.name,
                      state: sub.state,
                      elapsed: elapsedString(from: sub.startedAt, to: sub.finishedAt ?? tick),
                      toolCount: sub.toolCalls.count,
                      width: subNodeW,
                      isSession: false,
                      onTap: { onSubagentTap(sub) }
                  )
                  .offset(x: subLeft, y: CGFloat(index) * (nodeH + gap))
              }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .frame(height: totalHeight)
      }
  }
  ```

- [ ] **Step 2: 构建验证**

  ```bash
  xcodebuild -workspace macos/Poltertty.xcworkspace \
    -scheme Poltertty \
    -configuration Debug \
    -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Ghostty-atmjlipvxcedomdfuzmhsntvcxpe \
    build 2>&1 | tail -5
  ```

  期望：`BUILD SUCCEEDED`

- [ ] **Step 3: 提交**

  ```bash
  git add macos/Sources/Features/Agent/Monitor/AgentGraphView.swift
  git commit -m "feat: add AgentGraphView with horizontal tree layout and Canvas connectors"
  ```

---

## Task 4: 在 SessionOverviewContent 集成图形区域

**Files:**
- Modify: `macos/Sources/Features/Agent/Monitor/SessionOverviewContent.swift`

**背景：**
在现有 hint 文字下方，当 `session.subagents` 非空时追加 graph 区域。复用现有 `tick` 传入 `AgentGraphView`。

- [ ] **Step 1: 追加 graph 区域到 body**

  打开 `macos/Sources/Features/Agent/Monitor/SessionOverviewContent.swift`，在 hint 文字之后（`body` 的 VStack 底部，`.onReceive` 之前）追加：

  ```swift
  // 在这行之后：
  Text("点击 subagent 查看详情 · Cmd+Click 并排对比")
      .font(.system(size: 9)).foregroundStyle(.tertiary)

  // 新增：
  if !session.subagents.isEmpty {
      Divider().padding(.vertical, 6)
      Text("AGENT GRAPH")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(.tertiary)
          .padding(.bottom, 4)
      AgentGraphView(session: session, tick: tick) { sub in
          onSubagentTap?(sub)
      }
  }
  ```

  完整的 `body` 应为：

  ```swift
  var body: some View {
      ScrollView {
          VStack(alignment: .leading, spacing: 0) {
              statRow("总耗时", value: elapsedSinceStart)
              statRow("Cost",   value: costLabel)
              statRow("Context", value: String(format: "%.0f%%", session.tokenUsage.contextUtilization * 100))
              contextBar
                  .padding(.bottom, 8)
              Divider().padding(.vertical, 6)

              Text("SUBAGENTS")
                  .font(.system(size: 9, weight: .semibold))
                  .foregroundStyle(.tertiary)
                  .padding(.bottom, 4)

              ForEach(subagents) { sub in
                  overviewRow(sub)
              }

              Divider().padding(.vertical, 6)
              Text("点击 subagent 查看详情 · Cmd+Click 并排对比")
                  .font(.system(size: 9)).foregroundStyle(.tertiary)

              // ── Graph ──
              if !session.subagents.isEmpty {
                  Divider().padding(.vertical, 6)
                  Text("AGENT GRAPH")
                      .font(.system(size: 9, weight: .semibold))
                      .foregroundStyle(.tertiary)
                      .padding(.bottom, 4)
                  AgentGraphView(session: session, tick: tick) { sub in
                      onSubagentTap?(sub)
                  }
              }
          }
          .padding(12)
      }
      .onReceive(timer) { t in if session.state.isActive { tick = t } }
  }
  ```

- [ ] **Step 2: 构建验证**

  ```bash
  xcodebuild -workspace macos/Poltertty.xcworkspace \
    -scheme Poltertty \
    -configuration Debug \
    -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Ghostty-atmjlipvxcedomdfuzmhsntvcxpe \
    build 2>&1 | tail -5
  ```

  期望：`BUILD SUCCEEDED`

- [ ] **Step 3: 运行 App 手动验证**

  ```bash
  open ~/Library/Developer/Xcode/DerivedData/Ghostty-atmjlipvxcedomdfuzmhsntvcxpe/Build/Products/Debug/Poltertty.app
  ```

  验证项：
  - Session Overview panel 底部出现 "AGENT GRAPH" 区域
  - 无 subagent 时：graph 区域不显示
  - 有 subagent 时：session 节点在左，subagent 节点在右，连接线正确
  - 1 个 subagent：无垂直干线，仅一条水平线
  - 多个 subagent：有垂直干线 + 多条分支
  - 点击 subagent 节点：Drawer 切换到该 subagent 的 Output tab
  - 运行中节点：耗时每 3s 更新

- [ ] **Step 4: 提交**

  ```bash
  git add macos/Sources/Features/Agent/Monitor/SessionOverviewContent.swift
  git commit -m "feat: integrate AgentGraphView into SessionOverviewContent"
  ```
