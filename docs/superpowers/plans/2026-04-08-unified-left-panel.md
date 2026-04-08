# Unified Left Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 LazyGit 从浮动 Popup 迁移为左侧侧边栏，与 Yazi 文件浏览器共享同一面板位置，互斥显示，统一工具栏。

**Architecture:** 扩展现有 Yazi 面板，新增 `LeftPanelTool` 枚举（`.yazi` / `.lazygit`）控制面板内容切换。新建 `LazyGitSurfaceStore` 管理 LazyGit 进程生命周期。`YaziPanelToolbar` 改造为 `LeftPanelToolbar`，顶部加 Tab 指示，`YaziPanelView` 改造为 `LeftPanelView` 条件渲染两种工具。

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, Ghostty.SurfaceView, NotificationCenter

**Spec:** `docs/superpowers/specs/2026-04-08-unified-left-panel-design.md`

---

## 文件变更清单

| 操作 | 文件 |
|------|------|
| 新建 | `macos/Sources/Features/Workspace/LazyGit/LazyGitSurfaceStore.swift` |
| 修改 | `macos/Sources/Features/Workspace/Yazi/YaziPanelToolbar.swift` → struct 改为 `LeftPanelToolbar` |
| 修改 | `macos/Sources/Features/Workspace/Yazi/YaziPanelView.swift` → struct 改为 `LeftPanelView` |
| 修改 | `macos/Sources/Features/Workspace/PolterttyRootView.swift` |
| 修改 | `macos/Sources/Features/Workspace/WorkspaceModel.swift` |
| 修改 | `macos/Sources/Features/Workspace/WorkspaceManager.swift` |
| 修改 | `macos/Sources/Features/PopupOverlay/PopupOverlayManager.swift` |
| 修改 | `macos/Sources/App/macOS/AppDelegate.swift` |
| 修改 | `macos/Sources/Features/Terminal/TerminalController.swift` |
| 修改 | `macos/Sources/Features/Keyboard Shortcuts/KeyboardShortcutsPanelView.swift` |

---

## Task 1: 创建开发 worktree

**Files:**
- N/A (git 操作)

- [ ] **Step 1: 创建 worktree**

```bash
git worktree add .worktrees/unified-left-panel -b feat/unified-left-panel
cd .worktrees/unified-left-panel
```

- [ ] **Step 2: 确认 worktree 就绪**

```bash
git branch
# 预期：* feat/unified-left-panel
```

---

## Task 2: 创建 LazyGitSurfaceStore

**Files:**
- Create: `macos/Sources/Features/Workspace/LazyGit/LazyGitSurfaceStore.swift`

- [ ] **Step 1: 创建目录并写入文件**

```bash
mkdir -p macos/Sources/Features/Workspace/LazyGit
```

创建 `macos/Sources/Features/Workspace/LazyGit/LazyGitSurfaceStore.swift`：

```swift
// macos/Sources/Features/Workspace/LazyGit/LazyGitSurfaceStore.swift
import Foundation

/// Manages one lazygit terminal surface per workspace.
/// Surfaces are lazily created on first panel open and kept alive
/// until the workspace is deleted or the process exits.
class LazyGitSurfaceStore: ObservableObject {
    @Published private(set) var surfaces: [UUID: Ghostty.SurfaceView] = [:]
    private var exitObservers: [UUID: any NSObjectProtocol] = [:]

    // MARK: - Surface management

    /// Get or create the lazygit surface for a workspace.
    @MainActor
    func surface(for workspaceId: UUID, ghostty: Ghostty.App, rootDir: String) -> Ghostty.SurfaceView? {
        if let existing = surfaces[workspaceId] {
            return existing
        }

        guard let app = ghostty.app else { return nil }

        var config = Ghostty.SurfaceConfiguration()
        config.command = BundledTool.lazygitPath
        config.workingDirectory = rootDir
        config.environmentVariables = ["PATH": BundledTool.pathWithBundledBin]

        let surface = Ghostty.SurfaceView(app, baseConfig: config)
        surfaces[workspaceId] = surface
        observeExit(surface: surface, workspaceId: workspaceId)
        return surface
    }

    /// Remove and destroy the lazygit surface for a workspace.
    func removeSurface(for workspaceId: UUID) {
        if let token = exitObservers.removeValue(forKey: workspaceId) {
            NotificationCenter.default.removeObserver(token)
        }
        surfaces.removeValue(forKey: workspaceId)
    }

    func hasSurface(for workspaceId: UUID) -> Bool {
        surfaces[workspaceId] != nil
    }

    // MARK: - Exit observation

    private func observeExit(surface: Ghostty.SurfaceView, workspaceId: UUID) {
        let token = NotificationCenter.default.addObserver(
            forName: Ghostty.Notification.ghosttyCloseSurface,
            object: surface,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let processAlive = notification.userInfo?["process_alive"] as? Bool ?? false
            guard !processAlive else { return }
            if let token = self.exitObservers.removeValue(forKey: workspaceId) {
                NotificationCenter.default.removeObserver(token)
            }
            self.surfaces.removeValue(forKey: workspaceId)
        }
        exitObservers[workspaceId] = token
    }
}
```

