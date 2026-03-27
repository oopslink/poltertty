# 文件浏览器 & Git 面板 UX 优化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复文件浏览器和 Git 面板中审查发现的 5 个优先问题和 3 个次要问题，提升操作可发现性、视觉层级清晰度和空状态引导性。

**Architecture:** 6 个独立任务分三个 Phase 执行。Phase 1 三任务并发，Phase 2 串行（依赖 Phase 1 中的 A+C），Phase 3 两任务并发（依赖 Phase 2）。所有修改均为纯视觉/布局层面，不涉及数据逻辑变更。

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, macOS 13+

---

## 文件映射

| 任务 | 文件 | 操作 |
|------|------|------|
| 1A | `macos/Sources/Features/Workspace/UnifiedPanelView.swift` | 修改 |
| 1B | `macos/Sources/Features/Workspace/GitPanel/GitChangesSection.swift` | 修改 |
| 1C | `macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift` | 修改 |
| 2D | `macos/Sources/Features/Workspace/UnifiedPanelView.swift` | 修改 |
| 2D | `macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift` | 修改 |
| 2D | `macos/Sources/Features/Workspace/GitPanel/GitPanelView.swift` | 修改 |
| 3E | `macos/Sources/Features/Workspace/GitPanel/GitChangesSection.swift` | 修改 |
| 3E | `macos/Sources/Features/Workspace/GitPanel/GitCommitsSection.swift` | 修改 |
| 3E | `macos/Sources/Features/Workspace/GitPanel/GitCommitRow.swift` | 修改 |
| 3E | `macos/Sources/Features/Workspace/FileBrowser/FileNodeRow.swift` | 修改 |
| 3F | `macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift` | 修改 |
| 3F | `macos/Sources/Features/Workspace/GitPanel/GitPanelView.swift` | 修改 |

---

## Phase 1：三任务并发（互不干扰）

---

### Task 1A: Tab bar 选中状态强化

**问题：** `PanelTabBar` 中 active tab 背景 `opacity(0.15)` 太淡，图标颜色变化幅度小，无指示条。用户切换面板后无法快速确认当前位置。

**Files:**
- Modify: `macos/Sources/Features/Workspace/UnifiedPanelView.swift`

- [ ] **Step 1: 修改 `tabButton` 方法**

将 `PanelTabBar` 中的 `tabButton(icon:tab:badge:)` 方法替换为以下实现：

```swift
private func tabButton(icon: String, tab: PanelTab, badge: Int?) -> some View {
    Button {
        activePanelTab = tab
    } label: {
        ZStack(alignment: .topTrailing) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(
                    activePanelTab == tab
                        ? Color(nsColor: .controlAccentColor)
                        : .secondary
                )
                .frame(width: 28, height: 28)
                .background(
                    activePanelTab == tab
                        ? Color(nsColor: .controlAccentColor).opacity(0.15)
                        : Color.clear
                )
                .cornerRadius(5)
                .overlay(
                    // 底部 accent 指示条
                    Rectangle()
                        .fill(
                            activePanelTab == tab
                                ? Color(nsColor: .controlAccentColor)
                                : Color.clear
                        )
                        .frame(height: 2),
                    alignment: .bottom
                )

            if let count = badge {
                Text(count > 99 ? "99+" : "\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.orange)
                    .cornerRadius(4)
                    .offset(x: 6, y: -4)
            }
        }
    }
    .buttonStyle(.plain)
    .help(tab == .files ? "Files — 文件浏览器 (F)" : "Git — 版本控制 (G)")
}
```

关键变化：
- icon 颜色 active 时改为 `controlAccentColor`（原为 `.primary`）
- 添加底部 2px 指示条（`Rectangle().fill(accentColor).frame(height: 2)`）
- badge 字体 8pt → 10pt
- 添加 `.help()` 显示标签名和快捷键

- [ ] **Step 2: 构建验证**

```bash
make check
```

预期：零编译错误。

- [ ] **Step 3: 提交**

```bash
git add macos/Sources/Features/Workspace/UnifiedPanelView.swift
git commit -m "fix(ui): strengthen tab bar active state with accent color and indicator line"
```

---

### Task 1B: Stage/Unstage 按钮可见性 + 代码清理

