# Ctrl API Monitor UI 优化实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 移除 Status Bar 上的 Ctrl API Monitor 按钮，为 Detail Pane 添加 JSON 语法高亮，并将四个 Observability 工具整合到 Agent 菜单的 Observability 子菜单中。

**Architecture:** 三个完全独立的改动，可按任意顺序实现。改动二新增 `JSONHighlightView.swift`（`NSViewRepresentable` 包装 `NSTextView`），复用现有 `SyntaxHighlighter`（JSContext + highlight.js）。改动三在 `AppDelegate.swift` 中重组 Agent 菜单，将分散的工具项归入新建的 `NSMenu("Observability")` 子菜单。

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, JavaScriptCore (已有 `SyntaxHighlighter`)

**Worktree:** `.worktrees/feat/ctrl-api-monitor-ui`

---

## 文件变更清单

| 操作 | 文件 | 说明 |
|------|------|------|
| 修改 | `macos/Sources/Features/Workspace/BottomStatusBarView.swift` | 删除 `ctrlAPIStore` 属性和 network 按钮 |
| 新增 | `macos/Sources/Features/Agent/CtrlServer/JSONHighlightView.swift` | NSTextView 语法高亮组件 |
| 修改 | `macos/Sources/Features/Agent/CtrlServer/CtrlAPIMonitorPanel.swift` | 替换 `detailSection` 内的 Text 为 JSONHighlightView |
| 修改 | `macos/Sources/App/macOS/AppDelegate.swift` | 重组 Agent 菜单，新增 Observability 子菜单和 `toggleCtrlAPIMonitor` selector |

---

## Task 1: 移除 Status Bar 按钮

**Files:**
- Modify: `macos/Sources/Features/Workspace/BottomStatusBarView.swift`

- [ ] **Step 1: 打开文件，定位要删除的代码**

  打开 `macos/Sources/Features/Workspace/BottomStatusBarView.swift`。
  定位以下两处代码：

  **属性声明（约第 9 行）：**
  ```swift
  @ObservedObject private var ctrlAPIStore = CtrlAPIStore.shared
  ```

  **按钮代码块（约第 47–53 行）：**
  ```swift
  Button(action: { ctrlAPIStore.isMonitorVisible.toggle() }) {
      Image(systemName: "network")
          .font(.system(size: 11))
          .foregroundStyle(ctrlAPIStore.isMonitorVisible ? Color.accentColor : Color.secondary)
  }
  .buttonStyle(.plain)
  .help("Ctrl API Monitor")
  ```

- [ ] **Step 2: 删除属性声明**

  删除 `@ObservedObject private var ctrlAPIStore = CtrlAPIStore.shared` 整行。

- [ ] **Step 3: 删除按钮代码块**

  删除上述 Button 代码块（7 行）。注意保留 Button 前后的其他代码（`AgentButtonView`、git 状态区域）。

- [ ] **Step 4: 确认编译通过**

  ```bash
  cd macos
  xcodebuild -scheme Ghostty -configuration Debug -destination 'platform=macOS' build 2>&1 | grep -E "error:|Build succeeded"
  ```
  期望输出：`Build succeeded`（无 `error:` 行）

- [ ] **Step 5: Commit**

  ```bash
  git add macos/Sources/Features/Workspace/BottomStatusBarView.swift
  git commit -m "feat(ctrl-api-monitor): 移除 status bar 上的 network 按钮"
  ```

---

## Task 2: 新增 JSONHighlightView

**Files:**
- Create: `macos/Sources/Features/Agent/CtrlServer/JSONHighlightView.swift`

- [ ] **Step 1: 创建文件，写入完整实现**

  创建 `macos/Sources/Features/Agent/CtrlServer/JSONHighlightView.swift`，内容如下：

  ```swift
  // macos/Sources/Features/Agent/CtrlServer/JSONHighlightView.swift
  import SwiftUI
  import AppKit

  /// 用于 Ctrl API Monitor detail pane 的 JSON 语法高亮视图。
  /// 复用 SyntaxHighlighter（JSContext + highlight.js），不含行号 gutter。
  /// 背景固定为 AtomOneDark 深色（与 FileBrowser 高亮风格一致）。
  struct JSONHighlightView: NSViewRepresentable {
      let content: String
      let isError: Bool

      func makeCoordinator() -> Coordinator {
          Coordinator()
      }

      func makeNSView(context: Context) -> NSScrollView {
          let scrollView = NSScrollView()
          scrollView.hasVerticalScroller = true
          scrollView.hasHorizontalScroller = false
          scrollView.autohidesScrollers = true
          scrollView.borderType = .noBorder
          scrollView.backgroundColor = AtomOneDark.background
          scrollView.drawsBackground = true

          let textView = NSTextView()
          textView.isEditable = false
          textView.isSelectable = true
          textView.isRichText = true
          textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
          textView.drawsBackground = true
          textView.backgroundColor = AtomOneDark.background
          textView.textContainerInset = NSSize(width: 8, height: 8)
          textView.isHorizontallyResizable = false
          textView.isVerticallyResizable = true
          textView.autoresizingMask = [.width]
          textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                    height: CGFloat.greatestFiniteMagnitude)
          textView.textContainer?.widthTracksTextView = true

          scrollView.documentView = textView
          context.coordinator.textView = textView
          context.coordinator.highlighter = SyntaxHighlighter()
          return scrollView
      }

      func updateNSView(_ scrollView: NSScrollView, context: Context) {
          let coord = context.coordinator
          guard coord.lastContent != content || coord.lastIsError != isError else { return }
          coord.lastContent = content
          coord.lastIsError = isError

          let attributed: NSAttributedString
          if isError {
              attributed = NSAttributedString(
                  string: content,
                  attributes: [
                      .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                      .foregroundColor: NSColor.systemRed,
                  ]
              )
          } else {
              attributed = coord.highlighter?.highlight(content, language: "json")
                  ?? NSAttributedString(
                      string: content,
                      attributes: [
                          .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                          .foregroundColor: AtomOneDark.defaultText,
                      ]
                  )
          }

          DispatchQueue.main.async {
              (scrollView.documentView as? NSTextView)?.textStorage?.setAttributedString(attributed)
          }
      }

      class Coordinator {
          var textView: NSTextView?
          var highlighter: SyntaxHighlighter?
          var lastContent: String?
          var lastIsError: Bool?
      }
  }
  ```

