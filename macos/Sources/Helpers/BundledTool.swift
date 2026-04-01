// macos/Sources/Helpers/BundledTool.swift
import Foundation

/// Bundled binary paths for yazi, ya, and delta.
/// These binaries are packaged in Poltertty.app/Contents/Resources/bin/
enum BundledTool {
    static var binDir: URL {
        Bundle.main.resourceURL!.appendingPathComponent("bin")
    }

    static var yaziPath: String {
        binDir.appendingPathComponent("yazi").path
    }

    static var yaPath: String {
        binDir.appendingPathComponent("ya").path
    }

    static var deltaPath: String {
        binDir.appendingPathComponent("delta").path
    }

    static var yaziConfigDir: String {
        Bundle.main.resourceURL!.appendingPathComponent("yazi-config").path
    }

    static var polterttyOpenPath: String {
        binDir.appendingPathComponent("poltertty-open").path
    }

    /// PATH environment variable with bundled bin dir prepended
    static var pathWithBundledBin: String {
        binDir.path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
    }
}
