// macos/Sources/Features/Workspace/UnifiedPanelView.swift
import SwiftUI

// MARK: - Panel Tab

enum PanelTab: String, CaseIterable {
    case files
    case git
}

// MARK: - Unified Panel View

struct UnifiedPanelView: View {
    @ObservedObject var fileBrowserVM: FileBrowserViewModel
    @ObservedObject var gitPanelVM: GitPanelViewModel
    @Binding var activePanelTab: PanelTab
    var worktreeMonitor: GitWorktreeMonitor?
    var onOpenInTerminal: ((URL) -> Void)?
    var onSwitchToGitTab: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar (hidden during fullscreen preview)
            if !fileBrowserVM.isPreviewFullscreen {
                PanelTabBar(activePanelTab: $activePanelTab, gitPanelVM: gitPanelVM, fileBrowserVM: fileBrowserVM)
                Divider()
            }

            // Content
            switch activePanelTab {
            case .files:
                FileBrowserPanel(
                    viewModel: fileBrowserVM,
                    onOpenInTerminal: onOpenInTerminal,
                    worktreeMonitor: worktreeMonitor,
                    onSwitchToGitTab: {
                        if fileBrowserVM.isPreviewFullscreen {
                            fileBrowserVM.togglePreviewFullscreen()
                        }
                        activePanelTab = .git
                    }
                )
            case .git:
                GitPanelView(
                    vm: gitPanelVM,
                    fileBrowserVM: fileBrowserVM,
                    worktreeMonitor: worktreeMonitor,
                    onSwitchToFilesTab: {
                        activePanelTab = .files
                    }
                )
            }
        }
    }
}

// MARK: - Panel Tab Bar

private struct PanelTabBar: View {
    @Binding var activePanelTab: PanelTab
    @ObservedObject var gitPanelVM: GitPanelViewModel
    @ObservedObject var fileBrowserVM: FileBrowserViewModel

    var body: some View {
        HStack(spacing: 0) {
            tabButton(icon: "folder",                tab: .files, badge: nil)
            tabButton(icon: "arrow.triangle.branch", tab: .git,
                      badge: gitPanelVM.changedCount > 0 ? gitPanelVM.changedCount : nil)
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
}
