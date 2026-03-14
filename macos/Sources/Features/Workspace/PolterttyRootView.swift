// macos/Sources/Features/Workspace/PolterttyRootView.swift
import SwiftUI

extension Notification.Name {
    static let toggleWorkspaceSidebar = Notification.Name("poltertty.toggleWorkspaceSidebar")
    static let toggleWorkspaceQuickSwitcher = Notification.Name("poltertty.toggleWorkspaceQuickSwitcher")
    static let closeWorkspace = Notification.Name("poltertty.closeWorkspace")
}

struct PolterttyRootView<TerminalContent: View>: View {
    @ObservedObject var manager = WorkspaceManager.shared
    let workspaceId: UUID?
    let terminalView: TerminalContent
    let onSwitchWorkspace: (UUID) -> Void
    let onCloseWorkspace: (UUID) -> Void

    @State private var sidebarVisible: Bool = PolterttyConfig.shared.sidebarVisible
    @AppStorage("poltertty.sidebarCollapsed") private var sidebarCollapsed: Bool = false
    @State private var sidebarWidth: CGFloat = CGFloat(PolterttyConfig.shared.sidebarWidth)
    @State private var quickSwitcherVisible = false

    private var effectiveSidebarWidth: CGFloat {
        sidebarCollapsed ? 48 : sidebarWidth
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // Sidebar
                if sidebarVisible {
                    WorkspaceSidebar(
                        currentWorkspaceId: workspaceId,
                        onSwitch: { id in onSwitchWorkspace(id) },
                        onClose: { id in onCloseWorkspace(id) },
                        onCreate: {},
                        isCollapsed: $sidebarCollapsed
                    )
                    .frame(width: effectiveSidebarWidth)

                    Divider()
                }

                // Terminal view (passed through unchanged)
                terminalView
            }

            // Quick switcher overlay
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
        .onReceive(NotificationCenter.default.publisher(for: .toggleWorkspaceSidebar)) { _ in
            sidebarVisible.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleWorkspaceQuickSwitcher)) { _ in
            quickSwitcherVisible.toggle()
        }
    }

    // Called by TerminalController to get current sidebar state for snapshots
    var currentSidebarWidth: CGFloat { effectiveSidebarWidth }
    var currentSidebarVisible: Bool { sidebarVisible }
}
