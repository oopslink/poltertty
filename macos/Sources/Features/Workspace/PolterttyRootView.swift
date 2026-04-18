// macos/Sources/Features/Workspace/PolterttyRootView.swift
import SwiftUI

extension Notification.Name {
    static let toggleWorkspaceSidebar = Notification.Name("poltertty.toggleWorkspaceSidebar")
    static let toggleWorkspaceQuickSwitcher = Notification.Name("poltertty.toggleWorkspaceQuickSwitcher")
    static let closeWorkspace = Notification.Name("poltertty.closeWorkspace")
    static let workspaceSidebarNavigateUp = Notification.Name("poltertty.workspaceSidebarNavigateUp")
    static let workspaceSidebarNavigateDown = Notification.Name("poltertty.workspaceSidebarNavigateDown")
    static let toggleFileBrowser = Notification.Name("poltertty.toggleFileBrowser")
    static let toggleGitPanel = Notification.Name("poltertty.toggleGitPanel")
    static let toggleBrowserPanel = Notification.Name("poltertty.toggleBrowserPanel")
    static let openBrowserPanel = Notification.Name("poltertty.openBrowserPanel")
    static let openURLInBrowserPanel = Notification.Name("poltertty.openURLInBrowserPanel")
    static let fileBrowserOpenInTerminal = Notification.Name("poltertty.fileBrowserOpenInTerminal")
    static let toggleAgentMonitor = Notification.Name("poltertty.toggleAgentMonitor")
    static let launchAgentFromSidebar = Notification.Name("poltertty.launchAgentFromSidebar")
    static let launchAgentFromStatusBar = Notification.Name("poltertty.launchAgentFromStatusBar")
    static let showTmuxSessionPicker = Notification.Name("poltertty.showTmuxSessionPicker")
    static let tmuxAttachNewTab = Notification.Name("poltertty.tmuxAttachNewTab")
    static let tmuxAttachInCurrentPane = Notification.Name("poltertty.tmuxAttachInCurrentPane")
    static let toggleNotificationCenter = Notification.Name("poltertty.toggleNotificationCenter")
    static let jumpToHighestPriorityUnread = Notification.Name("poltertty.jumpToHighestPriorityUnread")
    static let toggleAgentDashboard = Notification.Name("poltertty.toggleAgentDashboard")
}

struct PolterttyRootView<TerminalContent: View>: View {
    @ObservedObject var manager = WorkspaceManager.shared
    let ghostty: Ghostty.App
    let workspaceId: UUID?
    let terminalView: TerminalContent
    let onSwitchWorkspace: (UUID) -> Void
    let onCloseWorkspace: (UUID) -> Void

    let initialStartupMode: WorkspaceStartupMode
    let onCreateFormalWorkspace: ((_ name: String, _ rootDir: String, _ colorHex: String, _ description: String) -> Void)?
    let onCreateTemporaryWorkspace: (() -> Void)?
    let onRestoreWorkspaces: (([UUID]) -> Void)?
    let onCreateTemporary: (() -> Void)?

    var worktreeMonitor: GitWorktreeMonitor? = nil
    var onOpenWorktreeInTab: ((String) -> Void)? = nil
    var onOpenWorktreeInWindow: ((String) -> Void)? = nil
    var onOpenWorktreeInSplit: ((String, SplitTree<Ghostty.SurfaceView>.NewDirection) -> Void)? = nil

    @State private var sidebarVisible: Bool = PolterttyConfig.shared.sidebarVisible
    @State private var sidebarCollapsed: Bool = UserDefaults.standard.bool(forKey: "poltertty.sidebarCollapsed")
    @State private var sidebarWidth: CGFloat = CGFloat(PolterttyConfig.shared.sidebarWidth)
    @State private var quickSwitcherVisible = false
    @State private var notificationCenterVisible = false
    @State private var startupMode: WorkspaceStartupMode = .terminal

    @State private var showConvertAlert = false
    @State private var showTmuxPicker = false
    @State private var tmuxPickerAttachInCurrentPane = false
    @State private var unifiedPaletteVisible = false
    @State private var paletteSurface: Ghostty.SurfaceView? = nil
    @State private var keyboardShortcutsPanelVisible = false
    @State private var convertTargetId: UUID?
    @State private var convertName = ""