**问题：** `GitChangesSection.changeRow` 中的 stage/unstage/discard 按钮颜色固定为 `.secondary`，非 hover 时几乎不可见。`xmark.circle` 图标被用户误解为"删除文件"。代码中存在无意义的 `if true {` 条件。

**Files:**
- Modify: `macos/Sources/Features/Workspace/GitPanel/GitChangesSection.swift`

- [ ] **Step 1: 替换 `changeRow` 方法中的按钮部分**

找到 `changeRow(_ change: GitChange, isStaged: Bool)` 方法，将整个 `HStack` 内容替换如下：

```swift
@ViewBuilder
private func changeRow(_ change: GitChange, isStaged: Bool) -> some View {
    let isHovered = hoveredChangeId == change.id

    HStack(spacing: 4) {
        Text(change.delta.symbol)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(Color(hex: change.delta.colorHex) ?? .secondary)
            .frame(width: 14)

        Text(URL(fileURLWithPath: change.path).lastPathComponent)
            .font(.system(size: 11))
            .lineLimit(1)
            .truncationMode(.middle)

        Spacer()

        // Stage / Unstage / Discard 操作按钮
        // 非 hover 时极淡（0.3 opacity），hover 时显现，表达可操作性
        if isStaged {
            Button(action: { Task { await vm.unstage(change) } }) {
                Image(systemName: "minus.circle")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(isHovered ? .secondary : .secondary.opacity(0.3))
            .help("Unstage — 从下次提交中移除")
            .accessibilityLabel("Unstage \(URL(fileURLWithPath: change.path).lastPathComponent)")
        } else {
            Button(action: { Task { await vm.stage(change) } }) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(isHovered ? Color.green.opacity(0.85) : .secondary.opacity(0.3))
            .help("Stage — 添加到下次提交")
            .accessibilityLabel("Stage \(URL(fileURLWithPath: change.path).lastPathComponent)")

            Button(action: { discardConfirm = change }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(isHovered ? Color.orange.opacity(0.85) : .secondary.opacity(0.3))
            .help("Discard Changes — 不可撤销")
            .accessibilityLabel("Discard changes to \(URL(fileURLWithPath: change.path).lastPathComponent)")
        }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
    .contentShape(Rectangle())
    .cornerRadius(3)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(change.delta.symbol) \(URL(fileURLWithPath: change.path).lastPathComponent)")
    .onHover { hovering in
        hoveredChangeId = hovering ? change.id : nil
    }
    .onTapGesture {
        Task { await vm.selectWorkingFile(change) }
    }
}
```

关键变化：
- 删除 `if true {` 包装器
- 非 hover 时 opacity 0.3（原为 `.secondary` 约 0.5，视觉上差异不足）
- hover 时 stage 变绿、discard 变橙，语义明确
- `xmark.circle` 改为 `arrow.uturn.backward`（Discard 语义更准确）
- help 文字改为中文说明，消除歧义

- [ ] **Step 2: 构建验证**

```bash
make check
```

预期：零编译错误。

- [ ] **Step 3: 提交**

```bash
git add macos/Sources/Features/Workspace/GitPanel/GitChangesSection.swift
git commit -m "fix(ui): improve stage/unstage button discoverability and clean up dead code"
```

---

### Task 1C: 双 Divider 修复 + 状态栏颜色

**问题：** `FileBrowserPanel.panelContent` 在有面包屑时出现两条紧挨的 Divider（第 91 行 + 第 94 行），视觉上变成加粗分割线。`rootPathStatusBar` 的文字 opacity 0.6 在深色模式下过淡。

**Files:**
- Modify: `macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift`

- [ ] **Step 1: 修复 `panelContent` 中的双 Divider**

找到 `panelContent` 的左侧 `VStack`，将以下代码：

```swift
// 原代码（约第 87-101 行）
VStack(spacing: 0) {
    filterBar
    if !viewModel.breadcrumbSegments.isEmpty {
        BreadcrumbView(segments: viewModel.breadcrumbSegments) { segment in
            viewModel.focusDirectory(segment.url)
        }
        Divider()
    }
    Divider()
    if viewModel.rootDir.isEmpty || !FileManager.default.fileExists(atPath: viewModel.rootDir) {
        emptyStateView
    } else {
        treeScrollView
    }
    Divider()
    rootPathStatusBar
}
```

