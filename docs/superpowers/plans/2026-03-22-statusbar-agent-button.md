# Status Bar Agent 按钮实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 per-pane status bar 右侧添加 agent 启动按钮，支持选择 agent 类型和权限模式在当前 pane 启动 agent，运行时切换为状态指示器。

**Architecture:** 新增 3 个 SwiftUI 视图文件（AgentButtonView、AgentPickerPopover、AgentSessionPopover），修改 BottomStatusBarView 和 TerminalSplitLeafContainer 传入 surfaceId。AgentButtonView 观察 AgentSessionManager 驱动两种模式切换。启动流程复用已有 AgentLauncher。

**Tech Stack:** Swift, SwiftUI, AppKit (NSPopover)

**Spec:** `docs/superpowers/specs/2026-03-22-statusbar-agent-button-design.md`

---

### Task 1: 传递 surfaceId 到 BottomStatusBarView

**Files:**
- Modify: `macos/Sources/Features/Workspace/BottomStatusBarView.swift:6-9`
- Modify: `macos/Sources/Features/Splits/TerminalSplitTreeView.swift:115-119`

- [ ] **Step 1: 给 BottomStatusBarView 添加 surfaceId 参数**

在 `BottomStatusBarView` 的属性区域新增：

```swift
struct BottomStatusBarView: View {
    @ObservedObject var monitor: GitStatusMonitor
    let pwd: String
    let isFocused: Bool
    let surfaceId: UUID   // 新增
```

- [ ] **Step 2: 更新 TerminalSplitLeafContainer 中的调用**

在 `TerminalSplitTreeView.swift` 第 115 行的调用处添加 surfaceId：

```swift
BottomStatusBarView(
    monitor: statusMonitor,
    pwd: surfaceView.pwd ?? "",
    isFocused: isFocused,
    surfaceId: surfaceView.id   // 新增
)
```

- [ ] **Step 3: 确认编译通过**

Run: `cd /Users/oopslink/works/codes/oopslink/poltertty && make build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Workspace/BottomStatusBarView.swift macos/Sources/Features/Splits/TerminalSplitTreeView.swift
git commit -m "refactor(statusbar): pass surfaceId to BottomStatusBarView"
```

---

### Task 2: 创建 AgentButtonView

**Files:**
- Create: `macos/Sources/Features/Workspace/AgentButton/AgentButtonView.swift`
- Modify: `macos/Sources/Features/Workspace/BottomStatusBarView.swift`

- [ ] **Step 1: 创建 AgentButtonView.swift**

```swift
// macos/Sources/Features/Workspace/AgentButton/AgentButtonView.swift

import SwiftUI

/// Status bar 中的 Agent 按钮：无 session 时显示启动入口，有 session 时显示状态指示器
struct AgentButtonView: View {
    let surfaceId: UUID

    @ObservedObject private var sessionManager = AgentService.shared.sessionManager
    @State private var showPopover = false

    private var session: AgentSession? {
        sessionManager.sessions[surfaceId]
    }

    var body: some View {
        Button(action: { showPopover.toggle() }) {
            if let session {
                agentStateIcon(session: session)
            } else {
                Text("⬡")
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            if let session {
                AgentSessionPopover(session: session)
            } else {
                AgentPickerPopover(surfaceId: surfaceId, isPresented: $showPopover)
            }
        }
    }

    @ViewBuilder
    private func agentStateIcon(session: AgentSession) -> some View {
        let color = session.definition.iconColor.flatMap { Color(hex: $0) } ?? .secondary
        Text(session.definition.icon)
            .foregroundColor(color)
            .opacity(session.state == .working ? 1.0 : (session.state.isActive ? 0.8 : 0.4))
            .animation(
                session.state == .working
                    ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                    : .default,
                value: session.state == .working
            )
    }
}
```

- [ ] **Step 2: 在 BottomStatusBarView 右侧添加 AgentButtonView**

在 `BottomStatusBarView.swift` 的 body 中，git 状态区域之后、HStack 结束前添加：

```swift
                // 右：git 状态
                if status.isGitRepo {
                    // ... 现有 git 代码 ...
                }
                AgentButtonView(surfaceId: surfaceId)
```

注意：AgentButtonView 放在 git HStack 之后、外层 HStack 结束 `}` 之前（Spacer 之后）。

- [ ] **Step 3: 创建空的 AgentPickerPopover 和 AgentSessionPopover 占位**

先创建空壳让编译通过，后续 Task 填充实现。

