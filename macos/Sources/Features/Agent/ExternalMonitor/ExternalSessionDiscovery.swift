// macos/Sources/Features/Agent/ExternalMonitor/ExternalSessionDiscovery.swift
import Foundation
import Combine

@MainActor
final class ExternalSessionDiscovery: ObservableObject {
    @Published private(set) var sessions: [ExternalSessionRecord] = []

    private let workspaceDir: String
    private let providers: [any ExternalAgentProvider]
    private var refreshTimer: Timer?

    init(workspaceRootDir: String) {
        self.workspaceDir = workspaceRootDir
        self.providers = [
            ClaudeSessionProvider(workspaceDir: workspaceRootDir),
            OpenCodeSessionProvider(workspaceDir: workspaceRootDir),
            GeminiSessionProvider(workspaceDir: workspaceRootDir),
        ]
    }

    func start() {
        providers.forEach { p in
            p.startWatching { [weak self] in self?.refresh() }
        }
        refresh()
        // 30s 兜底刷新（isAlive 状态同步 + 防止 FSEvents 遗漏）
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func stop() {
        providers.forEach { $0.stopWatching() }
        refreshTimer?.invalidate()
        refreshTimer = nil
        // 注意：此处不清空 sessions，因为 stop() 可能在 deinit 路径上被非主线程调用
    }

    deinit {
        refreshTimer?.invalidate()
    }

    private func refresh() {
        sessions = providers.flatMap { $0.currentSessions() }
    }
}
