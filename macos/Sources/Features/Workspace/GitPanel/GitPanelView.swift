// macos/Sources/Features/Workspace/GitPanel/GitPanelView.swift
import SwiftUI

struct GitPanelView: View {
    @ObservedObject var vm: GitPanelViewModel
    @ObservedObject var fileBrowserVM: FileBrowserViewModel
    var worktreeMonitor: GitWorktreeMonitor?
    var onSwitchToFilesTab: (() -> Void)?

    @FocusState private var isFocused: Bool

    var body: some View {
        gitPanelContent
            .focusable()
            .focused($isFocused)
            .backport.onKeyPress("f") { handleFKey(modifiers: $0) }
    }

    private func handleFKey(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused, !modifiers.contains(.command) else { return .ignored }
        onSwitchToFilesTab?()
        return .handled
    }

    @ViewBuilder
    private var gitPanelContent: some View {
        if !vm.isGitRepo {
            VStack(spacing: 0) {
                Spacer()
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
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
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HSplitView {
                // Left: Changes + Commits
                VStack(spacing: 0) {
                    // Worktree selector toolbar
                    worktreeToolbar
                    Divider()

                    // Error
                    if let err = vm.error {
                        Text(err)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }

                    ScrollView {
                        VStack(spacing: 0) {
                            GitChangesSection(vm: vm)
                            GitCommitsSection(vm: vm)
                        }
                    }
                }
                .frame(minWidth: 200, maxWidth: 320)

                // Right: Diff
                DiffView(diff: vm.selectedDiff, title: diffTitle)
                    .frame(minWidth: 300)
            }
        }
    }

    // MARK: - Worktree Toolbar

    private var worktreeToolbar: some View {
        let effectivePath = fileBrowserVM.effectiveRootDir
        let worktrees = worktreeMonitor?.worktrees ?? []
        let currentWT = worktrees.first {
            URL(fileURLWithPath: $0.path).standardized.path
                == URL(fileURLWithPath: effectivePath).standardized.path
        }
        let branchLabel = vm.branch
            ?? worktreeDisplayLabel(for: currentWT, fallback: effectivePath)

        return HStack(spacing: 6) {
            // Worktree selector (leftmost)
            if worktrees.isEmpty {
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

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func worktreeDisplayLabel(for wt: GitWorktree?, fallback: String) -> String {
        guard let wt else { return URL(fileURLWithPath: fallback).lastPathComponent }
        if wt.isMain { return "Main" }
        return wt.branch ?? wt.path
    }

    private var diffTitle: String? {
        guard let diff = vm.selectedDiff else { return nil }
        return diff.path
    }
}
