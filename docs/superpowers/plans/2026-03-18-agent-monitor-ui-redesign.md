# Agent Monitor UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Agent Monitor 从固定侧边栏重设计为「180px 侧边栏 + Overlay Drawer」模式，支持 session Overview 和 subagent 详情/Split 对比视图。

**Architecture:** 侧边栏（`AgentMonitorPanel`）保持在 `PolterttyRootView` 的 HStack 中，宽度缩减为 180px。Drawer（`AgentDrawer`）以 SwiftUI overlay 形式浮于终端区域上方，由 `AgentMonitorViewModel` 中的 `selectedItems` 状态驱动开关和内容。点击 Session 标题显示 Overview，点击 Subagent 显示详情，Cmd+Click 追加 panel 形成 Split 视图（最多 3 个）。

**Tech Stack:** SwiftUI, macOS 14+, Combine, 现有 `AgentSession` / `AgentSessionManager` 数据模型

---

## 文件结构

### 新建文件

| 文件 | 职责 |
|------|------|
| `Monitor/DrawerItem.swift` | enum `DrawerItem { sessionOverview(AgentSession) \| subagentDetail(AgentSession, SubagentInfo) }` |
| `Monitor/AgentDrawer.swift` | Drawer 容器：layout 切换、panel 列表、宽度动画 |
| `Monitor/AgentDrawerPanel.swift` | 单个 panel：header（状态点、名称、耗时、call 数）+ tabs（Output/Trace/Prompt）+ 内容区 |
| `Monitor/SessionOverviewContent.swift` | Session Overview tab：总耗时、cost、context 进度条、subagent 状态列表 |
| `Monitor/SubagentOutputContent.swift` | Output tab：结果文本 / 错误摘要 |
| `Monitor/SubagentTraceContent.swift` | Trace tab：从现有 `SubagentListView` 提取工具调用树逻辑 |
| `Monitor/SubagentPromptContent.swift` | Prompt tab：完整 prompt 文本，带滚动 |
| `Monitor/AgentSessionGroup.swift` | 侧边栏中的 session 分组行 + subagent 列表 |

### 修改文件

| 文件 | 修改内容 |
|------|---------|
| `Monitor/AgentMonitorViewModel.swift` | 添加 `selectedItems: [DrawerItem]`，`select()` / `cmdClick()` / `closeDrawer()` / `closePanel(_:)` |
| `Monitor/AgentMonitorPanel.swift` | 重构为 180px 侧边栏，使用 `AgentSessionGroup`，移除旧 `AgentSessionRow` |
| `Monitor/SubagentListView.swift` | 删除（逻辑拆分到 `SubagentTraceContent` 和 `AgentSessionGroup`） |
| `Workspace/PolterttyRootView.swift` | 在终端区域添加 `.overlay(alignment: .trailing)` 挂载 `AgentDrawer` |

---

## Task 1: DrawerItem 枚举 + ViewModel 选中状态

**Files:**
- Create: `macos/Sources/Features/Agent/Monitor/DrawerItem.swift`
- Modify: `macos/Sources/Features/Agent/Monitor/AgentMonitorViewModel.swift`

- [ ] **Step 1: 创建 DrawerItem.swift**

```swift
// macos/Sources/Features/Agent/Monitor/DrawerItem.swift
import Foundation

enum DrawerItem: Identifiable, Equatable {
    case sessionOverview(AgentSession)
    case subagentDetail(AgentSession, SubagentInfo)

    var id: String {
        switch self {
        case .sessionOverview(let s):      return "session-\(s.id)"
        case .subagentDetail(_, let sub):  return "sub-\(sub.id)"
        }
    }

    static func == (lhs: DrawerItem, rhs: DrawerItem) -> Bool { lhs.id == rhs.id }
}
```

- [ ] **Step 2: 更新 AgentMonitorViewModel.swift**

在现有 `isVisible` / `width` 后添加：

