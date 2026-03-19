// macos/Sources/Features/Agent/AgentService.swift
import Foundation
import OSLog

@MainActor
final class AgentService {
    static let shared = AgentService()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "AgentService"
    )

    let registry = AgentRegistry.shared
    let sessionManager = AgentSessionManager()
    let processMonitor = ProcessMonitor()

    // 后续 Phase 填充（声明为可选，Phase 2/5/6 取消注释）
    var hookServer: HookServer? = nil
    var tokenTracker: TokenTracker? = nil

    private init() {}

    func start() {
        Self.logger.info("AgentService starting")
        hookServer = HookServer(sessionManager: sessionManager)
        hookServer?.start()
        tokenTracker = TokenTracker(sessionManager: sessionManager)
        Self.logger.info("AgentService started")
    }

    func cleanupForWorkspace(id: UUID) {
        let cwds = sessionManager.sessions.values
            .filter { $0.workspaceId == id }
            .map { $0.cwd }
        sessionManager.removeAll(for: id)
        cwds.forEach { cleanupHooks(for: $0) }
        Self.logger.info("Cleaned up sessions and hooks for workspace \(id)")
    }

    func shutdown() {
        Self.logger.info("AgentService shutting down")
        hookServer?.stop()
    }

    func injectHooks(for cwd: String) {
        guard let port = hookServer?.port, port > 0 else { return }
        HookInjector.inject(cwd: cwd, port: port)
    }

    func cleanupHooks(for cwd: String) {
        HookInjector.cleanup(cwd: cwd)
    }

    func watchProcess(pid: Int32, surfaceId: UUID) {
        processMonitor.watch(pid: pid, surfaceId: surfaceId) { [weak self] sid, exitCode in
            self?.sessionManager.updateState(.done(exitCode: exitCode), surfaceId: sid)
        }
    }
}

// MARK: - 通知名

extension Notification.Name {
    /// 向指定 surface 的 PTY 写入文本
    static let agentWriteToSurface = Notification.Name("AgentWriteToSurface")
}