替换为：

```swift
VStack(spacing: 0) {
    filterBar
    Divider()
    if !viewModel.breadcrumbSegments.isEmpty {
        BreadcrumbView(segments: viewModel.breadcrumbSegments) { segment in
            viewModel.focusDirectory(segment.url)
        }
        Divider()
    }
    if viewModel.rootDir.isEmpty || !FileManager.default.fileExists(atPath: viewModel.rootDir) {
        emptyStateView
    } else {
        treeScrollView
    }
    Divider()
    rootPathStatusBar
}
```

变化：将第一个 Divider 移至 `filterBar` 之后（始终存在），删除 breadcrumb if 块内的 Divider → 有面包屑时变为 filterBar | BreadcrumbView | tree，无面包屑时变为 filterBar | tree，两种情况各只有一条分割线。

- [ ] **Step 2: 修复 `rootPathStatusBar` 的 opacity**

找到 `rootPathStatusBar` 计算属性，将两处 `.opacity(0.6)` 改为 `.opacity(0.8)`：

```swift
private var rootPathStatusBar: some View {
    HStack(spacing: 4) {
        Image(systemName: "folder")
            .font(.system(size: 9))
            .foregroundColor(.secondary.opacity(0.8))   // 原 0.6
        Text(viewModel.effectiveRootDir)
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.secondary.opacity(0.8))   // 原 0.6
            .lineLimit(1)
            .truncationMode(.head)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .frame(maxWidth: .infinity, alignment: .leading)
}
```

- [ ] **Step 3: 构建验证**

```bash
make check
```

预期：零编译错误。

- [ ] **Step 4: 提交**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift
git commit -m "fix(ui): remove duplicate divider and improve status bar readability"
```

---

## Phase 2：串行（依赖 1A + 1C 完成）

---

### Task 2D: Worktree Selector 提升为共享组件

**问题：** `FileBrowserPanel.filterBar` 和 `GitPanelView.worktreeToolbar` 各自维护一个 worktree selector，样式不一致，用户看到两处相同控件时不明白区别。切换逻辑实际上是同一个（都调用 `fileBrowserVM.switchRoot`），只是显示在两个地方。

**解决方案：** 将 selector 提升到 `UnifiedPanelView.PanelTabBar`，两个 tab 共享同一个控件，从各自面板中删除。

**Files:**
- Modify: `macos/Sources/Features/Workspace/UnifiedPanelView.swift`
- Modify: `macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift`
- Modify: `macos/Sources/Features/Workspace/GitPanel/GitPanelView.swift`

- [ ] **Step 1: 给 `PanelTabBar` 添加 `worktreeMonitor` 属性**

在 `PanelTabBar` struct 定义中添加一个属性：

```swift
private struct PanelTabBar: View {
    @Binding var activePanelTab: PanelTab
    @ObservedObject var gitPanelVM: GitPanelViewModel
    @ObservedObject var fileBrowserVM: FileBrowserViewModel
    var worktreeMonitor: GitWorktreeMonitor? = nil   // 新增