```swift
@Published var selectedItems: [DrawerItem] = []

var drawerWidth: CGFloat {
    switch selectedItems.count {
    case 0:  return 0
    case 1:  return 400
    case 2:  return 800
    default: return 1200
    }
}

/// 单击：替换整个 selectedItems
func select(_ item: DrawerItem) {
    selectedItems = [item]
}

/// Cmd+Click：追加（已存在则移除），最多 3 个
func cmdClick(_ item: DrawerItem) {
    if let idx = selectedItems.firstIndex(of: item) {
        selectedItems.remove(at: idx)
    } else if selectedItems.count < 3 {
        selectedItems.append(item)
    }
}

func closePanel(_ item: DrawerItem) {
    selectedItems.removeAll { $0 == item }
}

func closeDrawer() {
    selectedItems = []
}
```

- [ ] **Step 3: Build 确认编译**

```bash
cd /Users/aaronlin/works/codes/oss/poltertty/.worktrees/workspace-ai-agent
make dev 2>&1 | grep -E "error:|BUILD"
```
期望：`** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Agent/Monitor/DrawerItem.swift \
        macos/Sources/Features/Agent/Monitor/AgentMonitorViewModel.swift
git commit -m "feat(agent-monitor): add DrawerItem enum and selection state in ViewModel"
```

---

## Task 2: 侧边栏 Session 分组组件

**Files:**
- Create: `macos/Sources/Features/Agent/Monitor/AgentSessionGroup.swift`

- [ ] **Step 1: 创建 AgentSessionGroup.swift**

```swift
// macos/Sources/Features/Agent/Monitor/AgentSessionGroup.swift
import SwiftUI

struct AgentSessionGroup: View {
    let session: AgentSession
    @ObservedObject var viewModel: AgentMonitorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Session 标题行（可点击 → Overview）──────────
            sessionRow
            // ── Subagent 列表 ────────────────────────────────
            if !session.subagents.isEmpty {
                ForEach(sortedSubagents) { sub in
                    subagentRow(sub)
                }
            }
        }
    }

    // MARK: - Session row

    private var sessionRow: some View {
        let item = DrawerItem.sessionOverview(session)
        let isSelected = viewModel.selectedItems.contains(item)
        return HStack(spacing: 5) {
            AgentStateDot(state: session.state)
            Text(session.definition.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isSelected ? Color(hex: "#90bfff") : .primary)
                .lineLimit(1)
            Spacer()
            if activeCount > 0 {
                Text("\(activeCount)↑")
                    .font(.system(size: 8, weight: .medium))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color(hex: "#1a2e1a"))
                    .foregroundStyle(Color(hex: "#4caf50"))
                    .clipShape(Capsule())
            } else {
                Text("done")
                    .font(.system(size: 8))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color(.separatorColor).opacity(0.4))
                    .foregroundStyle(.tertiary)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(isSelected ? Color(hex: "#1a2535") : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.select(item) }
    }

    // MARK: - Subagent row

    private func subagentRow(_ sub: SubagentInfo) -> some View {
        let item = DrawerItem.subagentDetail(session, sub)
        let isSelected = viewModel.selectedItems.contains(item)
        return HStack(spacing: 4) {
            stateDot(sub.state)
            Text(sub.name)
                .font(.system(size: 9))
                .foregroundStyle(isSelected ? Color(hex: "#90bfff") : .secondary)
                .lineLimit(1).truncationMode(.tail)
            Spacer()
            Text(elapsedLabel(sub))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(isSelected ? Color(hex: "#4a6a99") : .tertiary)
        }
        .padding(.leading, 20).padding(.trailing, 10).padding(.vertical, 3)
        .background(isSelected ? Color(hex: "#152040") : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.select(item) }
        // Cmd+Click 多选
        .simultaneousGesture(TapGesture().modifiers(.command).onEnded { _ in
            viewModel.cmdClick(item)
        })
    }

    // MARK: - Helpers

    private var sortedSubagents: [SubagentInfo] {
        Array(session.subagents.values).sorted { $0.startedAt < $1.startedAt }
    }

    private var activeCount: Int {
        session.subagents.values.filter { $0.state.isActive }.count
    }

    private func stateDot(_ state: AgentState) -> some View {
        let color: Color = {
            switch state {
            case .working:  return Color(hex: "#4caf50")
            case .error:    return Color(hex: "#f44336")
            case .idle:     return Color(hex: "#ff9800")
            default:        return Color(hex: "#555555")
            }
        }()
        return Circle().fill(color).frame(width: 5, height: 5)
    }

    private func elapsedLabel(_ sub: SubagentInfo) -> String {
        let end = sub.finishedAt ?? Date()
        let secs = max(0, Int(end.timeIntervalSince(sub.startedAt)))
        if secs < 60 { return "\(secs)s" }
        return "\(secs/60)m\(secs%60)s"
    }
}

// MARK: - Color hex helper (extend if not already in codebase)
private extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        self.init(
            red:   Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8)  & 0xFF) / 255,
            blue:  Double( rgb        & 0xFF) / 255
        )
    }
}
```

