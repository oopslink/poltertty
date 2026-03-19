// macos/Sources/Features/Agent/ExternalMonitor/GeminiSessionProvider.swift
import Foundation

/// Gemini CLI 当前未安装；保留 init(workspaceDir:) 以保持接口一致
@MainActor
final class GeminiSessionProvider: ExternalAgentProvider {
    let toolType: ExternalToolType = .geminiCli
    init(workspaceDir: String) {}
    func currentSessions() -> [ExternalSessionRecord] { [] }
    func startWatching(onChange: @escaping @MainActor () -> Void) {}
    func stopWatching() {}
}