    // ...
}
```

- [ ] **Step 2: 在 `PanelTabBar.body` 中插入 worktree selector**

将 `PanelTabBar.body` 替换为：

```swift
var body: some View {
    HStack(spacing: 0) {
        tabButton(icon: "folder", tab: .files, badge: nil)
        tabButton(icon: "arrow.triangle.branch", tab: .git,
                  badge: gitPanelVM.changedCount > 0 ? gitPanelVM.changedCount : nil)

        // 共享 Worktree Selector
        if let monitor = worktreeMonitor, !monitor.worktrees.isEmpty {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1, height: 14)
                .padding(.horizontal, 4)
            worktreeSelector(monitor: monitor)
        }

        Spacer()

        // Help button
        Button {
            fileBrowserVM.showShortcutHelp.toggle()
        } label: {
            Image(systemName: "questionmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help("Keyboard Shortcuts (?)")
        .popover(isPresented: $fileBrowserVM.showShortcutHelp, arrowEdge: .trailing) {
            ShortcutHelpView()
        }

        // Close panel button
        Button {
            fileBrowserVM.isVisible = false
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help("Close Panel")
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 3)
    .background(Color(nsColor: .windowBackgroundColor))
}
```

- [ ] **Step 3: 在 `PanelTabBar` 中添加 `worktreeSelector` 私有方法**

在 `PanelTabBar` 的 `tabButton` 方法之后添加：

```swift
@ViewBuilder
private func worktreeSelector(monitor: GitWorktreeMonitor) -> some View {
    let effectivePath = fileBrowserVM.effectiveRootDir
    let worktrees = monitor.worktrees
    let currentWT = worktrees.first {
        URL(fileURLWithPath: $0.path).standardized.path
            == URL(fileURLWithPath: effectivePath).standardized.path
    }
    let branchLabel = gitPanelVM.branch
        ?? currentWT.map { wt -> String in
            if wt.isMain { return "Main" }
            return wt.branch ?? URL(fileURLWithPath: wt.path).lastPathComponent
        }
        ?? URL(fileURLWithPath: effectivePath).lastPathComponent

    if worktrees.count > 1 {
        Menu {
            ForEach(worktrees) { wt in
                let isActive = URL(fileURLWithPath: wt.path).standardized.path
                    == URL(fileURLWithPath: effectivePath).standardized.path
                Button {
                    if wt.isMain {
                        fileBrowserVM.switchRoot(to: nil)
                    } else {
                        fileBrowserVM.switchRoot(to: wt.path)
                    }
                } label: {
                    Label {
                        Text(wt.isMain ? "Main" : (wt.branch ?? wt.path))
                    } icon: {
                        if isActive { Image(systemName: "checkmark") }
                    }
                }
                .disabled(isActive)
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10))
                Text(branchLabel)
                    .font(.system(size: 11))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Switch Worktree")
    } else {
        HStack(spacing: 2) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10))
            Text(branchLabel)
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .foregroundColor(.secondary)
    }
}
```

- [ ] **Step 4: 在 `UnifiedPanelView` 中将 `worktreeMonitor` 传给 `PanelTabBar`**

找到 `UnifiedPanelView.body` 中创建 `PanelTabBar` 的调用，添加 `worktreeMonitor` 参数：

```swift
PanelTabBar(
    activePanelTab: $activePanelTab,
    gitPanelVM: gitPanelVM,
    fileBrowserVM: fileBrowserVM,
    worktreeMonitor: worktreeMonitor   // 新增
)
```

- [ ] **Step 5: 从 `FileBrowserPanel` 中删除 worktree selector**

在 `FileBrowserPanel.swift` 中：

**5a.** 删除 `worktreeMonitor` 属性（第 8 行附近）：
```swift
// 删除这一行：
var worktreeMonitor: GitWorktreeMonitor? = nil
```

**5b.** 修改 `filterBar`，删除 `worktreeSelector` 相关内容。

原 `filterBar` 的 HStack 开头：
```swift
HStack(spacing: 6) {
    worktreeSelector           // 删除这一行
    Image(systemName: "magnifyingglass")
    // ...
}
```
以及 worktreeSelector 之后的分隔线（即 `Rectangle().fill(...).frame(width: 1, height: 12)`，原先由 worktreeSelector 内部在单 worktree 时渲染）也一并删除。

注意：`filterBar` 中可能有 `if worktrees.count > 1` 或类似的分支包裹 worktreeSelector；连同整个 worktreeSelector 调用块一起删除即可。

**5c.** 删除 `worktreeSelector` 计算属性（约第 485-551 行，`@ViewBuilder private var worktreeSelector: some View { ... }`）：完整删除这个属性。

**5d.** 更新 `UnifiedPanelView` 中调用 `FileBrowserPanel` 时不再传 `worktreeMonitor`：

```swift
FileBrowserPanel(
    viewModel: fileBrowserVM,
    onOpenInTerminal: onOpenInTerminal,
    // worktreeMonitor: worktreeMonitor,  ← 删除此行
    onSwitchToGitTab: { ... }
)
```

- [ ] **Step 6: 从 `GitPanelView` 中删除 worktreeToolbar**

在 `GitPanelView.swift` 中：

**6a.** 删除 `worktreeMonitor` 属性（第 7 行附近）：
```swift
// 删除这一行：
var worktreeMonitor: GitWorktreeMonitor?
```

**6b.** 在 `gitPanelContent` 的左侧 `VStack` 中，删除 `worktreeToolbar` 和紧随其后的 `Divider()`：

```swift
// 删除这两行：
worktreeToolbar
Divider()
```

**6c.** 删除 `worktreeToolbar` 计算属性（约第 88-150 行，`private var worktreeToolbar: some View { ... }`）：完整删除。

**6d.** 删除 `worktreeDisplayLabel(for:fallback:)` 辅助方法（约第 152-156 行）：完整删除。

**6e.** 更新 `UnifiedPanelView` 中调用 `GitPanelView` 时不再传 `worktreeMonitor`：

```swift
GitPanelView(
    vm: gitPanelVM,
    fileBrowserVM: fileBrowserVM,
    // worktreeMonitor: worktreeMonitor,  ← 删除此行
    onSwitchToFilesTab: { activePanelTab = .files }
)
```

- [ ] **Step 7: 构建验证**

```bash
make check
```

预期：零编译错误。若提示 `worktreeMonitor` 引用残留，检查 Step 5/6 是否完整删除。

- [ ] **Step 8: 提交**

```bash
git add macos/Sources/Features/Workspace/UnifiedPanelView.swift \
        macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift \
        macos/Sources/Features/Workspace/GitPanel/GitPanelView.swift
