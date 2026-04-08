// macos/Sources/Features/Workspace/Yazi/YaziPanelView.swift
import SwiftUI

struct LeftPanelView: View {
    let workspaceId: UUID?
    let ghostty: Ghostty.App
    @ObservedObject var yaziStore: YaziSurfaceStore
    @ObservedObject var lazygitStore: LazyGitSurfaceStore
    var rootDir: String
    var worktreeMonitor: GitWorktreeMonitor?
    var isExpanded: Bool = false
    var currentTool: LeftPanelTool
    var onSwitchTool: (LeftPanelTool) -> Void
    var onToggleExpand: () -> Void = {}
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LeftPanelToolbar(
                yaziStore: yaziStore,
                workspaceId: workspaceId,
                worktreeMonitor: worktreeMonitor,
                currentRootDir: rootDir,
                isExpanded: isExpanded,
                currentTool: currentTool,
                onSwitchTool: onSwitchTool,
                onToggleExpand: onToggleExpand,
                onClose: onClose
            )
            Divider()

            switch currentTool {
            case .yazi:
                yaziContent
            case .lazygit:
                lazygitContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var yaziContent: some View {
        if let wsId = workspaceId,
           let surface = yaziStore.surface(for: wsId, ghostty: ghostty, rootDir: rootDir) {
            Ghostty.SurfaceWrapper(surfaceView: surface)
                .environmentObject(ghostty)
                .id(ObjectIdentifier(surface))
        } else {
            emptyView(icon: "folder", label: "No workspace selected")
        }
    }

    @ViewBuilder
    private var lazygitContent: some View {
        if let wsId = workspaceId,
           let surface = lazygitStore.surface(for: wsId, ghostty: ghostty, rootDir: rootDir) {
            Ghostty.SurfaceWrapper(surfaceView: surface)
                .environmentObject(ghostty)
                .id(ObjectIdentifier(surface))
        } else {
            emptyView(icon: "arrow.triangle.branch", label: "No workspace selected")
        }
    }

    private func emptyView(icon: String, label: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.4))
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
