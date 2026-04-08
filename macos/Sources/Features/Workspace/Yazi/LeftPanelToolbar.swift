// macos/Sources/Features/Workspace/Yazi/LeftPanelToolbar.swift
import SwiftUI

enum LeftPanelTool: String, Equatable {
    case yazi
    case lazygit
}

struct LeftPanelToolbar: View {
    @ObservedObject var yaziStore: YaziSurfaceStore
    var workspaceId: UUID?
    var worktreeMonitor: GitWorktreeMonitor?
    var currentRootDir: String
    var isExpanded: Bool = false
    var currentTool: LeftPanelTool
    var onSwitchTool: (LeftPanelTool) -> Void
    var onToggleExpand: () -> Void = {}
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Tool tabs: File Browser | Git
            toolTabButton(tool: .yazi, icon: "folder", help: "File Browser (⌥⌘F)")
            toolTabButton(tool: .lazygit, icon: "arrow.triangle.branch", help: "Git (⌥⌘G)")

            // Worktree selector (shared for both tools)
            if let monitor = worktreeMonitor, !monitor.worktrees.isEmpty {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1, height: 14)
                    .padding(.horizontal, 4)
                worktreeSelector(monitor: monitor)
            }

            Spacer()

            // Expand / collapse button (both tools)
            Button {
                onToggleExpand()
            } label: {
                Image(systemName: isExpanded
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11))
                    .foregroundStyle(isExpanded ? Color(nsColor: .controlAccentColor) : .secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse Panel (⌥⌘O)" : "Expand to Full Width (⌥⌘O)")
            .keyboardShortcut("o", modifiers: [.option, .command])

            // Layout ratio cycle button (Yazi only)
            if currentTool == .yazi {
                Button {
                    if let wsId = workspaceId {
                        yaziStore.cycleRatio(for: wsId)
                    }
                } label: {
                    Image(systemName: layoutIcon)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(layoutHelp + " (⌥⌘L)")
                .keyboardShortcut("l", modifiers: [.option, .command])
            }

            // Close panel button
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Close Panel")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // Note: The keyboard shortcuts shown in help text (⌥⌘F / ⌥⌘G) are handled
    // at the AppDelegate/menu level — informational only.
    private func toolTabButton(tool: LeftPanelTool, icon: String, help: String) -> some View {
        let isActive = currentTool == tool
        Button {
            onSwitchTool(tool)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(isActive ? Color(nsColor: .controlAccentColor) : .secondary)
                .frame(width: 28, height: 28)
                .background(isActive ? Color(nsColor: .controlAccentColor).opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var layoutIcon: String {
        guard let wsId = workspaceId else { return "rectangle.split.2x1" }
        let label = yaziStore.ratioLabel(for: wsId)
        return label == "Preview" ? "rectangle.split.2x1" : "rectangle"
    }

    private var layoutHelp: String {
        guard let wsId = workspaceId else { return "Cycle Layout" }
        let current = yaziStore.ratioLabel(for: wsId)
        let presets = YaziSurfaceStore.ratioPresets
        let currentIdx = presets.firstIndex(where: { $0.label == current }) ?? 0
        let next = presets[(currentIdx + 1) % presets.count].label
        return "Layout: \(current) → \(next)"
    }

    @ViewBuilder
    private func worktreeSelector(monitor: GitWorktreeMonitor) -> some View {
        let effectivePath = URL(fileURLWithPath: currentRootDir).standardized.path
        let worktrees = monitor.worktrees
        let currentWTPath = worktrees.first {
            URL(fileURLWithPath: $0.path).standardized.path == effectivePath
        }?.path

        let branchLabel: String = {
            guard let path = currentWTPath,
                  let wt = worktrees.first(where: { $0.path == path }) else {
                return URL(fileURLWithPath: currentRootDir).lastPathComponent
            }
            if wt.isMain { return "Main" }
            return wt.branch ?? URL(fileURLWithPath: wt.path).lastPathComponent
        }()

        if worktrees.count > 1 {
            Menu {
                ForEach(worktrees) { wt in
                    let isActive = wt.path == currentWTPath
                    Button {
                        let targetPath = wt.isMain
                            ? (worktrees.first(where: { $0.isMain })?.path ?? currentRootDir)
                            : wt.path
                        if let wsId = workspaceId {
                            // Always cd Yazi even when lazygit is active — Yazi tracks
                            // the active directory in background. LazyGit opens in rootDir
                            // at creation time and does not need dynamic cd.
                            yaziStore.cdToDirectory(wsId, path: targetPath)
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
                .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Switch Worktree")
        } else {
            HStack(spacing: 2) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10))
                Text(branchLabel)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
        }
    }
}