git commit -m "refactor(ui): consolidate worktree selector into shared tab bar"
```

---

## Phase 3：两任务并发（依赖 Phase 2 完成）

---

### Task 3E: 字体尺寸统一

**问题：** 界面中存在 8pt、9pt 两种过小字号，在普通 DPI 屏幕几乎不可读。应统一为最小 10pt。

**目标字号层级：**
- Section header（全大写标签）：10pt semibold（保持现状）
- 正文内容（文件名、提交信息）：11pt（保持现状）
- 辅助信息（路径、日期、badge 计数）：10pt（从 8pt/9pt 提升）

**Files:**
- Modify: `macos/Sources/Features/Workspace/GitPanel/GitChangesSection.swift`
- Modify: `macos/Sources/Features/Workspace/GitPanel/GitCommitsSection.swift`
- Modify: `macos/Sources/Features/Workspace/GitPanel/GitCommitRow.swift`
- Modify: `macos/Sources/Features/Workspace/FileBrowser/FileNodeRow.swift`

- [ ] **Step 1: `GitChangesSection.swift` — subsectionHeader badge 9pt → 10pt**

找到 `subsectionHeader` 方法中的 count badge：

```swift
// 原代码：
Text("\(count)")
    .font(.system(size: 9, weight: .medium, design: .monospaced))

// 改为：
Text("\(count)")
    .font(.system(size: 10, weight: .medium, design: .monospaced))
```

- [ ] **Step 2: `GitCommitsSection.swift` — commits badge 9pt → 10pt**

找到 `GitCommitsSection.body` 中的 count badge：

```swift
// 原代码：
Text("\(vm.commits.count)")
    .font(.system(size: 9, weight: .medium, design: .monospaced))

// 改为：
Text("\(vm.commits.count)")
    .font(.system(size: 10, weight: .medium, design: .monospaced))
```

- [ ] **Step 3: `GitCommitRow.swift` — chevron 8pt → 9pt，file chevron 8pt → 9pt**

找到 commit header 的 chevron：

```swift
// 原代码：
Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
    .font(.system(size: 8, weight: .medium))

// 改为：
Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
    .font(.system(size: 9, weight: .medium))
```

找到 expanded file list 中的 chevron：

```swift
// 原代码：
Image(systemName: "chevron.right")
    .font(.system(size: 8))

// 改为：
Image(systemName: "chevron.right")
    .font(.system(size: 9))
```

- [ ] **Step 4: `FileNodeRow.swift` — git status badge 9pt → 10pt**

找到 `FileNodeRow.body` 中的 git status badge：

```swift
// 原代码：
Text(status.symbol)
    .font(.system(size: 9, weight: .medium))

// 改为：
Text(status.symbol)
    .font(.system(size: 10, weight: .medium))
```

- [ ] **Step 5: 构建验证**

```bash
make check
```

预期：零编译错误。

- [ ] **Step 6: 提交**

```bash
git add macos/Sources/Features/Workspace/GitPanel/GitChangesSection.swift \
        macos/Sources/Features/Workspace/GitPanel/GitCommitsSection.swift \
        macos/Sources/Features/Workspace/GitPanel/GitCommitRow.swift \
        macos/Sources/Features/Workspace/FileBrowser/FileNodeRow.swift