`AgentPickerPopover.swift`:
```swift
// macos/Sources/Features/Workspace/AgentButton/AgentPickerPopover.swift

import SwiftUI

struct AgentPickerPopover: View {
    let surfaceId: UUID
    @Binding var isPresented: Bool

    var body: some View {
        Text("Pick an agent")
            .padding()
    }
}
```

`AgentSessionPopover.swift`:
```swift
// macos/Sources/Features/Workspace/AgentButton/AgentSessionPopover.swift

import SwiftUI

struct AgentSessionPopover: View {
    let session: AgentSession

    var body: some View {
        Text(session.definition.name)
            .padding()
    }
}
```

- [ ] **Step 4: 确认编译通过**

Run: `cd /Users/oopslink/works/codes/oopslink/poltertty && make build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Workspace/AgentButton/
git add macos/Sources/Features/Workspace/BottomStatusBarView.swift
git commit -m "feat(statusbar): add AgentButtonView with placeholder popovers"
```

---

### Task 3: 实现 AgentPickerPopover

**Files:**
- Modify: `macos/Sources/Features/Workspace/AgentButton/AgentPickerPopover.swift`

- [ ] **Step 1: 实现完整的 AgentPickerPopover**

```swift
// macos/Sources/Features/Workspace/AgentButton/AgentPickerPopover.swift

import SwiftUI

struct AgentPickerPopover: View {
    let surfaceId: UUID
    @Binding var isPresented: Bool

    @ObservedObject private var registry = AgentRegistry.shared
    @State private var selectedDefinition: AgentDefinition?
    @State private var permissionMode: ClaudePermissionMode = .auto

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Agent 列表
            ForEach(registry.definitions) { def in
                Button(action: { selectedDefinition = def }) {
                    HStack {
                        Text(def.icon)
                            .foregroundColor(def.iconColor.flatMap { Color(hex: $0) } ?? .secondary)
                        Text(def.name)
                            .foregroundColor(.primary)
                        Spacer()
                        if selectedDefinition?.id == def.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .background(selectedDefinition?.id == def.id ? Color.accentColor.opacity(0.1) : .clear)
            }

            Divider()
                .padding(.vertical, 4)

            // 权限模式选择
            HStack {
                Text("Permission")
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $permissionMode) {
                    ForEach(ClaudePermissionMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            Divider()
                .padding(.vertical, 4)

            // Launch 按钮
            HStack {
                Spacer()
                Button("Launch") {
                    launchAgent()
                }
                .disabled(selectedDefinition == nil)
                .keyboardShortcut(.return, modifiers: [])
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .frame(width: 200)
        .padding(.top, 8)
        .onAppear {
            selectedDefinition = registry.definitions.first
        }
    }

    private func launchAgent() {
        guard let def = selectedDefinition else { return }
        isPresented = false

        // 通过 Notification 触发 AgentLauncher（TerminalController 监听）
        NotificationCenter.default.post(
            name: .launchAgentFromStatusBar,
            object: nil,
            userInfo: [
                "surfaceId": surfaceId,
                "definitionId": def.id,
                "permissionMode": permissionMode.rawValue,
            ]
        )
    }
}
```

- [ ] **Step 2: 在 PolterttyRootView.swift 中添加 Notification.Name**

在已有的 `Notification.Name` extension 中添加：

```swift
static let launchAgentFromStatusBar = Notification.Name("launchAgentFromStatusBar")
```

- [ ] **Step 3: 在 TerminalController 中监听通知并调用 AgentLauncher**

在 TerminalController 的 notification 注册区域添加监听：

```swift
NotificationCenter.default.addObserver(
    forName: .launchAgentFromStatusBar,
    object: nil,
    queue: .main
) { [weak self] note in
    guard let self,
          let surfaceId = note.userInfo?["surfaceId"] as? UUID,
          let defId = note.userInfo?["definitionId"] as? String,
          let modeRaw = note.userInfo?["permissionMode"] as? String,
          let mode = ClaudePermissionMode(rawValue: modeRaw),
          let def = AgentRegistry.shared.definitions.first(where: { $0.id == defId })
    else { return }

    // 确保焦点在目标 surface 上（AgentLauncher 使用 focusedSurface）
    if let targetSurface = self.surfaceTree.first(where: { $0.id == surfaceId }) {
        self.focusSurface(targetSurface)
    }

    let cwd = self.surfaceTree.first(where: { $0.id == surfaceId })?.pwd ?? "~"
    self.agentLauncher.launch(
        definition: def,
        location: .currentPane,
        permissionMode: mode,
        workspaceId: self.workspaceId ?? UUID(),
        cwd: cwd
    )
}
```

