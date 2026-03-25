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
            SharedPanelNavBar(
                fileBrowserVM: fileBrowserVM,
                gitPanelVM: gitPanelVM,
                worktreeMonitor: worktreeMonitor
            )
            Divider()

            // Tab 切换栏（全屏预览时隐藏）
            if !fileBrowserVM.isPreviewFullscreen {
                PanelTabBar(activePanelTab: $activePanelTab, gitPanelVM: gitPanelVM)
                Divider()
            }

            // 内容区
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
                GitPanelView(vm: gitPanelVM)
            }
        }
    }
}

// MARK: - Shared Panel Nav Bar

private struct SharedPanelNavBar: View {
    @ObservedObject var fileBrowserVM: FileBrowserViewModel
    @ObservedObject var gitPanelVM: GitPanelViewModel
    var worktreeMonitor: GitWorktreeMonitor?

    var body: some View {
        let effectivePath = fileBrowserVM.effectiveRootDir
        let worktrees = worktreeMonitor?.worktrees ?? []
        let currentWT = worktrees.first {
            URL(fileURLWithPath: $0.path).standardized.path
                == URL(fileURLWithPath: effectivePath).standardized.path
        }
        let branchLabel = gitPanelVM.branch
            ?? currentDisplayLabel(for: currentWT, fallback: effectivePath)

        HStack(spacing: 4) {
            // 返回主仓库按钮（仅在 worktree 内显示）
            if fileBrowserVM.overrideRootDir != nil {
                Button {
                    fileBrowserVM.switchRoot(to: nil)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Main")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Go to main repo root")

                Text("·")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if worktrees.isEmpty {
                // 无 worktree 信息时只显示分支名（不可点击）
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10))
                    Text(branchLabel)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                .foregroundColor(.secondary)
            } else {
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
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10))
                        Text(branchLabel)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Switch worktree")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    private func currentDisplayLabel(for wt: GitWorktree?, fallback: String) -> String {
        guard let wt else { return URL(fileURLWithPath: fallback).lastPathComponent }
        if wt.isMain { return "Main" }
        return wt.branch ?? wt.path
    }
}

// MARK: - Panel Tab Bar

private struct PanelTabBar: View {
    @Binding var activePanelTab: PanelTab
    @ObservedObject var gitPanelVM: GitPanelViewModel

    var body: some View {
        HStack(spacing: 0) {
            tabButton(icon: "folder",                tab: .files, badge: nil)
            tabButton(icon: "arrow.triangle.branch", tab: .git,
                      badge: gitPanelVM.changedCount > 0 ? gitPanelVM.changedCount : nil)
            Spacer()
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
                    .foregroundColor(activePanelTab == tab ? .primary : .secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        activePanelTab == tab
                            ? Color(nsColor: .controlAccentColor).opacity(0.15)
                            : Color.clear
                    )
                    .cornerRadius(5)

                if let count = badge {
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(.system(size: 8, weight: .bold))
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
    }
}