    @StateObject private var yaziStore = YaziSurfaceStore()
    @StateObject private var lazygitStore = LazyGitSurfaceStore()
    @State private var panelVisible: Bool = false
    @State private var panelExpanded: Bool = false
    @State private var leftPanelTool: LeftPanelTool = .yazi
    @State private var yaziPanelWidth: CGFloat = 260
    @GestureState private var panelWidthDelta: CGFloat = 0

    @StateObject private var browserStore = BrowserSurfaceStore()
    @State private var browserPanelVisible: Bool = false
    @State private var browserPanelExpanded: Bool = false
    @State private var browserPanelWidth: CGFloat = 400
    @GestureState private var browserWidthDelta: CGFloat = 0
    /// 终端 HStack 容器宽度（由 GeometryReader 测量），用于给 browser 动态算上限。
    /// 直接用 GeometryReader 包裹 case .terminal 的 body，把 geo.size.width 通过闭包写入 state。
    @State private var containerWidth: CGFloat = 0

    // 无 workspace 时作为面板的临时标识符（仅限当前会话，不持久化）
    @State private var standaloneId = UUID()

    @ObservedObject private var agentMonitorVM: AgentMonitorViewModel
    @ObservedObject var tabBarViewModel: TabBarViewModel
    let workspaceAccentColor: Color
    let onSwitchTab: ((UUID) -> Void)?
    let windowProvider: () -> NSWindow?

    init(
        ghostty: Ghostty.App,
        workspaceId: UUID?,
        terminalView: TerminalContent,
        onSwitchWorkspace: @escaping (UUID) -> Void,
        onCloseWorkspace: @escaping (UUID) -> Void,
        initialStartupMode: WorkspaceStartupMode,
        onCreateFormalWorkspace: ((_ name: String, _ rootDir: String, _ colorHex: String, _ description: String) -> Void)?,
        onCreateTemporaryWorkspace: (() -> Void)?,
        onRestoreWorkspaces: (([UUID]) -> Void)?,
        onCreateTemporary: (() -> Void)?,
        tabBarViewModel: TabBarViewModel,
        workspaceAccentColor: Color,
        onSwitchTab: ((UUID) -> Void)? = nil,
        windowProvider: @escaping () -> NSWindow? = { nil },
        worktreeMonitor: GitWorktreeMonitor? = nil,
        onOpenWorktreeInTab: ((String) -> Void)? = nil,
        onOpenWorktreeInWindow: ((String) -> Void)? = nil,
        onOpenWorktreeInSplit: ((String, SplitTree<Ghostty.SurfaceView>.NewDirection) -> Void)? = nil
    ) {
        self.ghostty = ghostty
        self.workspaceId = workspaceId
        self.terminalView = terminalView
        self.onSwitchWorkspace = onSwitchWorkspace
        self.onCloseWorkspace = onCloseWorkspace
        self.initialStartupMode = initialStartupMode
        self.onCreateFormalWorkspace = onCreateFormalWorkspace
        self.onCreateTemporaryWorkspace = onCreateTemporaryWorkspace
        self.onRestoreWorkspaces = onRestoreWorkspaces
        self.onCreateTemporary = onCreateTemporary
        self.tabBarViewModel = tabBarViewModel
        self.workspaceAccentColor = workspaceAccentColor
        self.onSwitchTab = onSwitchTab
        self.windowProvider = windowProvider
        self.worktreeMonitor = worktreeMonitor
        self.onOpenWorktreeInTab = onOpenWorktreeInTab
        self.onOpenWorktreeInWindow = onOpenWorktreeInWindow
        self.onOpenWorktreeInSplit = onOpenWorktreeInSplit

        if let wsId = workspaceId {
            self._agentMonitorVM = ObservedObject(
                wrappedValue: AgentMonitorViewModel(workspaceId: wsId)
            )
        } else {
            self._agentMonitorVM = ObservedObject(
                wrappedValue: AgentMonitorViewModel(workspaceId: UUID())
            )
        }
    }

