// macos/Sources/Features/Workspace/Yazi/YaziSurfaceStore.swift
import Foundation

/// Manages one yazi terminal surface per workspace.
/// Surfaces are lazily created on first panel open and kept alive
/// until the workspace is deleted.
class YaziSurfaceStore: ObservableObject {
    @Published private(set) var surfaces: [UUID: Ghostty.SurfaceView] = [:]
    @Published private(set) var ratioIndices: [UUID: Int] = [:]

    // MARK: - Ratio presets [parent, current, preview]

    static let ratioPresets: [(label: String, ratio: [Int])] = [
        (label: "Preview", ratio: [0, 1, 3]),
        (label: "Focus",   ratio: [0, 1, 0]),
    ]

    func ratioLabel(for workspaceId: UUID) -> String {
        let idx = ratioIndices[workspaceId] ?? 0
        return Self.ratioPresets[idx].label
    }

    @MainActor
    func cycleRatio(for workspaceId: UUID) {
        let next = ((ratioIndices[workspaceId] ?? 0) + 1) % Self.ratioPresets.count
        ratioIndices[workspaceId] = next
        surfaces.removeValue(forKey: workspaceId)   // triggers lazy re-creation
    }

    // MARK: - Surface management

    /// Get or create the yazi surface for a workspace.
    @MainActor
    func surface(for workspaceId: UUID, ghostty: Ghostty.App, rootDir: String) -> Ghostty.SurfaceView? {
        if let existing = surfaces[workspaceId] {
            return existing
        }

        guard let app = ghostty.app else { return nil }

        let ratioIdx = ratioIndices[workspaceId] ?? 0
        let ratio = Self.ratioPresets[ratioIdx].ratio

        var config = Ghostty.SurfaceConfiguration()
        config.command = BundledTool.yaziPath
        config.workingDirectory = rootDir
        config.environmentVariables = [
            "YAZI_CONFIG_HOME": Self.configDir(for: ratio),
            "YAZI_DELTA_PATH": BundledTool.deltaPath,
            "PATH": BundledTool.pathWithBundledBin,
            "YAZI_ROOT_DIR": rootDir,
            // init.lua 用此值将 YAZI_ID 写入临时文件，供 cdToDirectory 读取
            "POLTERTTY_WS_ID": workspaceId.uuidString,
        ]

        let surface = Ghostty.SurfaceView(app, baseConfig: config)
        surfaces[workspaceId] = surface
        return surface
    }

    /// Remove and destroy the yazi surface for a workspace.
    func removeSurface(for workspaceId: UUID) {
        surfaces.removeValue(forKey: workspaceId)
    }

    /// 通知 yazi 切换到指定目录。
    /// 通过 `ya emit-to <YAZI_ID> cd <path>` 精准定位目标实例。
    /// YAZI_ID 由 init.lua 在 yazi 启动时写入 /tmp/poltertty-yazi-<wsId>.id。
    func cdToDirectory(_ workspaceId: UUID, path: String) {
        guard surfaces[workspaceId] != nil else { return }

        let idFile = "/tmp/poltertty-yazi-\(workspaceId.uuidString).id"
        guard let yaziId = try? String(contentsOfFile: idFile, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !yaziId.isEmpty else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: BundledTool.yaPath)
        task.arguments = ["emit-to", yaziId, "cd", path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    func hasSurface(for workspaceId: UUID) -> Bool {
        surfaces[workspaceId] != nil
    }

    // MARK: - Config dir generation

    /// Returns a config dir for the given ratio, creating it on first use.
    /// Uses symlinks to share keymap/theme/plugins from the bundled config.
    private static func configDir(for ratio: [Int]) -> String {
        let key = ratio.map(String.init).joined(separator: "-")
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("poltertty-yazi-\(key)")
        let bundled = URL(fileURLWithPath: BundledTool.yaziConfigDir)
        let destToml = dest.appendingPathComponent("yazi.toml")

        // Always (re)write yazi.toml so stale temp dirs from previous sessions
        // don't get stuck with the wrong ratio.
        guard let bundledToml = try? String(contentsOf: bundled.appendingPathComponent("yazi.toml"), encoding: .utf8) else {
            return BundledTool.yaziConfigDir
        }

        let ratioLine = "ratio = [\(ratio.map(String.init).joined(separator: ", "))]"
        let patched: String
        if bundledToml.range(of: #"ratio = \[.*?\]"#, options: .regularExpression) != nil {
            patched = bundledToml.replacingOccurrences(
                of: #"ratio = \[.*?\]"#, with: ratioLine, options: .regularExpression)
        } else {
            patched = bundledToml.replacingOccurrences(
                of: "[mgr]", with: "[mgr]\n\(ratioLine)")
        }

        do {
            if !FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            }
            // 始终更新软链接（确保新增文件如 init.lua 在已有目录中也能同步）
            for name in ["keymap.toml", "theme.toml", "plugins", "init.lua"] {
                let src = bundled.appendingPathComponent(name)
                let dst = dest.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: src.path) {
                    try? FileManager.default.removeItem(at: dst)
                    try FileManager.default.createSymbolicLink(at: dst, withDestinationURL: src)
                }
            }
            try patched.write(to: destToml, atomically: true, encoding: .utf8)
        } catch {
            return BundledTool.yaziConfigDir
        }

        return dest.path
    }
}
