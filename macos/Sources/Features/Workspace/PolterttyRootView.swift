// macos/Sources/Features/Workspace/PolterttyRootView.swift
import SwiftUI

extension Notification.Name {
    static let toggleWorkspaceSidebar = Notification.Name("poltertty.toggleWorkspaceSidebar")
    static let toggleWorkspaceQuickSwitcher = Notification.Name("poltertty.toggleWorkspaceQuickSwitcher")
    static let closeWorkspace = Notification.Name("poltertty.closeWorkspace")
    static let workspaceSidebarNavigateUp = Notification.Name("poltertty.workspaceSidebarNavigateUp")
    static let workspaceSidebarNavigateDown = Notification.Name("poltertty.workspaceSidebarNavigateDown")
    static let toggleFileBrowser = Notification.Name("poltertty.toggleFileBrowser")
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
    static let toggleGitPanel = Notification.Name("poltertty.toggleGitPanel")
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

    @State private var sidebarVisible: Bool = PolterttyConfig.shared.sidebarVisible
    @State private var sidebarCollapsed: Bool = UserDefaults.standard.bool(forKey: "poltertty.sidebarCollapsed")
    @State private var sidebarWidth: CGFloat = CGFloat(PolterttyConfig.shared.sidebarWidth)
    @State private var quickSwitcherVisible = false
    @State private var notificationCenterVisible = false
    @State private var startupMode: WorkspaceStartupMode = .terminal

    @State private var showConvertAlert = false
    @State private var fileBrowserDividerHovered = false
    @State private var activePanelTab: PanelTab = .files
    @State private var showTmuxPicker = false
    @State private var tmuxPickerAttachInCurrentPane = false
    @State private var launcherVisible = false
    @State private var convertTargetId: UUID?
    @State private var convertName = ""

    @ObservedObject private var fileBrowserVM: FileBrowserViewModel
    @ObservedObject private var agentMonitorVM: AgentMonitorViewModel
    @ObservedObject private var gitPanelVM: GitPanelViewModel
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
        onOpenWorktreeInWindow: ((String) -> Void)? = nil
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

        if let wsId = workspaceId {
            self._fileBrowserVM = ObservedObject(
                wrappedValue: WorkspaceManager.shared.fileBrowserViewModel(for: wsId)
            )
        } else {
            self._fileBrowserVM = ObservedObject(
                wrappedValue: FileBrowserViewModel(rootDir: "")
            )
        }

        if let wsId = workspaceId {
            self._agentMonitorVM = ObservedObject(
                wrappedValue: AgentMonitorViewModel(workspaceId: wsId)
            )
        } else {
            self._agentMonitorVM = ObservedObject(
                wrappedValue: AgentMonitorViewModel(workspaceId: UUID())
            )
        }

        if let wsId = workspaceId {
            self._gitPanelVM = ObservedObject(
                wrappedValue: WorkspaceManager.shared.gitPanelViewModel(for: wsId)
            )
        } else {
            self._gitPanelVM = ObservedObject(wrappedValue: GitPanelViewModel())
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

    private var unifiedPanelWidth: CGFloat {
        switch activePanelTab {
        case .git:
            return gitPanelVM.gitPanelWidth
        case .files:
            if fileBrowserVM.showPreviewPanel {
                return fileBrowserVM.previewTotalWidth
            }
            return fileBrowserVM.panelWidth
        }
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
                            onOpenWorktreeInWindow: onOpenWorktreeInWindow
                        )
                        .frame(width: effectiveSidebarWidth)

                        Divider()
                    }

