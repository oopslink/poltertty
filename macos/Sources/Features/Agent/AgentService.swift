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
    // let processMonitor = ProcessMonitor()  // Phase 2.4

    // 后续 Phase 填充（声明为可选，Phase 2/5/6 取消注释）
    var hookServer: Any? = nil
    var respawnController: Any? = nil
    var tokenTracker: Any? = nil

    private init() {}

    func start() {
        Self.logger.info("AgentService starting")
        // Phase 2: hookServer = HookServer(sessionManager: sessionManager); hookServer?.start()
        Self.logger.info("AgentService started")
    }

    func cleanupForWorkspace(id: UUID) {
        sessionManager.removeAll(for: id)
        Self.logger.info("Cleaned up sessions for workspace \(id)")
    }

    func shutdown() {
        Self.logger.info("AgentService shutting down")
        // Phase 2: hookServer?.stop()
    }

    func injectHooks(for cwd: String) {
        // Phase 2: guard let port = hookServer?.port, port > 0 else { return }
        // HookInjector.inject(cwd: cwd, port: port)
    }

    func cleanupHooks(for cwd: String) {
        // Phase 2: HookInjector.cleanup(cwd: cwd)
    }

    func watchProcess(pid: Int32, surfaceId: UUID) {
        // Phase 2.4: processMonitor.watch(pid: pid, surfaceId: surfaceId) { [weak self] sid, exitCode in
        //     self?.sessionManager.updateState(.done(exitCode: exitCode), surfaceId: sid)
        // }
    }
}
