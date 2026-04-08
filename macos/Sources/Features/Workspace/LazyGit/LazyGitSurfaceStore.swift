// macos/Sources/Features/Workspace/LazyGit/LazyGitSurfaceStore.swift
import Foundation

/// Manages one lazygit terminal surface per workspace.
/// Surfaces are lazily created on first panel open and kept alive
/// until the workspace is deleted or the process exits.
class LazyGitSurfaceStore: ObservableObject {
    @Published private(set) var surfaces: [UUID: Ghostty.SurfaceView] = [:]
    private var exitObservers: [UUID: any NSObjectProtocol] = [:]

    // MARK: - Surface management

    /// Get or create the lazygit surface for a workspace.
    @MainActor
    func surface(for workspaceId: UUID, ghostty: Ghostty.App, rootDir: String) -> Ghostty.SurfaceView? {
        if let existing = surfaces[workspaceId] {
            return existing
        }

        guard let app = ghostty.app else { return nil }

        var config = Ghostty.SurfaceConfiguration()
        config.command = BundledTool.lazygitPath
        config.workingDirectory = rootDir
        config.environmentVariables = ["PATH": BundledTool.pathWithBundledBin]

        let surface = Ghostty.SurfaceView(app, baseConfig: config)
        surfaces[workspaceId] = surface
        observeExit(surface: surface, workspaceId: workspaceId)
        return surface
    }

    /// Remove and destroy the lazygit surface for a workspace.
    func removeSurface(for workspaceId: UUID) {
        if let token = exitObservers.removeValue(forKey: workspaceId) {
            NotificationCenter.default.removeObserver(token)
        }
        surfaces.removeValue(forKey: workspaceId)
    }

    func hasSurface(for workspaceId: UUID) -> Bool {
        surfaces[workspaceId] != nil
    }

    // MARK: - Exit observation

    private func observeExit(surface: Ghostty.SurfaceView, workspaceId: UUID) {
        let token = NotificationCenter.default.addObserver(
            forName: Ghostty.Notification.ghosttyCloseSurface,
            object: surface,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let processAlive = notification.userInfo?["process_alive"] as? Bool ?? false
            guard !processAlive else { return }
            if let token = self.exitObservers.removeValue(forKey: workspaceId) {
                NotificationCenter.default.removeObserver(token)
            }
            self.surfaces.removeValue(forKey: workspaceId)
        }
        exitObservers[workspaceId] = token
    }
}