                    // Unified Panel (File Browser + Git Tab)
                    if fileBrowserVM.isVisible {
                        if fileBrowserVM.isPreviewFullscreen {
                            UnifiedPanelView(
                                fileBrowserVM: fileBrowserVM,
                                gitPanelVM: gitPanelVM,
                                activePanelTab: $activePanelTab,
                                worktreeMonitor: worktreeMonitor,
                                onOpenInTerminal: { url in
                                    NotificationCenter.default.post(
                                        name: .fileBrowserOpenInTerminal,
                                        object: nil,
                                        userInfo: [
                                            "workspaceId": workspaceId as Any,
                                            "path": url.path
                                        ]
                                    )
                                }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            UnifiedPanelView(
                                fileBrowserVM: fileBrowserVM,
                                gitPanelVM: gitPanelVM,
                                activePanelTab: $activePanelTab,
                                worktreeMonitor: worktreeMonitor,
                                onOpenInTerminal: { url in
                                    NotificationCenter.default.post(
                                        name: .fileBrowserOpenInTerminal,
                                        object: nil,
                                        userInfo: [
                                            "workspaceId": workspaceId as Any,
                                            "path": url.path
                                        ]
                                    )
                                }
                            )
                            .frame(width: unifiedPanelWidth)

                            unifiedPanelDivider

                            terminalAreaView
                        }
                    } else {
                        terminalAreaView
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
            }

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

            // App Launcher overlay
            if launcherVisible {
                AppLauncherView(
                    isPresented: $launcherVisible,
                    backgroundColor: Color(nsColor: .windowBackgroundColor)
                )
                .ignoresSafeArea()
            }
        }
        .onAppear { startupMode = initialStartupMode }
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
        .onReceive(NotificationCenter.default.publisher(for: .toggleFileBrowser)) { _ in
            if fileBrowserVM.isVisible {
                fileBrowserVM.isVisible = false
            } else {
                fileBrowserVM.isVisible = true
                activePanelTab = .files
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleGitPanel)) { _ in
            if fileBrowserVM.isVisible {
                if activePanelTab == .git {
                    // 已在 Git Tab：隐藏整个统一面板（toggle）
                    fileBrowserVM.isVisible = false
                } else {
                    // 在 Files Tab：切换到 Git Tab
                    if fileBrowserVM.isPreviewFullscreen {
                        fileBrowserVM.togglePreviewFullscreen()
                    }
                    activePanelTab = .git
                }
            } else {
                // 面板隐藏：打开面板并切到 Git Tab
                fileBrowserVM.isVisible = true
                activePanelTab = .git
            }
        }
        // 跟随文件浏览器当前路径（切换 worktree 时自动更新）
        .task(id: fileBrowserVM.effectiveRootDir) {
            let dir = fileBrowserVM.effectiveRootDir
            guard !dir.isEmpty else { return }
            await gitPanelVM.load(rootDir: dir)
            fileBrowserVM.updateGitRepo(gitPanelVM.repo)
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
        .onReceive(NotificationCenter.default.publisher(for: .toggleAppLauncher)) { notification in
            guard notification.object as? NSWindow == windowProvider() else { return }
            launcherVisible.toggle()
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
        // 删除所有 workspace 后保持 terminal 模式（不跳 onboarding），用户可通过侧边栏重新创建
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
            .environmentObject(gitPanelVM)
    }

    private var unifiedPanelDivider: some View {
        ZStack {
            // 悬停时加深边框，方便用户找到拖拽区域
            Color(nsColor: fileBrowserDividerHovered ? .controlAccentColor : .separatorColor)
                .frame(width: fileBrowserDividerHovered ? 2 : 1)
                .animation(.easeInOut(duration: 0.15), value: fileBrowserDividerHovered)
            if fileBrowserDividerHovered {
                DividerGripHandle()
            }
        }
        .frame(width: 24)
        .contentShape(Rectangle())
        .onHover { hovering in
            fileBrowserDividerHovered = hovering
            if hovering { NSCursor.resizeLeftRight.push() }
            else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    switch activePanelTab {
                    case .git:
                        let newWidth = gitPanelVM.gitPanelWidth + value.translation.width
                        gitPanelVM.gitPanelWidth = max(400, min(1200, newWidth))
                    case .files:
                        if fileBrowserVM.showPreviewPanel {
                            let minW = fileBrowserVM.treeWidth + 217
                            let newWidth = fileBrowserVM.previewTotalWidth + value.translation.width
                            fileBrowserVM.previewTotalWidth = max(minW, min(1200, newWidth))
                        } else {
                            let newWidth = fileBrowserVM.panelWidth + value.translation.width
                            fileBrowserVM.panelWidth = max(160, min(600, newWidth))
                        }
                    }
                }
        )
    }

    // Called by TerminalController to get current sidebar state for snapshots
    var currentSidebarWidth: CGFloat { effectiveSidebarWidth }
    var currentSidebarVisible: Bool { sidebarVisible }
    var currentFileBrowserVisible: Bool { fileBrowserVM.isVisible }
    var currentFileBrowserWidth: CGFloat { fileBrowserVM.panelWidth }
}