- [ ] **Step 2: 确认文件存在**

```bash
ls macos/Sources/Features/Workspace/LazyGit/
# 预期：LazyGitSurfaceStore.swift
```

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/LazyGit/LazyGitSurfaceStore.swift
git commit -m "feat: add LazyGitSurfaceStore for per-workspace lazygit session management"
```

---

## Task 3: 更新 YaziPanelToolbar → LeftPanelToolbar

**Files:**
- Modify: `macos/Sources/Features/Workspace/Yazi/YaziPanelToolbar.swift`

新增 `LeftPanelTool` 枚举，将 `YaziPanelToolbar` 改为 `LeftPanelToolbar`，加入 Tab 按钮，Yazi 专属按钮按 tool 条件显示。

- [ ] **Step 1: 全量替换 YaziPanelToolbar.swift**

```swift
// macos/Sources/Features/Workspace/Yazi/YaziPanelToolbar.swift
import SwiftUI

enum LeftPanelTool: String, Equatable {
    case yazi
    case lazygit
}

struct LeftPanelToolbar: View {
    @ObservedObject var yaziStore: YaziSurfaceStore
    var workspaceId: UUID?
    var worktreeMonitor: GitWorktreeMonitor?
    var currentRootDir: String
    var isExpanded: Bool = false
    var currentTool: LeftPanelTool
    var onSwitchTool: (LeftPanelTool) -> Void
    var onToggleExpand: () -> Void = {}
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Tool tabs: File Browser | Git
            toolTabButton(tool: .yazi, icon: "folder", help: "File Browser (⌥⌘F)")
            toolTabButton(tool: .lazygit, icon: "arrow.triangle.branch", help: "Git (⌥⌘G)")