git commit -m "fix(ui): raise minimum font size to 10pt, eliminate 8pt and 9pt usages"
```

---

### Task 3F: 空状态优化

**问题：** 文件浏览器和 Git 面板的空状态只显示"终态文字"，用户不知道下一步该做什么。

**Files:**
- Modify: `macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift`
- Modify: `macos/Sources/Features/Workspace/GitPanel/GitPanelView.swift`

- [ ] **Step 1: 替换 `FileBrowserPanel.emptyStateView`**

找到 `emptyStateView` 计算属性，替换为：

```swift
private var emptyStateView: some View {
    VStack(spacing: 0) {
        Spacer()
        Image(systemName: "folder")
            .font(.system(size: 24))
            .foregroundColor(Color.secondary.opacity(0.4))
        Text(viewModel.effectiveRootDir.isEmpty ? "No directory set" : "Directory not found")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .padding(.top, 8)
        Text(
            viewModel.effectiveRootDir.isEmpty
                ? "在工作区设置中配置根目录后即可浏览文件。"
                : "配置的目录在磁盘上不存在，请检查工作区设置。"
        )
        .font(.system(size: 11))
        .foregroundColor(.secondary.opacity(0.7))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        Spacer()
    }
    .frame(maxWidth: .infinity)
}
```

- [ ] **Step 2: 替换 `GitPanelView` 的非 git repo 空状态**

找到 `gitPanelContent` 中的 `if !vm.isGitRepo` 分支，将其内容替换为：

```swift
VStack(spacing: 0) {
    Spacer()
    Image(systemName: "arrow.triangle.branch")
        .font(.system(size: 32))
        .foregroundColor(.secondary.opacity(0.5))
    Text("Not a git repository")
        .font(.system(size: 13))
        .foregroundColor(.secondary)
        .padding(.top, 8)
    if !vm.lastAttemptedDir.isEmpty {
        Text(vm.lastAttemptedDir.replacingOccurrences(
            of: NSHomeDirectory(), with: "~"))
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.secondary.opacity(0.7))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.top, 4)
    }
    Text("在终端中运行 `git init` 初始化仓库，\n或打开一个已有 git 仓库的目录。")
        .font(.system(size: 11))
        .foregroundColor(.secondary.opacity(0.7))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    Spacer()
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
```

- [ ] **Step 3: 构建验证**

```bash
make check
```

预期：零编译错误。

- [ ] **Step 4: 提交**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift \
        macos/Sources/Features/Workspace/GitPanel/GitPanelView.swift
git commit -m "fix(ux): add helpful guidance text to empty states"
```

---

## 全部完成后验证

- [ ] **完整构建**

```bash
make dev
```

预期：构建成功，无警告和错误。

- [ ] **人工检查清单**

1. **Tab bar**：切换 Files/Git 时，active tab 有明显底部指示条 + accent 色图标；hover 时有 tooltip 显示快捷键
2. **Stage 按钮**：hover 到 git 变更行时，stage 按钮变绿、discard 按钮变橙；非 hover 时极淡但仍存在
3. **Divider**：有面包屑时 filterBar 下方只有一条分隔线；状态栏路径文字清晰可读
4. **Worktree selector**：只出现在顶部 tab bar 一处；切换 worktree 后两个面板均响应
5. **字体**：各处 badge 计数最小为 10pt
6. **空状态**：无目录时显示中文引导文字；非 git 仓库时显示 git init 提示

---

## 自检

**Spec 覆盖确认：**
- [x] P1: Tab bar 选中状态 → Task 1A
- [x] P1: Stage/unstage 按钮可见性 → Task 1B
- [x] Minor: 双 Divider + opacity → Task 1C
- [x] P2: Worktree Selector 重复 → Task 2D
- [x] P2: 字体系统 → Task 3E
- [x] P3: 空状态无引导 → Task 3F

**Placeholder 扫描：** 无 TBD/TODO/类似表述，所有 Step 均含完整代码。

**类型一致性：** `GitWorktreeMonitor`、`fileBrowserVM.switchRoot(to:)`、`gitPanelVM.branch` 均为现有 API，无新增类型。
