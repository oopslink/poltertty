// macos/Sources/Features/Agent/Respawn/RespawnController.swift
import Foundation
import OSLog

@MainActor
final class RespawnController {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "RespawnController"
    )

    struct CircuitBreaker {
        var noProgressCount: Int = 0
        var isOpen: Bool = false      // ≥5 次无进展，停止 respawn
        var isHalfOpen: Bool = false  // ≥3 次无进展，降低频率

        mutating func record(hadToolUse: Bool) {
            if hadToolUse {
                noProgressCount = 0; isHalfOpen = false; isOpen = false
            } else {
                noProgressCount += 1
                if noProgressCount >= 5 { isOpen = true }
                else if noProgressCount >= 3 { isHalfOpen = true }
            }
        }

        mutating func reset() { noProgressCount = 0; isOpen = false; isHalfOpen = false }
    }

    private var breakers: [UUID: CircuitBreaker] = [:]
    private var hadToolUse: [UUID: Bool] = [:]      // 两次 idle 之间是否有 toolUse
    private let sessionManager: AgentSessionManager

    init(sessionManager: AgentSessionManager) {
        self.sessionManager = sessionManager
    }

    func recordToolUse(surfaceId: UUID) {
        hadToolUse[surfaceId] = true
    }

    func handleIdle(surfaceId: UUID) {
        guard let session = sessionManager.session(for: surfaceId),
              let threshold = session.respawnMode.config.idleThresholdSeconds else { return }

        var breaker = breakers[surfaceId] ?? CircuitBreaker()
        breaker.record(hadToolUse: hadToolUse[surfaceId] ?? false)
        hadToolUse[surfaceId] = false
        breakers[surfaceId] = breaker

        if breaker.isOpen {
            Self.logger.warning("Circuit breaker OPEN for surface \(surfaceId)")
            postUserNotification(surfaceId: surfaceId)
            return
        }

        let delay = breaker.isHalfOpen ? 30.0 : threshold
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run { self.sendContinue(surfaceId: surfaceId) }
        }
    }

    func resetBreaker(surfaceId: UUID) {
        breakers[surfaceId]?.reset()
    }

    // MARK: - PTY 写入（通过 Notification 发给 TerminalController）

    private func sendContinue(surfaceId: UUID) {
        postWrite(surfaceId: surfaceId, text: "\n")
        Self.logger.info("RespawnController: sent continue to \(surfaceId)")
    }

    func sendCompact(surfaceId: UUID) { postWrite(surfaceId: surfaceId, text: "/compact\n") }
    func sendClear(surfaceId: UUID)   { postWrite(surfaceId: surfaceId, text: "/clear\n/init\n") }

    private func postWrite(surfaceId: UUID, text: String) {
        NotificationCenter.default.post(
            name: .agentWriteToSurface,
            object: nil,
            userInfo: ["surfaceId": surfaceId, "text": text]
        )
    }

    private func postUserNotification(surfaceId: UUID) {
        // TODO: UNUserNotificationCenter 发系统通知
    }
}

extension Notification.Name {
    static let agentWriteToSurface = Notification.Name("AgentWriteToSurface")
}