            // Worktree selector (shared for both tools)
            if let monitor = worktreeMonitor, !monitor.worktrees.isEmpty {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1, height: 14)
                    .padding(.horizontal, 4)
                worktreeSelector(monitor: monitor)
            }

            Spacer()

            // Expand / collapse button (both tools)
            Button {
                onToggleExpand()
            } label: {
                Image(systemName: isExpanded
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11))
                    .foregroundStyle(isExpanded ? Color(nsColor: .controlAccentColor) : .secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse Panel (⌥⌘O)" : "Expand to Full Width (⌥⌘O)")
            .keyboardShortcut("o", modifiers: [.option, .command])

            // Layout ratio cycle button (Yazi only)
            if currentTool == .yazi {
                Button {
                    if let wsId = workspaceId {
                        yaziStore.cycleRatio(for: wsId)
                    }
                } label: {
                    Image(systemName: layoutIcon)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(layoutHelp + " (⌥⌘L)")
                .keyboardShortcut("l", modifiers: [.option, .command])
            }

            // Close panel button
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Close Panel")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func toolTabButton(tool: LeftPanelTool, icon: String, help: String) -> some View {
        let isActive = currentTool == tool
        Button {
            onSwitchTool(tool)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(isActive ? Color(nsColor: .controlAccentColor) : .secondary)
                .frame(width: 28, height: 28)
                .background(isActive ? Color(nsColor: .controlAccentColor).opacity(0.15) : Color.clear)
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var layoutIcon: String {
        guard let wsId = workspaceId else { return "rectangle.split.2x1" }
        let label = yaziStore.ratioLabel(for: wsId)
        return label == "Preview" ? "rectangle.split.2x1" : "rectangle"
    }

    private var layoutHelp: String {
        guard let wsId = workspaceId else { return "Cycle Layout" }
        let current = yaziStore.ratioLabel(for: wsId)
        let presets = YaziSurfaceStore.ratioPresets
        let currentIdx = presets.firstIndex(where: { $0.label == current }) ?? 0
        let next = presets[(currentIdx + 1) % presets.count].label
        return "Layout: \(current) → \(next)"
    }

    @ViewBuilder
    private func worktreeSelector(monitor: GitWorktreeMonitor) -> some View {
        let effectivePath = URL(fileURLWithPath: currentRootDir).standardized.path
        let worktrees = monitor.worktrees
        let currentWTPath = worktrees.first {
            URL(fileURLWithPath: $0.path).standardized.path == effectivePath
        }?.path

        let branchLabel: String = {
            guard let path = currentWTPath,
                  let wt = worktrees.first(where: { $0.path == path }) else {
                return URL(fileURLWithPath: currentRootDir).lastPathComponent
            }
            if wt.isMain { return "Main" }
            return wt.branch ?? URL(fileURLWithPath: wt.path).lastPathComponent
        }()

        if worktrees.count > 1 {
            Menu {
                ForEach(worktrees) { wt in
                    let isActive = wt.path == currentWTPath
                    Button {
                        let targetPath = wt.isMain
                            ? (worktrees.first(where: { $0.isMain })?.path ?? currentRootDir)
                            : wt.path
                        if let wsId = workspaceId {
                            yaziStore.cdToDirectory(wsId, path: targetPath)
                        }
                    } label: {
                        Label {
                            Text(wt.isMain ? "Main" : (wt.branch ?? URL(fileURLWithPath: wt.path).lastPathComponent))
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
                .foregroundStyle(.secondary)
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
            .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add macos/Sources/Features/Workspace/Yazi/YaziPanelToolbar.swift
git commit -m "feat: rename YaziPanelToolbar to LeftPanelToolbar, add tool tab buttons"
```

---

## Task 4: 更新 YaziPanelView → LeftPanelView

**Files:**
- Modify: `macos/Sources/Features/Workspace/Yazi/YaziPanelView.swift`

- [ ] **Step 1: 全量替换 YaziPanelView.swift**

```swift
// macos/Sources/Features/Workspace/Yazi/YaziPanelView.swift
import SwiftUI

struct LeftPanelView: View {
    let workspaceId: UUID?
    let ghostty: Ghostty.App
    @ObservedObject var yaziStore: YaziSurfaceStore
    @ObservedObject var lazygitStore: LazyGitSurfaceStore
    var rootDir: String
    var worktreeMonitor: GitWorktreeMonitor?
    var isExpanded: Bool = false
    var currentTool: LeftPanelTool
    var onSwitchTool: (LeftPanelTool) -> Void
    var onToggleExpand: () -> Void = {}
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LeftPanelToolbar(
                yaziStore: yaziStore,
                workspaceId: workspaceId,
                worktreeMonitor: worktreeMonitor,
                currentRootDir: rootDir,
                isExpanded: isExpanded,
                currentTool: currentTool,
                onSwitchTool: onSwitchTool,
                onToggleExpand: onToggleExpand,
                onClose: onClose
            )
            Divider()

            switch currentTool {
            case .yazi:
                yaziContent
            case .lazygit:
                lazygitContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var yaziContent: some View {
        if let wsId = workspaceId,
           let surface = yaziStore.surface(for: wsId, ghostty: ghostty, rootDir: rootDir) {
            Ghostty.SurfaceWrapper(surfaceView: surface)
                .environmentObject(ghostty)
                .id(ObjectIdentifier(surface))
        } else {
            emptyView(icon: "folder", label: "No workspace selected")
        }
    }

    @ViewBuilder
    private var lazygitContent: some View {
        if let wsId = workspaceId,
           let surface = lazygitStore.surface(for: wsId, ghostty: ghostty, rootDir: rootDir) {
            Ghostty.SurfaceWrapper(surfaceView: surface)
                .environmentObject(ghostty)
                .id(ObjectIdentifier(surface))
        } else {
            emptyView(icon: "arrow.triangle.branch", label: "No workspace selected")
        }
    }

    private func emptyView(icon: String, label: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.4))
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add macos/Sources/Features/Workspace/Yazi/YaziPanelView.swift
git commit -m "feat: rename YaziPanelView to LeftPanelView, add conditional lazygit rendering"
```

---

## Task 5: 更新 WorkspaceModel（添加 leftPanelTool）

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceModel.swift`

- [ ] **Step 1: 添加 `leftPanelTool` 字段**

在 `WorkspaceModel` struct 的 `var panelVisible: Bool = false` 前添加：

找到文件中：
```swift
    var panelVisible: Bool = false
    var panelWidth: CGFloat = 260
```

改为：
```swift
    var panelVisible: Bool = false
    var panelWidth: CGFloat = 260
    var leftPanelTool: String = "yazi"
```

- [ ] **Step 2: 添加 CodingKey**

找到：
```swift
        case panelVisible = "fileBrowserVisible"
        case panelWidth = "fileBrowserWidth"
```

改为：
```swift
        case panelVisible = "fileBrowserVisible"
        case panelWidth = "fileBrowserWidth"
        case leftPanelTool = "leftPanelTool"
```

- [ ] **Step 3: 添加 init(from:) 解码**

找到：
```swift
        panelWidth = try container.decodeIfPresent(CGFloat.self, forKey: .panelWidth) ?? 260
```

在其后添加：
```swift
        leftPanelTool = try container.decodeIfPresent(String.self, forKey: .leftPanelTool) ?? "yazi"
```

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceModel.swift
git commit -m "feat: add leftPanelTool field to WorkspaceModel for persistence"
```

---

## Task 6: 更新 WorkspaceManager（添加 lazygitSurfaceStore）

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceManager.swift`

- [ ] **Step 1: 添加 lazygitSurfaceStore 属性**

找到：
```swift
    /// PolterttyRootView 创建 yazi store 后注入此引用（用于 delete 时清理 surface）
    weak var yaziSurfaceStore: YaziSurfaceStore?
```

在其后添加：
```swift
    /// PolterttyRootView 创建 lazygit store 后注入此引用（用于 delete 时清理 surface）
    weak var lazygitSurfaceStore: LazyGitSurfaceStore?
```

- [ ] **Step 2: 在 destroyAllTemporary 中添加清理**

找到：
```swift
        for id in tempIds {
            activeWindows.removeValue(forKey: id)
            yaziSurfaceStore?.removeSurface(for: id)
        }
```

改为：
```swift
        for id in tempIds {
            activeWindows.removeValue(forKey: id)
            yaziSurfaceStore?.removeSurface(for: id)
            lazygitSurfaceStore?.removeSurface(for: id)
        }
```

- [ ] **Step 3: 在 delete 中添加清理**

找到：
```swift
        yaziSurfaceStore?.removeSurface(for: id)
```

在其后添加：
```swift
        lazygitSurfaceStore?.removeSurface(for: id)
```

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceManager.swift
git commit -m "feat: add lazygitSurfaceStore to WorkspaceManager for lifecycle cleanup"
```

---

## Task 7: 更新 PolterttyRootView

**Files:**
- Modify: `macos/Sources/Features/Workspace/PolterttyRootView.swift`

- [ ] **Step 1: 添加 .toggleGitPanel 通知名和 lazygitStore 状态**

找到：
```swift
    static let toggleFileBrowser = Notification.Name("poltertty.toggleFileBrowser")
```

在其后添加：
```swift
    static let toggleGitPanel = Notification.Name("poltertty.toggleGitPanel")
```

找到：
```swift
    @StateObject private var yaziStore = YaziSurfaceStore()
    @State private var panelVisible: Bool = false
    @State private var panelExpanded: Bool = false
    @State private var yaziPanelWidth: CGFloat = 260
    @GestureState private var panelWidthDelta: CGFloat = 0
```

改为：
```swift
    @StateObject private var yaziStore = YaziSurfaceStore()
    @StateObject private var lazygitStore = LazyGitSurfaceStore()
    @State private var panelVisible: Bool = false
    @State private var panelExpanded: Bool = false
    @State private var leftPanelTool: LeftPanelTool = .yazi
    @State private var yaziPanelWidth: CGFloat = 260
    @GestureState private var panelWidthDelta: CGFloat = 0
```

- [ ] **Step 2: 更新 onAppear 恢复 leftPanelTool 并注入 lazygitStore**

找到：
```swift
        .onAppear {
            startupMode = initialStartupMode
            if let wsId = workspaceId, let ws = WorkspaceManager.shared.workspace(for: wsId) {
                panelVisible = ws.panelVisible
                yaziPanelWidth = ws.panelWidth
                browserPanelVisible = ws.browserPanelVisible
                browserPanelWidth = ws.browserPanelWidth
            }
            WorkspaceManager.shared.yaziSurfaceStore = yaziStore
            WorkspaceManager.shared.browserSurfaceStore = browserStore
```

改为：
```swift
        .onAppear {
            startupMode = initialStartupMode
            if let wsId = workspaceId, let ws = WorkspaceManager.shared.workspace(for: wsId) {
                panelVisible = ws.panelVisible
                yaziPanelWidth = ws.panelWidth
                leftPanelTool = LeftPanelTool(rawValue: ws.leftPanelTool) ?? .yazi
                browserPanelVisible = ws.browserPanelVisible
                browserPanelWidth = ws.browserPanelWidth
            }
            WorkspaceManager.shared.yaziSurfaceStore = yaziStore
            WorkspaceManager.shared.lazygitSurfaceStore = lazygitStore
            WorkspaceManager.shared.browserSurfaceStore = browserStore
```

- [ ] **Step 3: 更新 YaziPanelView → LeftPanelView 渲染**

找到：
```swift
                    // Yazi 文件管理面板
                    if panelVisible {
                        YaziPanelView(
                            workspaceId: workspaceId ?? standaloneId,
                            ghostty: ghostty,
                            yaziStore: yaziStore,
                            rootDir: currentWorkspaceRootDir,
                            worktreeMonitor: worktreeMonitor,
                            isExpanded: panelExpanded,
                            onToggleExpand: { panelExpanded.toggle() },
                            onClose: { panelVisible = false; panelExpanded = false }
                        )
```

改为：
```swift
                    // Left Panel（File Browser / Git）
                    if panelVisible {
                        LeftPanelView(
                            workspaceId: workspaceId ?? standaloneId,
                            ghostty: ghostty,
                            yaziStore: yaziStore,
                            lazygitStore: lazygitStore,
                            rootDir: currentWorkspaceRootDir,
                            worktreeMonitor: worktreeMonitor,
                            isExpanded: panelExpanded,
                            currentTool: leftPanelTool,
                            onSwitchTool: { tool in leftPanelTool = tool },
                            onToggleExpand: { panelExpanded.toggle() },
                            onClose: { panelVisible = false; panelExpanded = false }
                        )
```

- [ ] **Step 4: 更新 .toggleFileBrowser 通知处理，添加 .toggleGitPanel 处理**

找到：
```swift
        .onReceive(NotificationCenter.default.publisher(for: .toggleFileBrowser)) { _ in
            panelVisible.toggle()
        }
```

改为：
```swift
        .onReceive(NotificationCenter.default.publisher(for: .toggleFileBrowser)) { _ in
            if !panelVisible {
                panelVisible = true
                leftPanelTool = .yazi
            } else if leftPanelTool == .yazi {
                panelVisible = false
                panelExpanded = false
            } else {
                leftPanelTool = .yazi
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleGitPanel)) { _ in
            if !panelVisible {
                panelVisible = true
                leftPanelTool = .lazygit
            } else if leftPanelTool == .lazygit {
                panelVisible = false
                panelExpanded = false
            } else {
                leftPanelTool = .lazygit
            }
        }
```

- [ ] **Step 5: 添加 leftPanelTool onChange 持久化**

找到：
```swift
        .onChange(of: panelVisible) { newValue in
            guard let wsId = workspaceId else { return }
            guard var ws = WorkspaceManager.shared.workspace(for: wsId) else { return }
            ws.panelVisible = newValue
            WorkspaceManager.shared.update(ws)
        }
```

在其后添加：
```swift
        .onChange(of: leftPanelTool) { newValue in
            guard let wsId = workspaceId else { return }
            guard var ws = WorkspaceManager.shared.workspace(for: wsId) else { return }
            ws.leftPanelTool = newValue.rawValue
            WorkspaceManager.shared.update(ws)
        }
```

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Workspace/PolterttyRootView.swift
git commit -m "feat: update PolterttyRootView to use LeftPanelView with tool switching"
```

---

## Task 8: 更新 PopupOverlayManager（移除 lazygit）

**Files:**
- Modify: `macos/Sources/Features/PopupOverlay/PopupOverlayManager.swift`

- [ ] **Step 1: 从 PopupType 移除 .lazygit，移除 lazygit 相关属性和方法**

用以下内容全量替换文件：

```swift
import Cocoa
import SwiftUI

/// 管理 shell popup 的生命周期。
/// - 关闭只是 orderOut，进程继续保留（会话保留语义）
/// - 进程自然退出时销毁窗口和 surface，下次 toggle 重建
@MainActor
class PopupOverlayManager {

    enum PopupType {
        case shell
    }

    private let ghostty: Ghostty.App
    private weak var parentWindow: NSWindow?
    private let workspaceId: UUID?

    private var shellSurface: Ghostty.SurfaceView?
    private var shellPopupWindow: PopupOverlayWindow?

    /// 打开 popup 前记录的 firstResponder，关闭时归还
    private weak var previousFirstResponder: NSResponder?

    private var shellExitObserver: (any NSObjectProtocol)?

    /// Local event monitor，用于捕获 ESC 键以关闭 shell popup
    private var escapeEventMonitor: Any?

    init(ghostty: Ghostty.App, parentWindow: NSWindow, workspaceId: UUID? = nil) {
        self.ghostty = ghostty
        self.parentWindow = parentWindow
        self.workspaceId = workspaceId
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(parentWindowDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: parentWindow
        )
        setupEscapeMonitor()
    }

    deinit {
        if let token = shellExitObserver {
            NotificationCenter.default.removeObserver(token)
        }
        if let monitor = escapeEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: parentWindow)
    }

    /// 安装 local event monitor，当 shell popup 可见时拦截 ESC 键
    private func setupEscapeMonitor() {
        escapeEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.keyCode == 53 else { return event }
            if self.isVisible(self.shellPopupWindow), let popupWin = self.shellPopupWindow {
                let keyWin = NSApp.keyWindow
                if keyWin === popupWin || keyWin === self.parentWindow {
                    self.dismiss(popupWin)
                    return nil
                }
            }
            return event
        }
    }

    // MARK: - Window Resize

    @objc private func parentWindowDidResize(_ notification: Notification) {
        guard let parent = parentWindow else { return }
        let contentRect = parent.contentLayoutRect
        let popupWidth  = contentRect.width  * 0.8
        let popupHeight = contentRect.height * 0.7
        let originX = parent.frame.origin.x + contentRect.origin.x + (contentRect.width  - popupWidth)  / 2
        let originY = parent.frame.origin.y + contentRect.origin.y + (contentRect.height - popupHeight) / 2
        let newFrame = NSRect(x: originX, y: originY, width: popupWidth, height: popupHeight)

        if let popup = shellPopupWindow, popup.isVisible {
            popup.setFrame(newFrame, display: true)
        }
    }

    // MARK: - Public API

    func toggle(_ type: PopupType) {
        switch type {
        case .shell:
            if isVisible(shellPopupWindow) {
                dismiss(shellPopupWindow)
            } else {
                show(type: .shell)
            }
        }
    }

    func dismissAll() {
        dismiss(shellPopupWindow)
    }

    // MARK: - Private helpers

    private func isVisible(_ window: PopupOverlayWindow?) -> Bool {
        window?.isVisible ?? false
    }

    private func show(type: PopupType) {
        guard let parent = parentWindow, ghostty.app != nil else { return }

        previousFirstResponder = parent.firstResponder

        let surface = getOrCreateSurface(type: type)
        let popup = getOrCreateWindow(type: type, surface: surface)

        let contentRect = parent.contentLayoutRect
        let popupWidth  = contentRect.width  * 0.8
        let popupHeight = contentRect.height * 0.7
        let originX = parent.frame.origin.x + contentRect.origin.x + (contentRect.width  - popupWidth)  / 2
        let originY = parent.frame.origin.y + contentRect.origin.y + (contentRect.height - popupHeight) / 2
        popup.setFrame(NSRect(x: originX, y: originY, width: popupWidth, height: popupHeight), display: false)

        if popup.parent == nil {
            parent.addChildWindow(popup, ordered: .above)
        }

        popup.alphaValue = 0
        popup.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            popup.animator().alphaValue = 1
        }
    }

    private func dismiss(_ popup: PopupOverlayWindow?) {
        guard let popup, popup.isVisible else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            popup.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            popup.orderOut(nil)
            popup.alphaValue = 1
            self?.parentWindow?.makeKeyAndOrderFront(nil)
            if let prev = self?.previousFirstResponder {
                self?.parentWindow?.makeFirstResponder(prev)
            }
        }
    }

    private func getOrCreateSurface(type: PopupType) -> Ghostty.SurfaceView {
        switch type {
        case .shell:
            if let existing = shellSurface { return existing }
            var config = Ghostty.SurfaceConfiguration()
            config.workspaceId = workspaceId
            let surface = Ghostty.SurfaceView(ghostty.app!, baseConfig: config)
            shellSurface = surface
            observeExit(surface: surface, type: .shell)
            return surface
        }
    }

    private func getOrCreateWindow(type: PopupType, surface: Ghostty.SurfaceView) -> PopupOverlayWindow {
        switch type {
        case .shell:
            if let existing = shellPopupWindow { return existing }
            let win = makeWindow(surface: surface, type: type)
            shellPopupWindow = win
            return win
        }
    }

    private func makeWindow(surface: Ghostty.SurfaceView, type: PopupType) -> PopupOverlayWindow {
        let win = PopupOverlayWindow()
        let hostingView = NSHostingView(
            rootView: Ghostty.SurfaceWrapper(surfaceView: surface)
                .environmentObject(ghostty)
        )
        win.contentView = hostingView

        if type == .shell {
            win.onEscapePressed = { [weak self, weak win] in
                guard let win else { return }
                self?.dismiss(win)
            }
        }
        return win
    }

    private func observeExit(surface: Ghostty.SurfaceView, type: PopupType) {
        let token = NotificationCenter.default.addObserver(
            forName: Ghostty.Notification.ghosttyCloseSurface,
            object: surface,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let processAlive = notification.userInfo?["process_alive"] as? Bool ?? false
            guard !processAlive else { return }

            switch type {
            case .shell:
                if let token = self.shellExitObserver {
                    NotificationCenter.default.removeObserver(token)
                    self.shellExitObserver = nil
                }
                self.shellPopupWindow?.close()
                self.shellPopupWindow = nil
                self.shellSurface = nil
            }
        }
        switch type {
        case .shell: shellExitObserver = token
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add macos/Sources/Features/PopupOverlay/PopupOverlayManager.swift
git commit -m "feat: remove lazygit from PopupOverlayManager, shell-only popup"
```

---

## Task 9: 更新 AppDelegate（菜单项 + toggleLazygitPopup）

**Files:**
- Modify: `macos/Sources/App/macOS/AppDelegate.swift`

- [ ] **Step 1: 更新菜单项标题和 action**

找到：
```swift
        let lazygitPopupItem = NSMenuItem(
            title: "Toggle Lazygit Popup",
            action: #selector(toggleLazygitPopup(_:)),
            keyEquivalent: "g"
        )
        lazygitPopupItem.keyEquivalentModifierMask = [.command, .option]
        workspaceMenu.addItem(lazygitPopupItem)
```

改为：
```swift
        let gitPanelItem = NSMenuItem(
            title: "Toggle Git Panel",
            action: #selector(toggleGitPanel(_:)),
            keyEquivalent: "g"
        )
        gitPanelItem.keyEquivalentModifierMask = [.command, .option]
        workspaceMenu.addItem(gitPanelItem)
```

- [ ] **Step 2: 替换 toggleLazygitPopup 方法**

找到：
```swift
    @objc func toggleLazygitPopup(_ sender: Any?) {
        let targetWindow = NSApp.keyWindow?.parent ?? NSApp.keyWindow
        guard let tc = targetWindow?.windowController as? TerminalController else { return }
        tc.toggleLazygitPopup(sender)
    }
```

改为：
```swift
    @objc func toggleGitPanel(_ sender: Any?) {
        NotificationCenter.default.post(name: .toggleGitPanel, object: nil)
    }
```

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/App/macOS/AppDelegate.swift
git commit -m "feat: update AppDelegate - rename to toggleGitPanel, post notification"
```

---

## Task 10: 更新 TerminalController（移除 toggleLazygitPopup）

**Files:**
- Modify: `macos/Sources/Features/Terminal/TerminalController.swift`

- [ ] **Step 1: 移除 toggleLazygitPopup 方法**

找到并删除：
```swift
    @objc func toggleLazygitPopup(_ sender: Any?) {
        popupOverlayManager?.toggle(.lazygit)
    }
```

- [ ] **Step 2: Commit**

```bash
git add macos/Sources/Features/Terminal/TerminalController.swift
git commit -m "feat: remove toggleLazygitPopup from TerminalController"
```

---

## Task 11: 更新 KeyboardShortcutsPanelView

**Files:**
- Modify: `macos/Sources/Features/Keyboard Shortcuts/KeyboardShortcutsPanelView.swift`

- [ ] **Step 1: 更新 Lazygit 相关文本**

找到：
```swift
                            ShortcutItem("Lazygit Popup", "⌥⌘G"),
```

改为：
```swift
                            ShortcutItem("Git Panel", "⌥⌘G"),
```

- [ ] **Step 2: Commit**

```bash
git add "macos/Sources/Features/Keyboard Shortcuts/KeyboardShortcutsPanelView.swift"
git commit -m "feat: update keyboard shortcuts panel - Lazygit Popup → Git Panel"
```

---

## Task 12: 构建验证

**Files:** N/A

- [ ] **Step 1: 构建 Debug 版本**

```bash
cd /path/to/worktree
xcodebuild -project macos/Ghostty.xcodeproj \
  -scheme Ghostty \
  -configuration Debug \
  -destination 'platform=macOS' \
  build 2>&1 | tail -30
```

预期：`** BUILD SUCCEEDED **`

如果出现编译错误，根据错误信息修复（常见：`YaziPanelToolbar` / `YaziPanelView` 的旧引用未清理完全）。

- [ ] **Step 2: 搜索残留旧引用**

```bash
grep -rn "YaziPanelView\|YaziPanelToolbar\|toggleLazygitPopup\|lazygitPopupItem" \
  macos/Sources/ 2>/dev/null
```

预期：无任何输出（全部替换完毕）

- [ ] **Step 3: 搜索残留 .lazygit popup 引用**

```bash
grep -rn "toggle(.lazygit)\|PopupType.lazygit\|case .lazygit" macos/Sources/ 2>/dev/null
```

预期：无任何输出

---

## Task 13: UI/UX 审查与测试

**按 UI/UX 规则进行审查，修复发现的问题，直到通过。**

- [ ] **Step 1: 运行 App，手动测试核心交互**

启动 App，执行以下测试序列并记录结果：

| # | 操作 | 预期结果 |
|---|------|---------|
| T1 | ⌥⌘F（面板关闭时） | 面板打开，显示 Yazi，toolbar 高亮 File Browser tab |
| T2 | ⌥⌘G（File Browser 面板打开时） | 面板保持打开，内容切换为 LazyGit，toolbar 高亮 Git tab |
| T3 | ⌥⌘F（Git 面板打开时） | 面板保持打开，内容切换回 Yazi |
| T4 | ⌥⌘G（Git 面板打开时） | 面板关闭 |
| T5 | ⌥⌘F（Yazi 面板打开时） | 面板关闭 |
| T6 | 点击工具栏 Git tab | 切换到 LazyGit（等同 ⌥⌘G） |
| T7 | 点击工具栏 File Browser tab | 切换到 Yazi（等同 ⌥⌘F） |
| T8 | ⌥⌘O（展开） | 面板全屏展开，两种工具均正常 |
| T9 | 拖拽分隔线 | 面板宽度调整，切换 tool 后宽度保留 |
| T10 | 关闭重启 App | 面板显示状态和当前 tool 正确恢复 |
| T11 | Shell Popup（⌥⌘J） | 不受影响，仍然弹出 shell popup |

- [ ] **Step 2: 使用 /audit 进行 UI/UX 审查**

```
/audit
```

对 LeftPanelToolbar 的 tab 按钮、视觉一致性、键盘可达性进行评分，记录发现的问题。

- [ ] **Step 3: 修复 audit 发现的问题**

对每个问题：
- 修改对应 Swift 文件
- 重新构建验证
- 标注修复内容

- [ ] **Step 4: PR 定向 Review（按 development-rules.md）**

检查以下回归风险：

**光标空心方块**：
- `LazyGitSurfaceStore` 创建的 surface 是否触发了 `syncFocusToSurfaceTree` 路径？
- 新 `LeftPanelView` 中的 `Ghostty.SurfaceWrapper` 挂载/卸载时焦点是否正确归还？

**多窗口通知隔离**：
- `.toggleGitPanel` 通知的 `object: nil` 是 global broadcast，与 `.toggleFileBrowser` 保持一致（当前可接受）
- 如后续发现多窗口问题，需改为 `object: workspaceId`

**初始渲染时序**：
- `LazyGitSurfaceStore.surface()` 首次调用时序是否正确（面板 visible 时才调用）？

- [ ] **Step 5: 生成测试报告**

将测试结果写入 `docs/superpowers/reports/2026-04-08-unified-left-panel-test-report.md`

---

## Task 14: 提交 PR

- [ ] **Step 1: 推送分支**

```bash
git push -u origin feat/unified-left-panel
```

- [ ] **Step 2: 创建 PR**

```bash
gh pr create \
  --title "feat: 统一左侧面板 - LazyGit 迁移为侧边栏" \
  --body "$(cat <<'EOF'
## Summary
- LazyGit 从浮动 Popup 迁移为左侧侧边栏，与 Yazi 共享同一面板位置
- ⌥⌘F / ⌥⌘G 快捷键保持不变，互斥切换
- 新建 `LazyGitSurfaceStore` 管理每个 workspace 的 LazyGit 进程会话
- 工具栏改造为 `LeftPanelToolbar`，顶部 Tab 显示当前工具，工作树选择器共用
- Yazi 专属布局切换按钮在 Git 模式下隐藏
- WorkspaceModel 新增 `leftPanelTool` 字段持久化当前工具

## Test plan
- [ ] T1-T11 手动测试用例全部通过
- [ ] /audit UI/UX 审查通过，无新增严重问题
- [ ] 构建无编译错误
- [ ] 光标焦点行为无回归
- [ ] Shell Popup（⌥⌘J）不受影响

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## 注意事项

1. **`@MainActor` 要求**：`LazyGitSurfaceStore.surface()` 和 `YaziSurfaceStore.surface()` 都标注了 `@MainActor`，在 SwiftUI 视图中调用时 SwiftUI 已在 main thread，不需要额外处理。

2. **surface 懒加载时机**：`LeftPanelView` 的 `.lazygit` 分支只在 `currentTool == .lazygit` 时调用 `lazygitStore.surface()`，不会在 Yazi 模式下预创建 LazyGit 进程。

3. **旧 `YaziPanelToolbar` / `YaziPanelView` 引用**：重命名 struct 后，所有调用点（仅 `PolterttyRootView`）需同步更新，Task 12 的残留引用检查会验证。

4. **`Ghostty.SurfaceConfiguration.workspaceId`**：`LazyGitSurfaceStore` 不设置 `config.workspaceId`（与 `PopupOverlayManager` 的原始实现一致），如后续需要 per-workspace 隔离可以加上。