> **注意**：如果项目已有 `Color(hex:)` 扩展，删除文件末尾的 private extension，避免重复定义。先搜索：`grep -r "init(hex" macos/Sources/`

- [ ] **Step 2: Build 确认**

```bash
make dev 2>&1 | grep -E "error:|BUILD"
```
期望：`** BUILD SUCCEEDED **`（若有 `Color(hex:)` 重复定义错误，删除文件内的 private extension）

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Agent/Monitor/AgentSessionGroup.swift
git commit -m "feat(agent-monitor): add AgentSessionGroup sidebar component"
```

---

## Task 3: 重构侧边栏 AgentMonitorPanel

**Files:**
- Modify: `macos/Sources/Features/Agent/Monitor/AgentMonitorPanel.swift`

- [ ] **Step 1: 替换 AgentMonitorPanel 内容**

将整个文件替换为：

```swift
// macos/Sources/Features/Agent/Monitor/AgentMonitorPanel.swift
import SwiftUI

struct AgentMonitorPanel: View {
    @ObservedObject var viewModel: AgentMonitorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Text("Agents").font(.system(size: 11, weight: .semibold))
                Spacer()
                Button { viewModel.toggle() } label: {
                    Image(systemName: "xmark").font(.system(size: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color(.windowBackgroundColor))
            Divider()

            if viewModel.sessions.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Text("No active agents").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("⌘⇧A to launch").font(.system(size: 10)).foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.sessions) { session in
                            AgentSessionGroup(session: session, viewModel: viewModel)
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(width: 180)
        .background(Color(.windowBackgroundColor))
    }
}
```

- [ ] **Step 2: Build 确认**

```bash
make dev 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: 打开 app 目测侧边栏形态**

```bash
open ~/Library/Developer/Xcode/DerivedData/Ghostty-atmjlipvxcedomdfuzmhsntvcxpe/Build/Products/Debug/Poltertty.app
```

验证：侧边栏宽度约 180px，可见 session 分组和 subagent 列表，点击无崩溃。

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Agent/Monitor/AgentMonitorPanel.swift
git commit -m "refactor(agent-monitor): sidebar 重构为 180px，使用 AgentSessionGroup"
```

---

## Task 4: Drawer 内容视图

**Files:**
- Create: `Monitor/SessionOverviewContent.swift`
- Create: `Monitor/SubagentOutputContent.swift`
- Create: `Monitor/SubagentTraceContent.swift`
- Create: `Monitor/SubagentPromptContent.swift`

- [ ] **Step 1: 创建 SessionOverviewContent.swift**

```swift
// macos/Sources/Features/Agent/Monitor/SessionOverviewContent.swift
import SwiftUI

struct SessionOverviewContent: View {
    let session: AgentSession

    private var subagents: [SubagentInfo] {
        Array(session.subagents.values).sorted { $0.startedAt < $1.startedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // ── Stats ──────────────────────────────────────
                statRow("总耗时", value: elapsedSinceStart)
                statRow("Cost",   value: costLabel)
                statRow("Context", value: String(format: "%.0f%%", session.tokenUsage.contextUtilization * 100))
                contextBar
                    .padding(.bottom, 8)
                Divider().padding(.vertical, 6)

                // ── Subagent list ─────────────────────────────
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
            }
            .padding(12)
        }
    }