- [ ] **Step 4: 确认编译通过**

Run: `cd /Users/oopslink/works/codes/oopslink/poltertty && make build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Workspace/AgentButton/AgentPickerPopover.swift
git add macos/Sources/Features/Workspace/PolterttyRootView.swift
git add macos/Sources/Features/Terminal/TerminalController.swift
git commit -m "feat(statusbar): implement AgentPickerPopover with agent selection and permission mode"
```

---

### Task 4: 实现 AgentSessionPopover

**Files:**
- Modify: `macos/Sources/Features/Workspace/AgentButton/AgentSessionPopover.swift`

- [ ] **Step 1: 实现 AgentSessionPopover**

```swift
// macos/Sources/Features/Workspace/AgentButton/AgentSessionPopover.swift

import SwiftUI

struct AgentSessionPopover: View {
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Agent 名称 + 图标
            HStack(spacing: 6) {
                Text(session.definition.icon)
                    .foregroundColor(
                        session.definition.iconColor.flatMap { Color(hex: $0) } ?? .secondary
                    )
                Text(session.definition.name)
                    .fontWeight(.medium)
            }

            Divider()

            // 状态
            HStack {
                Text("Status")
                    .foregroundColor(.secondary)
                Spacer()
                Text(stateText)
                    .foregroundColor(stateColor)
            }

            // 启动时间
            HStack {
                Text("Started")
                    .foregroundColor(.secondary)
                Spacer()
                Text(session.startedAt, style: .relative)
            }

            // Token 用量
            if session.tokenUsage.totalTokens > 0 {
                HStack {
                    Text("Tokens")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatTokens(session.tokenUsage.totalTokens))
                }
            }
        }
        .font(.system(size: 11))
        .padding(12)
        .frame(width: 200)
    }

    private var stateText: String {
        switch session.state {
        case .launching: return "Launching"
        case .working:   return "Working"
        case .idle:      return "Idle"
        case .done:      return "Done"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    private var stateColor: Color {
        switch session.state {
        case .working:   return .green
        case .idle:      return .yellow
        case .done:      return .secondary
        case .error:     return .red
        case .launching: return .blue
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        }
        return "\(count)"
    }
}
```

- [ ] **Step 2: 确认编译通过**

Run: `cd /Users/oopslink/works/codes/oopslink/poltertty && make build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/AgentButton/AgentSessionPopover.swift
git commit -m "feat(statusbar): implement AgentSessionPopover with session details"
```

---

### Task 5: Color(hex:) 扩展

**Files:**
- Create: `macos/Sources/Features/Workspace/AgentButton/Color+Hex.swift`

注意：先搜索项目中是否已有 `Color(hex:)` 扩展。如果已有则跳过此 Task。

- [ ] **Step 1: 搜索现有扩展**

Run: `grep -r "Color.*hex" macos/Sources/ --include="*.swift" -l`

如果找到已有实现，跳过后续步骤。

- [ ] **Step 2: 创建 Color+Hex.swift（仅在不存在时）**

```swift
// macos/Sources/Features/Workspace/AgentButton/Color+Hex.swift

import SwiftUI

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.hasPrefix("#") ? String(hexSanitized.dropFirst()) : hexSanitized

        guard hexSanitized.count == 6,
              let rgb = UInt64(hexSanitized, radix: 16) else { return nil }

        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }
}
```

- [ ] **Step 3: 确认编译通过**

Run: `cd /Users/oopslink/works/codes/oopslink/poltertty && make build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Workspace/AgentButton/Color+Hex.swift
git commit -m "feat: add Color hex string initializer"
```

---

### Task 6: 端到端验证

- [ ] **Step 1: 完整构建**

Run: `cd /Users/oopslink/works/codes/oopslink/poltertty && make build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: 手动验证清单**

启动应用后验证：

1. 打开一个 workspace（非临时），status bar 可见
2. Status bar 右侧出现 `⬡` 图标
3. 点击图标弹出 popover，显示 3 个内置 agent
4. 选择 agent 后出现 checkmark 高亮
5. Permission 下拉框可切换模式
6. 点击 Launch，当前 pane 启动对应 agent 命令
7. 启动后按钮变为 agent 图标和颜色
8. 点击变色后的按钮，弹出 session 详情 popover
9. Agent 退出后，按钮图标变灰

- [ ] **Step 3: 最终 Commit（如有修复）**

```bash
git add -A
git commit -m "fix(statusbar): agent button polish and fixes"
```
