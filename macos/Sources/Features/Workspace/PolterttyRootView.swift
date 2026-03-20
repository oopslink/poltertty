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
    static let toggleTmuxPanel = Notification.Name("poltertty.toggleTmuxPanel")
    static let showTmuxSessionPicker = Notification.Name("poltertty.showTmuxSessionPicker")
    static let tmuxAttachNewTab = Notification.Name("poltertty.tmuxAttachNewTab")
    static let tmuxAttachInCurrentPane = Notification.Name("poltertty.tmuxAttachInCurrentPane")
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

    @State private var sidebarVisible: Bool = PolterttyConfig.shared.sidebarVisible
    @State private var sidebarCollapsed: Bool = UserDefaults.standard.bool(forKey: "poltertty.sidebarCollapsed")
    @State private var sidebarWidth: CGFloat = CGFloat(PolterttyConfig.shared.sidebarWidth)
    @State private var quickSwitcherVisible = false
    @FocusedValue(\.ghosttySurfacePwd) private var focusedPwd

    @State private var startupMode: WorkspaceStartupMode = .terminal

    @State private var showConvertAlert = false
    @State private var fileBrowserDividerHovered = false
    @State private var tmuxDividerHovered = false
    @State private var showTmuxPicker = false
    @State private var tmuxPickerAttachInCurrentPane = false
    @State private var convertTargetId: UUID?
    @State private var convertName = ""

    @ObservedObject private var fileBrowserVM: FileBrowserViewModel
    @ObservedObject private var agentMonitorVM: AgentMonitorViewModel
    @ObservedObject private var tmuxPanelVM: TmuxPanelViewModel
    @ObservedObject var tabBarViewModel: TabBarViewModel
    let workspaceAccentColor: Color
    let statusMonitor: GitStatusMonitor
    let showStatusBar: Bool
    let onNewTab: () -> Void
    let onCloseTab: (UUID) -> Void
    let onSwitchTab: ((UUID) -> Void)?

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
        statusMonitor: GitStatusMonitor,
        showStatusBar: Bool,
        onNewTab: @escaping () -> Void,
        onCloseTab: @escaping (UUID) -> Void,
        onSwitchTab: ((UUID) -> Void)? = nil
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
        self.statusMonitor = statusMonitor
        self.showStatusBar = showStatusBar
        self.tabBarViewModel = tabBarViewModel
        self.workspaceAccentColor = workspaceAccentColor
        self.onNewTab = onNewTab
        self.onCloseTab = onCloseTab
        self.onSwitchTab = onSwitchTab

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

        self._tmuxPanelVM = ObservedObject(wrappedValue: TmuxPanelViewModel())
    }

    private var effectiveSidebarWidth: CGFloat {
        sidebarCollapsed ? 48 : sidebarWidth
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
                            isCollapsed: $sidebarCollapsed
                        )
                        .frame(width: effectiveSidebarWidth)

                        Divider()
                    }

                    // File Browser Panel
                    if fileBrowserVM.isVisible {
                        if fileBrowserVM.isPreviewFullscreen {
                            // Fullscreen mode: file browser takes all space
                            FileBrowserPanel(
                                viewModel: fileBrowserVM,
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
                            // Normal mode
                            FileBrowserPanel(
                                viewModel: fileBrowserVM,
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
                            .frame(
                                minWidth: fileBrowserVM.showPreviewPanel
                                    ? (fileBrowserVM.treeWidth + 217)
                                    : 160,
                                maxWidth: fileBrowserVM.showPreviewPanel
                                    ? fileBrowserVM.previewTotalWidth
                                    : fileBrowserVM.panelWidth
                            )

                            fileBrowserDivider

                            if tmuxPanelVM.isVisible {
                                TmuxPanelView(viewModel: tmuxPanelVM)
                                    .frame(width: tmuxPanelVM.panelWidth)
                                tmuxDividerView
                            }
                            terminalAreaView
                        }
                    } else {
                        // File browser not visible, show terminal
                        if tmuxPanelVM.isVisible {
                            TmuxPanelView(viewModel: tmuxPanelVM)
                                .frame(width: tmuxPanelVM.panelWidth)
                            tmuxDividerView
                        }
                        terminalAreaView
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
                .onChange(of: focusedPwd) { newPwd in
                    // single-parameter closure, compatible with macOS 13+
                    guard let pwd = newPwd, !pwd.isEmpty else { return }
                    statusMonitor.updatePwd(pwd)
                }
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
        }
        .onAppear { startupMode = initialStartupMode }
        .onReceive(NotificationCenter.default.publisher(for: .toggleWorkspaceSidebar)) { _ in
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
        .onReceive(NotificationCenter.default.publisher(for: .toggleTmuxPanel)) { _ in
            tmuxPanelVM.isVisible.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showTmuxSessionPicker)) { notification in
            tmuxPickerAttachInCurrentPane = notification.userInfo?["attachInCurrentPane"] as? Bool ?? false
            showTmuxPicker = true
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
        .onChange(of: manager.formalWorkspaces.count) { count in
            // When all formal workspaces are deleted, return to onboarding
            if count == 0 && startupMode == .terminal {
                startupMode = .onboarding
            }
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
            Text("转为正式 Workspace")
                .font(.system(size: 14, weight: .semibold))

            TextField("名称", text: Binding(
                get: { convertName },
                set: { convertName = WorkspaceNameValidator.filterInput($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 240)

            HStack {
                Button("取消") { showConvertAlert = false }
                Button("确认") {
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

    /// 终端区域：tab bar（条件显示）+ 当前活跃 surface
    @ViewBuilder
    private var terminalAreaView: some View {
        VStack(spacing: 0) {
            // Tab bar：多 tab 且非全屏预览时显示
            if tabBarViewModel.tabs.count > 1 {
                TerminalTabBar(
                    viewModel: tabBarViewModel,
                    accentColor: workspaceAccentColor,
                    onNewTab: onNewTab,
                    onCloseTab: onCloseTab,
                    onSwitchTab: onSwitchTab
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 终端内容：始终使用 terminalView 渲染 surfaceTree（支持 split + tab）
            // tab 切换通过 onSwitchTab 回调更新 controller 的 surfaceTree
            terminalView
                .environment(\.tabBarViewModel, tabBarViewModel)

            // Status bar 在 shell 区域正下方，与 shell 区域对齐
            if showStatusBar {
                BottomStatusBarView(
                    monitor: statusMonitor,
                    pwd: focusedPwd ?? ""
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: tabBarViewModel.tabs.count > 1)
    }

    private var fileBrowserDivider: some View {
        ZStack {
            Color(nsColor: .separatorColor)
                .frame(width: 1)
            if fileBrowserDividerHovered {
                DividerGripHandle()
            }
        }
        .frame(width: 16)
        .contentShape(Rectangle())
        .onHover { hovering in
            fileBrowserDividerHovered = hovering
            if hovering { NSCursor.resizeLeftRight.push() }
            else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if fileBrowserVM.showPreviewPanel {
                        let minW = fileBrowserVM.treeWidth + 217
                        let newWidth = fileBrowserVM.previewTotalWidth + value.translation.width
                        fileBrowserVM.previewTotalWidth = max(minW, min(1200, newWidth))
                    } else {
                        let newWidth = fileBrowserVM.panelWidth + value.translation.width
                        fileBrowserVM.panelWidth = max(160, min(600, newWidth))
                    }
                }
        )
    }

    private var tmuxDividerView: some View {
        ZStack {
            Color(nsColor: .separatorColor)
                .frame(width: 1)
            if tmuxDividerHovered {
                DividerGripHandle()
            }
        }
        .frame(width: 16)
        .contentShape(Rectangle())
        .onHover { hovering in
            tmuxDividerHovered = hovering
            if hovering { NSCursor.resizeLeftRight.push() }
            else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let newWidth = tmuxPanelVM.panelWidth + value.translation.width
                    tmuxPanelVM.panelWidth = max(160, min(600, newWidth))
                }
        )
    }

    // Called by TerminalController to get current sidebar state for snapshots
    var currentSidebarWidth: CGFloat { effectiveSidebarWidth }
    var currentSidebarVisible: Bool { sidebarVisible }
    var currentFileBrowserVisible: Bool { fileBrowserVM.isVisible }
    var currentFileBrowserWidth: CGFloat { fileBrowserVM.panelWidth }
}
