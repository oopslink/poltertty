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
                PanelTabBar(
                    activePanelTab: $activePanelTab,
                    gitPanelVM: gitPanelVM,
                    fileBrowserVM: fileBrowserVM,
                    worktreeMonitor: worktreeMonitor
                )
                Divider()
            }

            // Content
            switch activePanelTab {
            case .files:
                FileBrowserPanel(
                    viewModel: fileBrowserVM,
                    onOpenInTerminal: onOpenInTerminal,
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
    var worktreeMonitor: GitWorktreeMonitor? = nil

    var body: some View {
        HStack(spacing: 0) {
            tabButton(icon: "folder",                tab: .files, badge: nil)
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

    @ViewBuilder
    private func worktreeSelector(monitor: GitWorktreeMonitor) -> some View {
        // 在开头统一标准化路径，避免后续重复创建 URL 对象
        let effectivePath = URL(fileURLWithPath: fileBrowserVM.effectiveRootDir).standardized.path
        let worktrees = monitor.worktrees
        let currentWTPath = worktrees.first {
            URL(fileURLWithPath: $0.path).standardized.path == effectivePath
        }?.path

        let branchLabel: String = {
            if let branch = gitPanelVM.branch { return branch }
            guard let path = currentWTPath,
                  let wt = worktrees.first(where: { $0.path == path }) else {
                return URL(fileURLWithPath: fileBrowserVM.effectiveRootDir).lastPathComponent
            }
            if wt.isMain { return "Main" }
            return wt.branch ?? URL(fileURLWithPath: wt.path).lastPathComponent
        }()

        if worktrees.count > 1 {
            // 单 worktree：无切换选项，仅展示当前分支
            Menu {
                ForEach(worktrees) { wt in
                    let isActive = wt.path == currentWTPath
                    Button {
                        if wt.isMain {
                            fileBrowserVM.switchRoot(to: nil)
                        } else {
                            fileBrowserVM.switchRoot(to: wt.path)
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
                .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Switch Worktree")
        } else {
            // 单 worktree：无切换选项，仅展示当前分支
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
}