    // MARK: - Sub-views

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 10, design: .monospaced)).foregroundStyle(.primary)
        }
        .padding(.bottom, 3)
    }

    private var contextBar: some View {
        let u = CGFloat(session.tokenUsage.contextUtilization)
        let color: Color = u < 0.55 ? Color(hex: "#4caf50") : u < 0.75 ? .yellow : .red
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Color(.separatorColor)).frame(height: 3)
                RoundedRectangle(cornerRadius: 2).fill(color)
                    .frame(width: geo.size.width * u, height: 3)
            }
        }
        .frame(height: 3)
    }

    private func overviewRow(_ sub: SubagentInfo) -> some View {
        HStack(spacing: 6) {
            stateIcon(sub.state)
            Text(sub.name)
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: "#569cd6"))
                .lineLimit(1).truncationMode(.tail)
            stateBadge(sub.state)
            Spacer()
            Text(elapsed(sub)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func stateIcon(_ state: AgentState) -> some View {
        let (sym, col): (String, Color) = {
            switch state {
            case .done:    return ("checkmark", Color(hex: "#4caf50"))
            case .error:   return ("xmark", Color(hex: "#f44336"))
            case .working: return ("circle.fill", Color(hex: "#ff9800"))
            default:       return ("circle", .secondary)
            }
        }()
        return Image(systemName: sym).font(.system(size: 9)).foregroundStyle(col)
    }

    private func stateBadge(_ state: AgentState) -> some View {
        let (label, bg, fg): (String, Color, Color) = {
            switch state {
            case .done:    return ("done",    Color(hex: "#1a2e1a"), Color(hex: "#4caf50"))
            case .error:   return ("error",   Color(hex: "#2e1a1a"), Color(hex: "#f44336"))
            case .working: return ("running", Color(hex: "#1a2535"), Color(hex: "#90bfff"))
            default:       return ("idle",    Color(.separatorColor).opacity(0.4), .secondary)
            }
        }()
        return Text(label)
            .font(.system(size: 8, weight: .medium))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(bg).foregroundStyle(fg)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    // MARK: - Helpers

    private var elapsedSinceStart: String {
        let secs = max(0, Int(Date().timeIntervalSince(session.startedAt)))
        if secs < 60 { return "\(secs)s" }
        return "\(secs/60)m \(secs%60)s"
    }

    private var costLabel: String {
        let d = NSDecimalNumber(decimal: session.tokenUsage.cost).doubleValue
        return d > 0 ? String(format: "$%.4f", d) : "—"
    }

    private func elapsed(_ sub: SubagentInfo) -> String {
        let end = sub.finishedAt ?? Date()
        let s = max(0, Int(end.timeIntervalSince(sub.startedAt)))
        return s < 60 ? "\(s)s" : "\(s/60)m\(s%60)s"
    }
}

private extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        var rgb: UInt64 = 0; Scanner(string: h).scanHexInt64(&rgb)
        self.init(red: Double((rgb>>16)&0xFF)/255, green: Double((rgb>>8)&0xFF)/255, blue: Double(rgb&0xFF)/255)
    }
}
```

- [ ] **Step 2: 创建 SubagentOutputContent.swift**

```swift
// macos/Sources/Features/Agent/Monitor/SubagentOutputContent.swift
import SwiftUI

/// Output tab：若 subagent 有错误，展示错误摘要；否则展示最近工具调用结果摘要
struct SubagentOutputContent: View {
    let session: AgentSession
    let subagent: SubagentInfo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                switch subagent.state {
                case .error(let msg):
                    errorView(msg)
                case .done:
                    doneView
                case .working, .launching:
                    runningView
                default:
                    Text("等待输出…").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func errorView(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("中断于错误", systemImage: "xmark.circle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color(hex: "#f44336"))

            Text(msg)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(hex: "#f44336"))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "#1e0f0f"))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            completedCallsView
        }
    }

    private var doneView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("已完成", systemImage: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color(hex: "#4caf50"))
            completedCallsView
        }
    }

    private var runningView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("运行中", systemImage: "bolt.circle.fill")
                .font(.system(size: 10)).foregroundStyle(Color(hex: "#ff9800"))
            completedCallsView
        }
    }

    private var completedCallsView: some View {
        let done = subagent.toolCalls.filter { $0.isDone }
        let total = subagent.toolCalls.count
        guard !done.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(VStack(alignment: .leading, spacing: 3) {
            Text("已完成调用 (\(done.count)/\(total))：")
                .font(.system(size: 9)).foregroundStyle(.secondary)
            ForEach(done) { call in
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 8)).foregroundStyle(Color(hex: "#4caf50"))
                    Text(call.toolName).font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            if total > done.count {
                HStack(spacing: 4) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 8)).foregroundStyle(.orange)
                    Text("未完成: \(total - done.count) 个").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
        })
    }
}

private extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        var rgb: UInt64 = 0; Scanner(string: h).scanHexInt64(&rgb)
        self.init(red: Double((rgb>>16)&0xFF)/255, green: Double((rgb>>8)&0xFF)/255, blue: Double(rgb&0xFF)/255)
    }
}
```

- [ ] **Step 3: 创建 SubagentTraceContent.swift**（从现有 `SubagentListView.swift` 提取工具调用树）

```swift
// macos/Sources/Features/Agent/Monitor/SubagentTraceContent.swift
import SwiftUI

/// Trace tab：展示 subagent 的工具调用序列（树形）
struct SubagentTraceContent: View {
    let subagent: SubagentInfo
    @State private var tick = Date()
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if subagent.toolCalls.isEmpty {
                    Text(subagent.state.isActive ? "等待工具调用…" : "无工具调用记录")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                        .padding(12)
                } else {
                    Text("Tool calls (\(subagent.toolCalls.count))")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
                    ForEach(Array(subagent.toolCalls.enumerated()), id: \.element.id) { idx, call in
                        callRow(call, isLast: idx == subagent.toolCalls.count - 1)
                    }
                }
            }
        }
        .onReceive(timer) { t in if subagent.state.isActive { tick = t } }
    }

    private func callRow(_ call: ToolCallRecord, isLast: Bool) -> some View {
        HStack(spacing: 4) {
            Spacer().frame(width: 12)
            treeConnector(last: isLast)
            if call.isDone {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9)).foregroundStyle(Color(hex: "#4caf50"))
            } else {
                Circle().fill(Color.orange).frame(width: 6, height: 6)
            }
            Text(call.toolName)
                .font(.system(size: 10, weight: call.isDone ? .regular : .medium))
                .foregroundStyle(call.isDone ? .secondary : .primary)
            Spacer()
            Text(durationFor(call))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(call.isDone ? .tertiary : .orange)
        }
        .padding(.trailing, 12).frame(height: 18)
    }

    private func treeConnector(last: Bool) -> some View {
        Canvas { ctx, size in
            var path = Path()
            let mid = size.width / 2
            path.move(to: .init(x: mid, y: 0))
            path.addLine(to: .init(x: mid, y: last ? size.height/2 : size.height))
            path.move(to: .init(x: mid, y: size.height/2))
            path.addLine(to: .init(x: size.width, y: size.height/2))
            ctx.stroke(path, with: .color(.secondary.opacity(0.35)), lineWidth: 1)
        }
        .frame(width: 10, height: 18)
    }

    private func durationFor(_ call: ToolCallRecord) -> String {
        guard call.isDone else {
            let s = max(0, Int(tick.timeIntervalSince(call.startedAt)))
            return s < 60 ? "\(s)s" : "\(s/60)m\(s%60)s"
        }
        let calls = subagent.toolCalls
        guard let idx = calls.firstIndex(where: { $0.id == call.id }) else { return "" }
        let end: Date = idx + 1 < calls.count ? calls[idx+1].startedAt : (subagent.finishedAt ?? Date())
        let s = max(0, Int(end.timeIntervalSince(call.startedAt)))
        return s < 60 ? "\(s)s" : "\(s/60)m\(s%60)s"
    }
}

private extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        var rgb: UInt64 = 0; Scanner(string: h).scanHexInt64(&rgb)
        self.init(red: Double((rgb>>16)&0xFF)/255, green: Double((rgb>>8)&0xFF)/255, blue: Double(rgb&0xFF)/255)
    }
}
```

- [ ] **Step 4: 创建 SubagentPromptContent.swift**

```swift
// macos/Sources/Features/Agent/Monitor/SubagentPromptContent.swift
import SwiftUI

