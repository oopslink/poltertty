// macos/Sources/Features/Agent/ExternalMonitor/ExternalSessionDiscovery.swift
import Foundation
import Combine

@MainActor
final class ExternalSessionDiscovery: ObservableObject {
    @Published private(set) var sessions: [ExternalSessionRecord] = []

    private let workspaceDir: String
    private let workspaceId: UUID?
    private let providers: [any ExternalAgentProvider]
    private var refreshTimer: Timer?
    private var isFirstRefresh = true

    init(workspaceRootDir: String, workspaceId: UUID? = nil) {
        self.workspaceDir = workspaceRootDir
        self.workspaceId = workspaceId
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
        let newSessions = providers.flatMap { $0.currentSessions() }
        let oldMap = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })

        // Delta 检测：生成通知（首次启动跳过，避免对已有会话误报）
        if !isFirstRefresh, let wsId = workspaceId {
            for newRecord in newSessions {
                if let oldRecord = oldMap[newRecord.id] {
                    // 已有会话：检测 isAlive 变化
                    if oldRecord.isAlive && !newRecord.isAlive {
                        emitNotification(
                            workspaceId: wsId, record: newRecord,
                            type: .done,
                            title: "\(newRecord.toolType.badge) 会话结束"
                        )
                    }
                }
            }
        }
        isFirstRefresh = false

        sessions = newSessions
    }

    private func emitNotification(
        workspaceId: UUID,
        record: ExternalSessionRecord,
        type: AgentNotificationType,
        title: String
    ) {
        AgentNotificationStore.shared.insert(AgentNotification(
            id: UUID(),
            timestamp: Date(),
            workspaceId: workspaceId,
            surfaceId: nil,
            agentDefinitionId: record.toolType.rawValue,
            sessionId: record.id,
            type: type,
            title: title,
            body: record.lastMessage?.text.prefix(100).description,
            priority: type == .error ? .high : .normal
        ))
    }
}