    private var showStatusBar: Bool {
        guard let id = workspaceId,
              let ws = WorkspaceManager.shared.workspace(for: id) else { return false }
        return !ws.isTemporary
    }

    private var effectiveSidebarWidth: CGFloat {
        sidebarCollapsed ? 48 : sidebarWidth
    }

    private var effectivePanelWidth: CGFloat {
        max(160, min(600, yaziPanelWidth + panelWidthDelta))
    }

    /// 非 browser / 非 terminal 的固定占位宽度（sidebar + sidebar 1pt 分隔 + 左面板 + 左面板 divider）。
    private var fixedSideConsumption: CGFloat {
        let sidebar = sidebarVisible ? effectiveSidebarWidth : 0
        let sidebarDiv: CGFloat = sidebarVisible ? 1 : 0
        let leftPanel = (panelVisible && !panelExpanded) ? effectivePanelWidth : 0
        let leftPanelDiv: CGFloat = (panelVisible && !panelExpanded) ? ResizeDivider.hitWidth : 0
        return sidebar + sidebarDiv + leftPanel + leftPanelDiv
    }

    /// browser 面板动态上限：容器宽度减去 sidebar、左面板、左面板分隔线、browser 分隔线。
    /// 未测得容器宽度时回退到 800（保持旧行为，首帧后立即更新）。
    private var browserPanelMaxWidth: CGFloat {
        guard containerWidth > 0 else { return 800 }
        let browserDiv: CGFloat = browserPanelVisible && !browserPanelExpanded ? ResizeDivider.hitWidth : 0
        return max(200, containerWidth - fixedSideConsumption - browserDiv)
    }

    private var effectiveBrowserPanelWidth: CGFloat {
        max(200, min(browserPanelMaxWidth, browserPanelWidth + browserWidthDelta))
    }


    private var currentWorkspaceRootDir: String {
        guard let wsId = workspaceId,
              let ws = WorkspaceManager.shared.workspace(for: wsId) else { return NSHomeDirectory() }
        return ws.rootDirExpanded
    }

