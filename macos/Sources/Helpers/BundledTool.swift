// macos/Sources/Helpers/BundledTool.swift
import Foundation

/// Bundled binary paths for yazi, ya, and delta.
/// These binaries are packaged in Poltertty.app/Contents/Resources/bin/
enum BundledTool {
    static let binDir: URL = {
        guard let resourceURL = Bundle.main.resourceURL else {
            fatalError("BundledTool: Bundle.main.resourceURL is nil — app bundle is malformed")
        }
        return resourceURL.appendingPathComponent("bin")
    }()

    static let yaziConfigDir: String = {
        guard let resourceURL = Bundle.main.resourceURL else {
            fatalError("BundledTool: Bundle.main.resourceURL is nil — app bundle is malformed")
        }
        return resourceURL.appendingPathComponent("yazi-config").path
    }()

    static let yaziPath: String = binDir.appendingPathComponent("yazi").path
    static let yaPath: String = binDir.appendingPathComponent("ya").path
    static let deltaPath: String = binDir.appendingPathComponent("delta").path
    static let lazygitPath: String = binDir.appendingPathComponent("lazygit").path
    static let polterttyOpenPath: String = binDir.appendingPathComponent("poltertty-open").path

    /// PATH environment variable with bundled bin dir prepended
    static let pathWithBundledBin: String = binDir.path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
}