- [ ] **Step 2: 将文件加入 Xcode 项目**

  在 Xcode 中：
  - 右键点击 `macos/Sources/Features/Agent/CtrlServer/` 群组
  - 选择 "Add Files to Ghostty..."
  - 选中 `JSONHighlightView.swift`，确保 Target "Ghostty" 已勾选

  或者检查 `project.pbxproj` 是否需要手动添加引用（如果用命令行构建）。

- [ ] **Step 3: 确认编译通过**

  ```bash
  cd macos
  xcodebuild -scheme Ghostty -configuration Debug -destination 'platform=macOS' build 2>&1 | grep -E "error:|Build succeeded"
  ```
  期望输出：`Build succeeded`

- [ ] **Step 4: Commit**

  ```bash
  git add macos/Sources/Features/Agent/CtrlServer/JSONHighlightView.swift
  git add macos/Ghostty.xcodeproj/project.pbxproj
  git commit -m "feat(ctrl-api-monitor): 新增 JSONHighlightView — JSON 语法高亮组件"
  ```

---

## Task 3: 替换 detailSection 内的渲染组件

**Files:**
- Modify: `macos/Sources/Features/Agent/CtrlServer/CtrlAPIMonitorPanel.swift:200-217`

- [ ] **Step 1: 定位 `detailSection` 函数**

  打开 `macos/Sources/Features/Agent/CtrlServer/CtrlAPIMonitorPanel.swift`，找到 `detailSection` 函数（约第 200 行）：

  ```swift
  private func detailSection(title: String, body: String?, isError: Bool) -> some View {
      VStack(alignment: .leading, spacing: 0) {
          Text(title)
              ...
          Divider()
          ScrollView([.horizontal, .vertical]) {
              Text(prettyJSON(body))
                  .font(.system(size: 11, design: .monospaced))
                  .foregroundStyle(isError ? Color.red : Color.primary)
                  .padding(8)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .textSelection(.enabled)
          }
      }
  }
  ```

- [ ] **Step 2: 替换 ScrollView+Text 为 JSONHighlightView**

  将 `ScrollView([.horizontal, .vertical]) { ... }` 整块替换为：

  ```swift
  JSONHighlightView(content: prettyJSON(body), isError: isError)
  ```

  替换后的完整函数：

  ```swift
  private func detailSection(title: String, body: String?, isError: Bool) -> some View {
      VStack(alignment: .leading, spacing: 0) {
          Text(title)
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(isError ? Color.red : Color.secondary)
              .padding(.horizontal, 8)
              .padding(.vertical, 5)
          Divider()
          JSONHighlightView(content: prettyJSON(body), isError: isError)
      }
  }
  ```

- [ ] **Step 3: 确认编译通过**

  ```bash
  cd macos
  xcodebuild -scheme Ghostty -configuration Debug -destination 'platform=macOS' build 2>&1 | grep -E "error:|Build succeeded"
  ```
  期望输出：`Build succeeded`

- [ ] **Step 4: 手动验证**

  启动 App，打开 Ctrl API Monitor，点击任意一条有 Request/Response 的记录，确认：
  - JSON 显示为深色背景 + 语法高亮颜色
  - 内容左对齐
  - 可以选中文字并复制

- [ ] **Step 5: Commit**

  ```bash
  git add macos/Sources/Features/Agent/CtrlServer/CtrlAPIMonitorPanel.swift
  git commit -m "feat(ctrl-api-monitor): detail pane 使用 JSONHighlightView 渲染语法高亮"
  ```

---

## Task 4: 重组 Agent 菜单 — Observability 子菜单

**Files:**
- Modify: `macos/Sources/App/macOS/AppDelegate.swift`

