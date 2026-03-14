// macos/Sources/Features/Workspace/PolterttyRootView.swift
import SwiftUI

struct PolterttyRootView<TerminalContent: View>: View {
    @ObservedObject var manager = WorkspaceManager.shared
    let workspaceId: UUID?
    let terminalView: TerminalContent
    let onSwitchWorkspace: (UUID) -> Void

    @State private var sidebarVisible: Bool = PolterttyConfig.shared.sidebarVisible
    @State private var sidebarWidth: CGFloat = CGFloat(PolterttyConfig.shared.sidebarWidth)
    @State private var quickSwitcherVisible = false

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // Sidebar
                if sidebarVisible {
                    WorkspaceSidebar(
                        currentWorkspaceId: workspaceId,
                        onSwitch: { id in onSwitchWorkspace(id) },
                        onCreate: {}
                    )
                    .frame(width: sidebarWidth)

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
        .onKeyPress(KeyEquivalent("w"), modifiers: [.command, .control]) {
            quickSwitcherVisible.toggle()
            return .handled
        }
        .onKeyPress(KeyEquivalent("b"), modifiers: .command) {
            sidebarVisible.toggle()
            return .handled
        }
    }

    // Called by TerminalController to get current sidebar state for snapshots
    var currentSidebarWidth: CGFloat { sidebarWidth }
    var currentSidebarVisible: Bool { sidebarVisible }
}