    var body: some View {
        ZStack {
            switch startupMode {
            case .onboarding:
                OnboardingView(
                    onCreateFormal: { name, rootDir, colorHex, description in
                        onCreateFormalWorkspace?(name, rootDir, colorHex, description)
                        startupMode = .terminal
                    },
                    onCreateTemporary: {
                        onCreateTemporaryWorkspace?()
                        startupMode = .terminal
                    }
                )

            case .restore:
                RestoreView(
                    workspaces: manager.formalWorkspaces.sorted { $0.lastActiveAt > $1.lastActiveAt },
                    onRestore: { ids in
                        onRestoreWorkspaces?(ids)
                        startupMode = .terminal
                    },
                    onCreateNew: {
                        startupMode = .onboarding
                    }
                )

            case .terminal:
                HStack(spacing: 0) {
                    // Sidebar
                    if sidebarVisible {
                        WorkspaceSidebar(
                            currentWorkspaceId: workspaceId,
                            onSwitch: { id in onSwitchWorkspace(id) },
                            onClose: { id in onCloseWorkspace(id) },
                            onCreate: {},
                            onCreateTemporary: { onCreateTemporary?() },
                            onConvert: { workspace in
                                convertTargetId = workspace.id
                                convertName = workspace.name
                                showConvertAlert = true
                            },
                            onLaunchAgent: {
                                NotificationCenter.default.post(
                                    name: .launchAgentFromSidebar,
                                    object: nil,
                                    userInfo: ["workspaceId": workspaceId as Any]
                                )
                            },
                            isCollapsed: $sidebarCollapsed,
                            worktreeMonitor: worktreeMonitor,
                            onOpenWorktreeInTab: onOpenWorktreeInTab,
                            onOpenWorktreeInWindow: onOpenWorktreeInWindow,
                            onOpenWorktreeInSplit: onOpenWorktreeInSplit
                        )
                        .frame(width: effectiveSidebarWidth)

                        Divider()
                    }

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
                        .frame(width: panelExpanded ? nil : effectivePanelWidth)
                        .frame(maxWidth: panelExpanded ? .infinity : effectivePanelWidth)

                        if !panelExpanded {
                            yaziPanelDivider
                        }

                        // 终端始终保留在视图树中（防止进程被销毁），展开时宽度压缩为 0。
                        // `minWidth: 0` 让终端能被 HStack 压缩到任意窄，以便 browser 能拉到最大。
                        terminalAreaView
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .frame(width: (panelExpanded || browserPanelExpanded) ? 0 : nil)
                            .opacity((panelExpanded || browserPanelExpanded) ? 0 : 1)
                            .clipped()
                    } else {
                        terminalAreaView
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .frame(width: browserPanelExpanded ? 0 : nil)
                            .opacity(browserPanelExpanded ? 0 : 1)
                            .clipped()
                    }

                    // Browser Panel (right side, 向左展开)
                    if browserPanelVisible {
                        HStack(spacing: 0) {
                            if !browserPanelExpanded {
                                browserPanelDivider
                            }
                            BrowserPanelView(
                                workspaceId: workspaceId ?? standaloneId,
                                browserStore: browserStore,
                                snapshotsForRestore: WorkspaceManager.shared.workspace(for: workspaceId ?? UUID())?.browserTabSnapshots ?? [],
                                activeSnapshotId: WorkspaceManager.shared.workspace(for: workspaceId ?? UUID())?.browserActiveTabId,
                                isExpanded: browserPanelExpanded,
                                onToggleExpand: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                        browserPanelExpanded.toggle()
                                    }
                                },
                                onClose: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                        browserPanelExpanded = false
                                        browserPanelVisible = false
                                    }
                                }
                            )
                            .frame(width: browserPanelExpanded ? nil : effectiveBrowserPanelWidth)
                            .frame(maxWidth: browserPanelExpanded ? .infinity : effectiveBrowserPanelWidth)
                            // fixedSize：确保 HStack 严格遵守 .frame(width:)，否则 Ghostty terminal
                            // 的 intrinsic 最小宽度会反压 browser 到 ~50%
                            .fixedSize(horizontal: !browserPanelExpanded, vertical: false)
                        }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }

                    // Notification Center Panel
                    if notificationCenterVisible {
                        Divider()
                        NotificationCenterPanel(
                            workspaceId: workspaceId,
                            onJumpToSurface: { surfaceId in
                                onSwitchTab?(surfaceId)
                            },
                            onClose: {
                                notificationCenterVisible = false
                            }
                        )
                    }

                    // Agent Monitor Panel
                    if agentMonitorVM.isVisible {
                        Divider()
                        AgentMonitorPanel(viewModel: agentMonitorVM)
                    }
                }
                .overlay(alignment: .trailing) {
                    HStack(spacing: 0) {
                        AgentDrawer(viewModel: agentMonitorVM)
                        // 占位 180px + 1px divider，使 Drawer 浮于终端上方而不遮盖侧边栏
                        if agentMonitorVM.isVisible {
                            Spacer().frame(width: 181)
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: agentMonitorVM.selectedItems.isEmpty)
                }
                .environment(\.showStatusBar, showStatusBar)
                .environment(\.workspaceId, workspaceId)
                .environment(\.browserPanelVisible, browserPanelVisible)
                .background(
                    GeometryReader { geo in
                        // 写 state 必须 async，避免 SwiftUI 在同一轮 layout 内递归
                        Color.clear.task(id: geo.size.width) {
                            if geo.size.width > 0 && geo.size.width != containerWidth {
                                containerWidth = geo.size.width
                            }
                        }
                    }
                )
            }

            // Hidden keyboard shortcut for browser panel
            Button("") {
                if startupMode == .terminal {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        browserPanelVisible.toggle()
                    }
                }
            }
            .keyboardShortcut("b", modifiers: [.option, .command])
            .opacity(0)
            .frame(width: 0, height: 0)

            // Hidden keyboard shortcut for browser panel expand (⌥⇧⌘B)
            Button("") {
                if startupMode == .terminal && browserPanelVisible {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        browserPanelExpanded.toggle()
                    }
                }
            }
            .keyboardShortcut("b", modifiers: [.option, .command, .shift])
            .opacity(0)
            .frame(width: 0, height: 0)

            // Quick switcher overlay (always available in terminal mode)
            if quickSwitcherVisible {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { quickSwitcherVisible = false }

                WorkspaceQuickSwitcher(
                    currentWorkspaceId: workspaceId,
                    onSelect: { id in
                        onSwitchWorkspace(id)
                        quickSwitcherVisible = false
                    },
                    onDismiss: { quickSwitcherVisible = false }
                )
            }

            // 统一 Command Palette（⌘⇧P 触发）
            if unifiedPaletteVisible {
                AppLauncherView(
                    isPresented: $unifiedPaletteVisible,
                    backgroundColor: Color(nsColor: .windowBackgroundColor),
                    surfaceView: paletteSurface,
                    performAction: paletteSurface.map { s in
                        { action, surface in
                            guard let tc = TerminalController.all.first(where: {
                                $0.surfaceTree.contains(where: { $0 === surface })
                            }) else { return }
                            tc.performAction(action, on: surface)
                        }
                    },
                    ghosttyConfig: (NSApp.delegate as? AppDelegate)?.ghostty.config
                )
                .ignoresSafeArea()
            }

            // Keyboard Shortcuts 速查面板（双击 Shift 触发）
            if keyboardShortcutsPanelVisible {
                KeyboardShortcutsPanelView(isPresented: $keyboardShortcutsPanelVisible)
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            startupMode = initialStartupMode
            if let wsId = workspaceId, let ws = WorkspaceManager.shared.workspace(for: wsId) {
                panelVisible = ws.panelVisible
                yaziPanelWidth = ws.panelWidth
                leftPanelTool = ws.leftPanelTool
                browserPanelVisible = ws.browserPanelVisible
                browserPanelWidth = ws.browserPanelWidth
            }
            WorkspaceManager.shared.yaziSurfaceStore = yaziStore
            WorkspaceManager.shared.lazygitSurfaceStore = lazygitStore
            WorkspaceManager.shared.browserSurfaceStore = browserStore
            WorkspaceMetadataStore.shared.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleWorkspaceSidebar)) { notification in
            guard notification.object as? NSWindow == windowProvider() else { return }
            sidebarVisible.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleWorkspaceQuickSwitcher)) { _ in
            quickSwitcherVisible.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .workspaceSidebarNavigateUp)) { _ in
            navigateWorkspace(direction: -1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .workspaceSidebarNavigateDown)) { _ in
            navigateWorkspace(direction: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleAgentMonitor)) { _ in
            agentMonitorVM.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleFileBrowser)) { notification in
            guard notification.object as? NSWindow == windowProvider() else { return }
            handleToggleLeftPanel(for: .yazi)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleGitPanel)) { notification in
            guard notification.object as? NSWindow == windowProvider() else { return }
            handleToggleLeftPanel(for: .lazygit)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleBrowserPanel)) { notification in
            guard (notification.object as? UUID) == workspaceId else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                browserPanelVisible.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openBrowserPanel)) { notification in
            guard (notification.object as? UUID) == workspaceId else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                browserPanelVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openURLInBrowserPanel)) { notification in
            guard let url = notification.userInfo?["url"] as? URL,
                  let wsId = notification.userInfo?["workspaceId"] as? UUID,
                  wsId == workspaceId else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                browserPanelVisible = true
            }
            let mgr = browserStore.manager(for: wsId)
            mgr.newTab(url: url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleNotificationCenter)) { _ in
            notificationCenterVisible.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .jumpToHighestPriorityUnread)) { _ in
            if let notification = AgentNotificationStore.shared.highestPriorityUnread() {
                AgentNotificationStore.shared.markRead(notification.id)
                if let sid = notification.surfaceId {
                    onSwitchTab?(sid)
                }
                if !notificationCenterVisible {
                    notificationCenterVisible = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showTmuxSessionPicker)) { notification in
            tmuxPickerAttachInCurrentPane = notification.userInfo?["attachInCurrentPane"] as? Bool ?? false
            showTmuxPicker = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleKeyboardShortcutsPanel)) { notification in
            guard notification.object as? NSWindow == windowProvider() else { return }
            keyboardShortcutsPanelVisible.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleUnifiedCommandPalette)) { notification in
            guard notification.object as? NSWindow == windowProvider() else { return }
            let surface = notification.userInfo?["surface"] as? Ghostty.SurfaceView
            if unifiedPaletteVisible {
                unifiedPaletteVisible = false
                paletteSurface = nil
            } else {
                paletteSurface = surface
                unifiedPaletteVisible = true
            }
        }
        .sheet(isPresented: $showTmuxPicker) {
            TmuxSessionPicker(
                onOpen: { sessionName in
                    showTmuxPicker = false
                    let inCurrentPane = tmuxPickerAttachInCurrentPane
                    // 延迟发送通知，等 sheet 完全关闭后 window 恢复 keyWindow 状态
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if inCurrentPane {
                            // 在当前 pane 中 attach（右键菜单触发）
                            NotificationCenter.default.post(
                                name: .tmuxAttachInCurrentPane,
                                object: nil,
                                userInfo: ["sessionName": sessionName]
                            )
                        } else {
                            // 新建 tab 并 attach（菜单触发）
                            NotificationCenter.default.post(
                                name: .tmuxAttachNewTab,
                                object: nil,
                                userInfo: ["sessionName": sessionName]
                            )
                        }
                    }
                },
                onCancel: { showTmuxPicker = false }
            )
        }
        .sheet(isPresented: $showConvertAlert) {
            convertToFormalSheet
        }
        // panelVisible/yaziPanelWidth 变化时即时写回 WorkspaceModel，供 persistPanelState 读取
        .onChange(of: panelVisible) { newValue in
            guard let wsId = workspaceId else { return }
            guard var ws = WorkspaceManager.shared.workspace(for: wsId) else { return }
            ws.panelVisible = newValue
            WorkspaceManager.shared.update(ws)
        }
        .onChange(of: leftPanelTool) { newValue in
            guard let wsId = workspaceId else { return }
            guard var ws = WorkspaceManager.shared.workspace(for: wsId) else { return }
            ws.leftPanelTool = newValue
            WorkspaceManager.shared.update(ws)
        }
        .onChange(of: yaziPanelWidth) { newValue in
            guard let wsId = workspaceId else { return }
            guard var ws = WorkspaceManager.shared.workspace(for: wsId) else { return }
            ws.panelWidth = newValue
            WorkspaceManager.shared.update(ws)
        }
        .onChange(of: browserPanelVisible) { newValue in
            if !newValue { browserPanelExpanded = false }
            guard let wsId = workspaceId else { return }
            guard var ws = WorkspaceManager.shared.workspace(for: wsId) else { return }
            ws.browserPanelVisible = newValue
            // Browser Panel 关闭时保存 tab 快照，供下次打开时恢复
            if !newValue, let mgr = browserStore.managers[wsId] {
                ws.browserTabSnapshots = mgr.currentSnapshot()
                ws.browserActiveTabId  = mgr.activeTabId
            }
            WorkspaceManager.shared.update(ws)
        }
        .onChange(of: browserPanelWidth) { newValue in
            guard let wsId = workspaceId else { return }
            guard var ws = WorkspaceManager.shared.workspace(for: wsId) else { return }
            ws.browserPanelWidth = newValue
            WorkspaceManager.shared.update(ws)
        }
        // 删除所有 workspace 后保持 terminal 模式（不跳 onboarding），用户可通过侧边栏重新创建
    }

    private func handleToggleLeftPanel(for tool: LeftPanelTool) {
        if !panelVisible {
            panelVisible = true
            leftPanelTool = tool
        } else if leftPanelTool == tool {
            panelVisible = false
            panelExpanded = false
        } else {
            leftPanelTool = tool
        }
    }

    private func navigateWorkspace(direction: Int) {
        let allWorkspaces = manager.workspaces
        guard !allWorkspaces.isEmpty else { return }
        guard let currentId = workspaceId,
              let currentIndex = allWorkspaces.firstIndex(where: { $0.id == currentId }) else {
            if let first = allWorkspaces.first {
                onSwitchWorkspace(first.id)
            }
            return
        }
        let newIndex = (currentIndex + direction + allWorkspaces.count) % allWorkspaces.count
        onSwitchWorkspace(allWorkspaces[newIndex].id)
    }

    @ViewBuilder
    private var convertToFormalSheet: some View {
        VStack(spacing: 16) {
            Text("Convert to Workspace")
                .font(.system(size: 14, weight: .semibold))

            TextField("Name", text: Binding(
                get: { convertName },
                set: { convertName = WorkspaceNameValidator.filterInput($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 240)

            HStack {
                Button("Cancel") { showConvertAlert = false }
                Button("Confirm") {
                    if let id = convertTargetId {
                        manager.convertToFormal(id: id, newName: convertName)
                    }
                    showConvertAlert = false
                }
                .disabled(convertName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
    }

    /// 终端区域：当前活跃 surface
    @ViewBuilder
    private var terminalAreaView: some View {
        // 终端内容：始终使用 terminalView 渲染 surfaceTree（支持 split + tab）
        // tab 切换通过 onSwitchTab 回调更新 controller 的 surfaceTree
        terminalView
            .environmentObject(tabBarViewModel)
    }

    @State private var yaziDividerHovering: Bool = false
    @State private var browserDividerHovering: Bool = false

    private var yaziPanelDivider: some View {
        ResizeDivider(
            hovering: yaziDividerHovering,
            onHoverChange: { yaziDividerHovering = $0 }
        )
        .gesture(
            DragGesture(minimumDistance: 1)
                .updating($panelWidthDelta) { value, state, _ in
                    state = value.translation.width
                }
                .onEnded { value in
                    yaziPanelWidth = max(160, min(600, yaziPanelWidth + value.translation.width))
                }
        )
    }

    private var browserPanelDivider: some View {
        ResizeDivider(
            hovering: browserDividerHovering,
            onHoverChange: { browserDividerHovering = $0 }
        )
        .gesture(
            DragGesture(minimumDistance: 1)
                .updating($browserWidthDelta) { value, state, _ in
                    state = -value.translation.width
                }
                .onEnded { value in
                    browserPanelWidth = max(
                        200,
                        min(browserPanelMaxWidth, browserPanelWidth - value.translation.width)
                    )
                }
        )
    }

    // Called by TerminalController to get current sidebar state for snapshots
    var currentSidebarWidth: CGFloat { effectiveSidebarWidth }
    var currentSidebarVisible: Bool { sidebarVisible }
    var currentFileBrowserVisible: Bool { panelVisible }
    var currentFileBrowserWidth: CGFloat { yaziPanelWidth }
}

/// PolterttyRootView terminal 容器宽度。由 GeometryReader 上报，
/// 用于给 browser 面板拖拽上限算出"满窗口（侧边栏除外）"的动态上限。
private struct ContainerWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// 面板之间的可拖拽分隔条。
/// - 10pt 透明 hit area（Apple HIG ≥10pt）保证不用像素级精准也能命中
/// - 1pt 可见分隔线；hover 时加粗到 3pt 并变成强调色，提供视觉反馈
/// - macOS 15+ 使用 `.pointerStyle`，旧系统回退到 NSCursor push/pop（与 SplitView.Divider 一致）
/// - 父视图通过 `.gesture(...)` 挂拖拽手势，本组件仅负责外观和 hover 态
struct ResizeDivider: View {
    /// 对外导出的 hit-area 宽度，布局算子用它算可用空间。
    static let hitWidth: CGFloat = 10

    let hovering: Bool
    let onHoverChange: (Bool) -> Void

    var body: some View {
        ZStack {
            // 透明 hit area：可靠命中 + 承载 hover / pointerStyle
            Color.clear
                .frame(width: Self.hitWidth)
                .contentShape(Rectangle())
            // 可见分隔线：hover / 拖拽中加粗变色，给用户明确反馈
            Rectangle()
                .fill(hovering ? Color.accentColor.opacity(0.8) : Color(nsColor: .separatorColor))
                .frame(width: hovering ? 3 : 1)
                .animation(.easeInOut(duration: 0.12), value: hovering)
        }
        .frame(maxHeight: .infinity)
        .backport.pointerStyle(.resizeLeftRight)
        .onHover { isHovered in
            onHoverChange(isHovered)
            // macOS 15+ 用 pointerStyle，不需要手动 push/pop
            if #available(macOS 15, *) { return }
            if isHovered {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