- [ ] **Step 1: 定位现有 Agent 菜单构建代码**

  在 `AppDelegate.swift` 中搜索 `// Agent 菜单`，找到约第 1134 行开始的菜单构建代码。当前结构：

  ```swift
  let agentMenu = NSMenu(title: "Agent")

  let launchAgent = NSMenuItem(title: "Launch Agent", ...)
  agentMenu.addItem(launchAgent)
  agentMenu.addItem(.separator())

  let toggleAgentMonitor = NSMenuItem(title: "Toggle Agent Monitor", ...)
  agentMenu.addItem(toggleAgentMonitor)

  let toggleNotificationCenter = NSMenuItem(title: "Toggle Notification Center", ...)
  agentMenu.addItem(toggleNotificationCenter)

  let jumpToUnread = NSMenuItem(title: "Jump to Highest Priority Unread", ...)
  agentMenu.addItem(jumpToUnread)

  agentMenu.addItem(.separator())

  let agentDashboard = NSMenuItem(title: "Agent Dashboard", ...)
  agentMenu.addItem(agentDashboard)
  ```

- [ ] **Step 2: 替换 Agent 菜单构建代码**

  将 `agentMenu.addItem(launchAgent)` 之后的全部内容替换为（`agentMenu.addItem(launchAgent)` 本行不重复添加，仅作参考位置标记）：

  ```swift
  // agentMenu.addItem(launchAgent)  ← 已存在，不要重复添加

  agentMenu.addItem(.separator())

  // Observability 子菜单
  let observabilityMenu = NSMenu(title: "Observability")

  let agentsInWorkspace = NSMenuItem(
      title: "Agents In Workspace",
      action: #selector(toggleAgentMonitor(_:)),
      keyEquivalent: "m")
  agentsInWorkspace.keyEquivalentModifierMask = [.command, .option]
  observabilityMenu.addItem(agentsInWorkspace)

  let agentDashboard = NSMenuItem(
      title: "Agent Dashboard",
      action: #selector(showAgentDashboard(_:)),
      keyEquivalent: "d")
  agentDashboard.keyEquivalentModifierMask = [.command, .option]
  observabilityMenu.addItem(agentDashboard)

  let notifCenter = NSMenuItem(
      title: "Agent Notification Center",
      action: #selector(toggleNotificationCenter(_:)),
      keyEquivalent: "n")
  notifCenter.keyEquivalentModifierMask = [.command, .option]
  observabilityMenu.addItem(notifCenter)

  observabilityMenu.addItem(.separator())

  let ctrlMonitor = NSMenuItem(
      title: "Controller API Monitor",
      action: #selector(toggleCtrlAPIMonitor(_:)),
      keyEquivalent: "c")
  ctrlMonitor.keyEquivalentModifierMask = [.command, .option]
  observabilityMenu.addItem(ctrlMonitor)

  let observabilityItem = NSMenuItem(title: "Observability", action: nil, keyEquivalent: "")
  observabilityItem.submenu = observabilityMenu
  agentMenu.addItem(observabilityItem)

  agentMenu.addItem(.separator())

  let jumpToUnread = NSMenuItem(
      title: "Jump to Highest Priority Unread",
      action: #selector(jumpToHighestPriorityUnread(_:)),
      keyEquivalent: "u")
  jumpToUnread.keyEquivalentModifierMask = [.command, .option]
  agentMenu.addItem(jumpToUnread)
  ```

- [ ] **Step 3: 新增 `toggleCtrlAPIMonitor` selector**

  在 `AppDelegate.swift` 中找到 `toggleAgentMonitor` 方法附近（约第 1198 行），在其后添加：

  ```swift
  @objc func toggleCtrlAPIMonitor(_ sender: Any?) {
      CtrlAPIStore.shared.isMonitorVisible.toggle()
  }
  ```

- [ ] **Step 4: 确认编译通过**

  ```bash
  cd macos
  xcodebuild -scheme Ghostty -configuration Debug -destination 'platform=macOS' build 2>&1 | grep -E "error:|Build succeeded"
  ```
  期望输出：`Build succeeded`

- [ ] **Step 5: 手动验证菜单结构**

  启动 App，打开菜单栏 **Agent**，确认：
  - 顶层只有：Launch Agent / Observability ▶ / Jump to Highest Priority Unread
  - 悬停 Observability 展开子菜单，包含：Agents In Workspace (⌥⌘M)、Agent Dashboard (⌥⌘D)、Agent Notification Center (⌥⌘N)、分割线、Controller API Monitor (⌥⌘C)
  - 点击 Controller API Monitor 可切换底部面板显示/隐藏

- [ ] **Step 6: Commit**

  ```bash
  git add macos/Sources/App/macOS/AppDelegate.swift
  git commit -m "feat(agent-menu): 新增 Observability 子菜单，整合四个可观测性工具"
  ```

---

## 完成后验证

- [ ] Status bar 不再显示 network 图标按钮
- [ ] Ctrl API Monitor detail pane 显示语法高亮 JSON（深色背景 + 颜色）
- [ ] Agent > Observability 子菜单包含四个工具，快捷键正确
- [ ] ⌥⌘M / ⌥⌘D / ⌥⌘N / ⌥⌘C 均可正常触发对应功能