struct SubagentPromptContent: View {
    let subagent: SubagentInfo

    var body: some View {
        ScrollView {
            if let prompt = subagent.prompt, !prompt.isEmpty {
                Text(prompt)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else {
                Text("Prompt 未记录")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .padding(12)
            }
        }
    }
}
```

- [ ] **Step 5: Build 确认**

```bash
make dev 2>&1 | grep -E "error:|BUILD"
```
期望：`** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Agent/Monitor/SessionOverviewContent.swift \
        macos/Sources/Features/Agent/Monitor/SubagentOutputContent.swift \
        macos/Sources/Features/Agent/Monitor/SubagentTraceContent.swift \
        macos/Sources/Features/Agent/Monitor/SubagentPromptContent.swift
git commit -m "feat(agent-monitor): add drawer content views (Overview, Output, Trace, Prompt)"
```

---

## Task 5: AgentDrawerPanel（单个 panel）

**Files:**
- Create: `macos/Sources/Features/Agent/Monitor/AgentDrawerPanel.swift`

- [ ] **Step 1: 创建 AgentDrawerPanel.swift**

```swift
// macos/Sources/Features/Agent/Monitor/AgentDrawerPanel.swift
import SwiftUI

enum DrawerTab: String, CaseIterable {
    case output = "Output"
    case trace  = "Trace"
    case prompt = "Prompt"
    case overview = "Overview"
}

struct AgentDrawerPanel: View {
    let item: DrawerItem
    let onClose: () -> Void
    @State private var tab: DrawerTab

