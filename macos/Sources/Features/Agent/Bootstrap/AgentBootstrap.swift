// macos/Sources/Features/Agent/Bootstrap/AgentBootstrap.swift
import Foundation
import OSLog

/// App 启动时将 wrapper、shell integration 脚本部署到 ~/.poltertty/
enum AgentBootstrap {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "AgentBootstrap"
    )

    /// 支持的 agent 名称（每个都会创建 symlink → poltertty-agent-wrapper）
    private static let supportedAgents = ["claude"]

    private static var polterttyHome: String {
        "\(NSHomeDirectory())/.poltertty"
    }

    private static var binDir: String { "\(polterttyHome)/bin" }
    private static var shellDir: String { "\(polterttyHome)/shell" }

    // MARK: - Public

    /// 一次性部署所有资源；幂等，可多次调用
    static func deploy() {
        logger.info("AgentBootstrap deploy started")
        do {
            try createDirectories()
            try deployWrapper()
            try deployShellIntegration()
            // TODO: poltertty-cli 的部署（需要等 Task 8 的 Xcode target 配置）
            logger.info("AgentBootstrap deploy completed")
        } catch {
            logger.error("AgentBootstrap deploy failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private static func createDirectories() throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: shellDir, withIntermediateDirectories: true)
        logger.debug("Directories ensured: bin/, shell/")
    }

    /// 从 App bundle 复制 poltertty-agent-wrapper 并为每个 agent 创建 symlink
    private static func deployWrapper() throws {
        guard let srcPath = Bundle.main.path(forResource: "poltertty-agent-wrapper", ofType: nil) else {
            logger.warning("poltertty-agent-wrapper not found in app bundle, skipping wrapper deploy")
            return
        }

        let dstPath = "\(binDir)/poltertty-agent-wrapper"
        let fm = FileManager.default

        // 复制（覆盖已有文件）
        if fm.fileExists(atPath: dstPath) {
            try fm.removeItem(atPath: dstPath)
        }
        try fm.copyItem(atPath: srcPath, toPath: dstPath)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dstPath)
        logger.info("Deployed poltertty-agent-wrapper to \(dstPath)")

        // 为每个支持的 agent 创建 symlink
        for agent in supportedAgents {
            let linkPath = "\(binDir)/\(agent)"
            if fm.fileExists(atPath: linkPath) || (try? fm.attributesOfItem(atPath: linkPath)) != nil {
                try? fm.removeItem(atPath: linkPath)
            }
            try fm.createSymbolicLink(atPath: linkPath, withDestinationPath: "poltertty-agent-wrapper")
            logger.info("Created symlink \(agent) → poltertty-agent-wrapper")
        }
    }

    /// 从 App bundle 复制 shell integration 脚本
    private static func deployShellIntegration() throws {
        let scripts = ["poltertty.zsh", "poltertty.bash", "poltertty.fish"]
        let fm = FileManager.default

        for script in scripts {
            guard let srcPath = Bundle.main.path(forResource: script, ofType: nil) else {
                logger.debug("Shell script \(script) not found in app bundle, skipping")
                continue
            }

            let dstPath = "\(shellDir)/\(script)"
            if fm.fileExists(atPath: dstPath) {
                try fm.removeItem(atPath: dstPath)
            }
            try fm.copyItem(atPath: srcPath, toPath: dstPath)
            logger.info("Deployed shell script \(script)")
        }
    }
}
