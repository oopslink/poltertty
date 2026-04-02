// macos/Sources/Features/Workspace/Yazi/YaziPanelView.swift
import SwiftUI

struct YaziPanelView: View {
    let workspaceId: UUID?
    let ghostty: Ghostty.App
    @ObservedObject var yaziStore: YaziSurfaceStore
    var rootDir: String
    var worktreeMonitor: GitWorktreeMonitor?
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            YaziPanelToolbar(
                yaziStore: yaziStore,
                workspaceId: workspaceId,
                worktreeMonitor: worktreeMonitor,
                currentRootDir: rootDir,
                onClose: onClose
            )
            Divider()

            if let wsId = workspaceId,
               let surface = yaziStore.surface(for: wsId, ghostty: ghostty, rootDir: rootDir) {
                Ghostty.SurfaceWrapper(surfaceView: surface)
                    .environmentObject(ghostty)
            } else {
                noWorkspaceView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var noWorkspaceView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "folder")
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No workspace selected")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
