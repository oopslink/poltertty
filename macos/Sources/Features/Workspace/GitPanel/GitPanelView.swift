// macos/Sources/Features/Workspace/GitPanel/GitPanelView.swift
import SwiftUI

struct GitPanelView: View {
    @ObservedObject var vm: GitPanelViewModel
    @ObservedObject var fileBrowserVM: FileBrowserViewModel
    var onSwitchToFilesTab: (() -> Void)?

    @FocusState private var isFocused: Bool

    var body: some View {
        gitPanelContent
            .focusable()
            .focused($isFocused)
            .onAppear {
                // 面板出现（含 Tab 切换）时自动获取焦点，确保快捷键立即可用
                DispatchQueue.main.async { isFocused = true }
            }
            .backport.onKeyPress("f")                   { handleFKey(modifiers: $0) }
            .backport.onKeyPress(KeyEquivalent.upArrow)  { _ in handleChangeNav(delta: -1) }
            .backport.onKeyPress(KeyEquivalent.downArrow){ _ in handleChangeNav(delta: 1) }
            .backport.onKeyPress(KeyEquivalent.return)   { _ in handleChangeReturn() }
            .backport.onKeyPress("s")                   { handleStageToggle(modifiers: $0) }
    }

    private func handleFKey(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused, !modifiers.contains(.command) else { return .ignored }
        onSwitchToFilesTab?()
        return .handled
    }

    /// 在所有变更文件（staged + unstaged）中上下导航
    private func handleChangeNav(delta: Int) -> BackportKeyPressResult {
        guard isFocused else { return .ignored }
        let all = vm.stagedFiles + vm.unstagedFiles
        guard !all.isEmpty else { return .ignored }
        if let current = vm.selectedChangeId,
           let idx = all.firstIndex(where: { $0.id == current }) {
            let next = max(0, min(all.count - 1, idx + delta))
            vm.selectedChangeId = all[next].id
        } else {
            vm.selectedChangeId = delta >= 0 ? all.first?.id : all.last?.id
        }
        return .handled
    }

    /// Return：查看选中文件的 diff
    private func handleChangeReturn() -> BackportKeyPressResult {
        guard isFocused, let id = vm.selectedChangeId else { return .ignored }
        let all = vm.stagedFiles + vm.unstagedFiles
        guard let change = all.first(where: { $0.id == id }) else { return .ignored }
        Task { await vm.selectChange(change) }
        return .handled
    }

    /// S：暂存 / 取消暂存选中文件
    private func handleStageToggle(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused, modifiers.isEmpty,
              let id = vm.selectedChangeId else { return .ignored }
        if let change = vm.stagedFiles.first(where: { $0.id == id }) {
            Task { await vm.unstage(change) }
            return .handled
        }
        if let change = vm.unstagedFiles.first(where: { $0.id == id }) {
            Task { await vm.stage(change) }
            return .handled
        }
        return .ignored
    }

    @ViewBuilder
    private var gitPanelContent: some View {
        if !vm.isGitRepo {
            VStack(spacing: 0) {
                Spacer()
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary.opacity(0.5))
                Text("Not a git repository")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                if !vm.lastAttemptedDir.isEmpty {
                    Text(vm.lastAttemptedDir.replacingOccurrences(
                        of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                }
                Text("Run `git init` in the terminal to initialize a repository,\nor open a directory that already contains one.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HSplitView {
                // Left: Changes + Commits
                VStack(spacing: 0) {
                    // Error
                    if let err = vm.error {
                        Text(err)
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
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

                // Right: Diff 浮窗面板
                diffPanel
            }
        }
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
                .foregroundStyle(.secondary)

            if let diff = vm.selectedDiff {
                Text(URL(fileURLWithPath: diff.path).lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(diff.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            } else {
                Text("Diff")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Maximize / Restore button
            if vm.selectedDiff != nil {
                Button(action: {
                    let newValue = !vm.isDiffMaximized
                    vm.isDiffMaximized = newValue
                    fileBrowserVM.isPreviewFullscreen = newValue
                }) {
                    Image(systemName: vm.isDiffMaximized
                          ? "arrow.down.right.and.arrow.up.left"
                          : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(vm.isDiffMaximized ? "Restore Layout (Esc)" : "Maximize Diff Panel")

                // Close button
                Button(action: {
                    vm.closeDiff()
                    fileBrowserVM.isPreviewFullscreen = false
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close Diff")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(
            // Esc key to restore fullscreen
            Group {
                if vm.isDiffMaximized {
                    Button("") {
                        vm.isDiffMaximized = false
                        fileBrowserVM.isPreviewFullscreen = false
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    .opacity(0)
                    .frame(width: 0, height: 0)
                }
            }
        )
    }
}
