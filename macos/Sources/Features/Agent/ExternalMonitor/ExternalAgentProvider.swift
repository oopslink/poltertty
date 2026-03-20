// macos/Sources/Features/Agent/ExternalMonitor/ExternalAgentProvider.swift
import Foundation

@MainActor
protocol ExternalAgentProvider: AnyObject {
    var toolType: ExternalToolType { get }
    func currentSessions() -> [ExternalSessionRecord]
    func startWatching(onChange: @escaping @MainActor () -> Void)
    func stopWatching()
}