    init(item: DrawerItem, onClose: @escaping () -> Void) {
        self.item = item
        self.onClose = onClose
        // 默认 tab 因 item 类型而异
        switch item {
        case .sessionOverview:   _tab = State(initialValue: .overview)
        case .subagentDetail:    _tab = State(initialValue: .output)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            tabBar
            Divider()
            contentArea
        }
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 6) {
            statusDot
            Text(titleText)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1).truncationMode(.tail)
            Spacer()
            if case .subagentDetail(_, let sub) = item {
                metricsRow(sub)
            }
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 9))
            }
            .buttonStyle(.plain).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color(.windowBackgroundColor).opacity(0.95))
    }

    @ViewBuilder
    private var statusDot: some View {
        switch item {
        case .sessionOverview(let s):
            AgentStateDot(state: s.state)
        case .subagentDetail(_, let sub):
            AgentStateDot(state: sub.state)
        }
    }

    private var titleText: String {
        switch item {
        case .sessionOverview(let s):       return s.definition.name
        case .subagentDetail(_, let sub):   return sub.name
        }
    }

    private func metricsRow(_ sub: SubagentInfo) -> some View {
        let elapsed: String = {
            let end = sub.finishedAt ?? Date()
            let s = max(0, Int(end.timeIntervalSince(sub.startedAt)))
            return s < 60 ? "\(s)s" : "\(s/60)m\(s%60)s"
        }()
        return HStack(spacing: 6) {
            Label(elapsed, systemImage: "clock").font(.system(size: 9)).foregroundStyle(.secondary)
            Label("\(sub.toolCalls.count)", systemImage: "wrench").font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }

    // MARK: - Tab bar

    private var availableTabs: [DrawerTab] {
        switch item {
        case .sessionOverview:  return [.overview]
        case .subagentDetail:   return [.output, .trace, .prompt]
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(availableTabs, id: \.self) { t in
                Button(action: { tab = t }) {
                    Text(t.rawValue)
                        .font(.system(size: 10))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .foregroundStyle(tab == t ? .primary : .secondary)
                        .overlay(alignment: .bottom) {
                            if tab == t {
                                Rectangle().fill(Color.accentColor).frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        switch item {
        case .sessionOverview(let session):
            SessionOverviewContent(session: session)
        case .subagentDetail(let session, let sub):
            switch tab {
            case .output:   SubagentOutputContent(session: session, subagent: sub)
            case .trace:    SubagentTraceContent(subagent: sub)
            case .prompt:   SubagentPromptContent(subagent: sub)
            default:        EmptyView()
            }
        }
    }
}
```

- [ ] **Step 2: Build 确认**

```bash
make dev 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Agent/Monitor/AgentDrawerPanel.swift
git commit -m "feat(agent-monitor): add AgentDrawerPanel with tab switching"
```

---

## Task 6: AgentDrawer（Drawer 容器 + 动画）

**Files:**
- Create: `macos/Sources/Features/Agent/Monitor/AgentDrawer.swift`

- [ ] **Step 1: 创建 AgentDrawer.swift**

```swift
// macos/Sources/Features/Agent/Monitor/AgentDrawer.swift
import SwiftUI

struct AgentDrawer: View {
    @ObservedObject var viewModel: AgentMonitorViewModel

    var body: some View {
        if !viewModel.selectedItems.isEmpty {
            HStack(spacing: 0) {
                Divider()
                VStack(spacing: 0) {
                    drawerHeader
                    Divider()
                    HStack(spacing: 0) {
                        ForEach(viewModel.selectedItems) { item in
                            AgentDrawerPanel(item: item) {
                                viewModel.closePanel(item)
                            }
                            if item != viewModel.selectedItems.last {
                                Divider()
                            }
                        }
                    }
                }
                .frame(width: viewModel.drawerWidth)
                .background(Color(.windowBackgroundColor))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.selectedItems.count)
        }
    }

    // MARK: - Global header

    private var drawerHeader: some View {
        HStack(spacing: 8) {
            Text(headerTitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            // 布局切换按钮（上下分屏暂不实现，保留 UI）
            HStack(spacing: 3) {
                layoutBtn(icon: "square.split.2x1", isActive: true)
                layoutBtn(icon: "square.split.1x2", isActive: false)
                    .opacity(0.4)  // disabled
            }
            Button(action: viewModel.closeDrawer) {
                Image(systemName: "xmark").font(.system(size: 10))
            }
            .buttonStyle(.plain).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(.windowBackgroundColor))
    }

    private var headerTitle: String {
        switch viewModel.selectedItems.count {
        case 1:
            switch viewModel.selectedItems[0] {
            case .sessionOverview(let s):     return s.definition.name
            case .subagentDetail(let s, _):   return s.definition.name
            }
        default:
            return "对比模式"
        }
    }

    private func layoutBtn(icon: String, isActive: Bool) -> some View {
        Image(systemName: icon)
            .font(.system(size: 10))
            .padding(4)
            .background(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
            .foregroundStyle(isActive ? .accentColor : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
```

- [ ] **Step 2: Build 确认**

```bash
make dev 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Agent/Monitor/AgentDrawer.swift
git commit -m "feat(agent-monitor): add AgentDrawer container with animation"
```

---

## Task 7: 挂载 Drawer 到 PolterttyRootView

**Files:**
- Modify: `macos/Sources/Features/Workspace/PolterttyRootView.swift`

- [ ] **Step 1: 定位现有 Agent Monitor 挂载点**

在 `PolterttyRootView.swift` 中找到（约第 203 行）：

```swift
// Agent Monitor Panel
if agentMonitorVM.isVisible {
    Divider()
    AgentMonitorPanel(viewModel: agentMonitorVM)
}
```

- [ ] **Step 2: 在 `case .terminal:` HStack 上挂载 overlay**

`case .terminal:` 的 HStack 结构（`PolterttyRootView.swift` 约第 133–208 行）：

```
case .terminal:
    HStack(spacing: 0) {        // line 134
        // WorkspaceSidebar     // line 136
        // FileBrowserPanel     // line 156
        // terminalAreaView     // line 196–200
        // AgentMonitorPanel    // line 203–207
    }                           // line 208
```

在该 HStack 的右花括号（第 208 行）之后，追加 `.overlay`。最终代码形如：

```swift
                } // ← 这是 case .terminal: 的 HStack 闭合括号（约第 208 行）
                .overlay(alignment: .trailing) {
                    HStack(spacing: 0) {
                        AgentDrawer(viewModel: agentMonitorVM)
                        // 占位 180px + 1px divider，使 Drawer 浮于终端上方而不遮盖侧边栏
                        if agentMonitorVM.isVisible {
                            Spacer().frame(width: 181)
                        }
                    }
                }
```

整个修改仅在 HStack 之后插入 `.overlay(...)`，不移动任何现有代码。
AgentMonitorPanel 留在 HStack 内不变（Task 3 已重构为 180px）。

- [ ] **Step 3: Build 确认**

```bash
make dev 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 4: 端到端视觉验证**

```bash
open ~/Library/Developer/Xcode/DerivedData/Ghostty-atmjlipvxcedomdfuzmhsntvcxpe/Build/Products/Debug/Poltertty.app
```

验证项：
1. 打开 Agent Monitor（⌘⇧M），侧边栏宽 180px，可见 session/subagent 列表
2. 点击 session 标题 → Drawer 从右侧划出，显示 Overview（400px）
3. 点击 subagent → Drawer 显示 Output tab 内容
4. Cmd+Click 第二个 subagent → Drawer 扩展为两列（800px）
5. 点击 panel ✕ → 收缩；最后一个 ✕ → Drawer 关闭

- [ ] **Step 5: 删除旧 SubagentListView.swift**

确认旧文件没有其他引用后删除：

```bash
grep -r "SubagentListView" /Users/aaronlin/works/codes/oss/poltertty/.worktrees/workspace-ai-agent/macos/Sources
# 若无引用：
git rm macos/Sources/Features/Agent/Monitor/SubagentListView.swift
```

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Workspace/PolterttyRootView.swift
git commit -m "feat(agent-monitor): mount AgentDrawer as overlay in PolterttyRootView"
```

---

## Task 8: 最终收尾与验证

- [ ] **Step 1: 完整 build**

```bash
make dev 2>&1 | grep -E "error:|warning:.*error|BUILD"
```

- [ ] **Step 2: 端到端验证清单**

启动 Claude Code，触发一个带多个 subagent 的任务（如 `/superpowers:requesting-code-review`），验证：

- [ ] Session 标题点击 → Overview 显示正确（耗时、cost、context bar、subagent 状态列表）
- [ ] Subagent 行点击 → Output tab 显示（运行中显示已完成调用，done/error 显示结果）
- [ ] Trace tab → 工具调用树渲染，运行中工具显示橙色 + 计时
- [ ] Prompt tab → 显示完整 prompt 文本，支持选中复制
- [ ] Cmd+Click 两个 subagent → Split 视图，两列 panel
- [ ] panel ✕ → 关闭单列；最后一个 ✕ → Drawer 收起
- [ ] Drawer 全局 ✕ → 完全关闭，selectedItems 清空
- [ ] 侧边栏高亮：当前在 Drawer 显示的 subagent 行呈蓝色背景

- [ ] **Step 3: 最终 commit**

```bash
git add \
  macos/Sources/Features/Agent/Monitor/DrawerItem.swift \
  macos/Sources/Features/Agent/Monitor/AgentSessionGroup.swift \
  macos/Sources/Features/Agent/Monitor/AgentDrawer.swift \
  macos/Sources/Features/Agent/Monitor/AgentDrawerPanel.swift \
  macos/Sources/Features/Agent/Monitor/SessionOverviewContent.swift \
  macos/Sources/Features/Agent/Monitor/SubagentOutputContent.swift \
  macos/Sources/Features/Agent/Monitor/SubagentTraceContent.swift \
  macos/Sources/Features/Agent/Monitor/SubagentPromptContent.swift \
  macos/Sources/Features/Agent/Monitor/AgentMonitorPanel.swift \
  macos/Sources/Features/Agent/Monitor/AgentMonitorViewModel.swift \
  macos/Sources/Features/Workspace/PolterttyRootView.swift
git commit -m "feat(agent-monitor): UI 重设计完成 — Sidebar + Overlay Drawer

- 180px 侧边栏：session 分组 + subagent 列表
- 点 session → Overview（耗时/cost/context/subagent 汇总）
- 点 subagent → 详情（Output/Trace/Prompt tabs）
- Cmd+Click 多选 → Split 对比（最多 3 个 panel）
- Drawer 以 overlay 形式浮于终端上方

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```
