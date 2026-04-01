// macos/Sources/Features/Workspace/Yazi/YaziSurfaceStore.swift
import Foundation

/// Manages one yazi terminal surface per workspace.
/// Surfaces are lazily created on first panel open and kept alive
/// until the workspace is deleted.
class YaziSurfaceStore: ObservableObject {
    @Published private(set) var surfaces: [UUID: Ghostty.SurfaceView] = [:]

    /// Get or create the yazi surface for a workspace.
    /// - Parameters:
    ///   - workspaceId: The workspace UUID
    ///   - app: The Ghostty app instance for creating surfaces
    ///   - rootDir: The workspace root directory (expanded path)
    /// - Returns: The existing or newly created SurfaceView running yazi
    @MainActor
    func surface(for workspaceId: UUID, app: ghostty_app_t, rootDir: String) -> Ghostty.SurfaceView {
        if let existing = surfaces[workspaceId] {
            return existing
        }

        var config = Ghostty.SurfaceConfiguration()
        config.command = BundledTool.yaziPath
        config.workingDirectory = rootDir
        config.environmentVariables = [
            "YAZI_CONFIG_HOME": BundledTool.yaziConfigDir,
            "YAZI_DELTA_PATH": BundledTool.deltaPath,
            "PATH": BundledTool.pathWithBundledBin,
        ]

        let surface = Ghostty.SurfaceView(app, baseConfig: config)
        surfaces[workspaceId] = surface
        return surface
    }

    /// Remove and destroy the yazi surface for a workspace.
    /// Called when a workspace is deleted.
    func removeSurface(for workspaceId: UUID) {
        surfaces.removeValue(forKey: workspaceId)
        // SurfaceView.deinit calls ghostty_surface_free automatically
    }

    /// Notify yazi to change directory via ya pub-sub IPC.
    /// Uses a separate Process instead of sendText to avoid
    /// interfering with yazi's TUI input.
    func cdToDirectory(_ workspaceId: UUID, path: String) {
        guard surfaces[workspaceId] != nil else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: BundledTool.yaPath)
        task.arguments = ["pub", "dds-cd", "--str", path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    /// Check if a surface exists for the given workspace.
    func hasSurface(for workspaceId: UUID) -> Bool {
        surfaces[workspaceId] != nil
    }
}
