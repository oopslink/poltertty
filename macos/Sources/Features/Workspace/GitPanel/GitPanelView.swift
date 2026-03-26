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
                // Left: Changes + Commits（最大化时隐藏）
                if !vm.isDiffFullscreen {
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
                }

                // Right: Diff 浮窗面板
                diffPanel
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

    // MARK: - Diff 浮窗面板

    private var diffPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header：标题 + 最大化 + 关闭
            diffPanelHeader
            Divider()
            // Diff 内容
            DiffView(diff: vm.selectedDiff, title: nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .frame(minWidth: 300)
    }

    private var diffPanelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            if let diff = vm.selectedDiff {
                Text(URL(fileURLWithPath: diff.path).lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(diff.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            } else {
                Text("Diff")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 最大化 / 还原按钮
            if vm.selectedDiff != nil {
                Button(action: { vm.isDiffFullscreen.toggle() }) {
                    Image(systemName: vm.isDiffFullscreen
                          ? "arrow.down.right.and.arrow.up.left"
                          : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(vm.isDiffFullscreen ? "还原布局 (Esc)" : "最大化 Diff 面板")

                // 关闭按钮
                Button(action: { vm.closeDiff() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("关闭 Diff")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(
            // Esc 键还原全屏
            Group {
                if vm.isDiffFullscreen {
                    Button("") { vm.isDiffFullscreen = false }
                        .keyboardShortcut(.escape, modifiers: [])
                        .opacity(0)
                        .frame(width: 0, height: 0)
                }
            }
        )
    }
}
