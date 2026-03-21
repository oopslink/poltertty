// macos/Sources/Features/Notification/AgentNotificationStore.swift
import Foundation
import Combine
import OSLog
import UserNotifications

@MainActor
final class AgentNotificationStore: ObservableObject {
    static let shared = AgentNotificationStore()

    @Published private(set) var notifications: [AgentNotification] = []

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "poltertty",
        category: "AgentNotificationStore"
    )

    /// 最近 dedupeWindow 秒内的 (sessionId:type) 组合，用于去重
    private var recentKeys: [(key: String, at: Date)] = []
    private static let dedupeWindow: TimeInterval = 300 // 5 分钟
    private static let maxNotifications = 500

    private init() {
        loadFromDisk()
    }

    // MARK: - 写入

    func insert(_ notification: AgentNotification) {
        // 去重：同一 sessionId + type 在 5 分钟内不重复
        if let sid = notification.sessionId {
            let key = "\(sid):\(notification.type.rawValue)"
            let now = Date()
            recentKeys.removeAll { now.timeIntervalSince($0.at) > Self.dedupeWindow }
            if recentKeys.contains(where: { $0.key == key }) {
                logger.debug("Deduplicated notification: \(key)")
                return
            }
            recentKeys.append((key, now))
        }

        notifications.insert(notification, at: 0)

        // 上限裁剪
        if notifications.count > Self.maxNotifications {
            notifications = Array(notifications.prefix(Self.maxNotifications))
        }

        persistToDisk()

        // waiting / error → macOS 系统通知
        if notification.type == .waiting || notification.type == .error {
            sendSystemNotification(notification)
        }

        logger.info("Notification inserted: type=\(notification.type.rawValue) agent=\(notification.agentDefinitionId)")
    }

    // MARK: - 查询

    func unreadCount(for workspaceId: UUID) -> Int {
        // nil workspaceId 的通知计入所有工作区
        notifications.count { !$0.isRead && ($0.workspaceId == workspaceId || $0.workspaceId == nil) }
    }

    func totalUnreadCount() -> Int {
        notifications.count { !$0.isRead }
    }

    func filtered(workspace: UUID? = nil, type: AgentNotificationType? = nil) -> [AgentNotification] {
        notifications.filter { n in
            // workspace 为 nil 时返回全部；否则匹配指定工作区或 nil workspaceId（全局通知）
            (workspace == nil || n.workspaceId == workspace || n.workspaceId == nil) &&
            (type == nil || n.type == type)
        }
    }

    /// 最高优先级的未读通知
    func highestPriorityUnread() -> AgentNotification? {
        notifications
            .filter { !$0.isRead }
            .max { $0.priority < $1.priority }
    }

    // MARK: - 标记已读

    func markRead(_ id: UUID) {
        guard let idx = notifications.firstIndex(where: { $0.id == id }) else { return }
        notifications[idx].isRead = true
        persistToDisk()
    }

    func markAllRead(workspace: UUID) {
        var changed = false
        for i in notifications.indices where !notifications[i].isRead &&
            (notifications[i].workspaceId == workspace || notifications[i].workspaceId == nil) {
            notifications[i].isRead = true
            changed = true
        }
        if changed { persistToDisk() }
    }

    // MARK: - 持久化（JSON 文件，复用 SessionStore 同款模式）

    private var storePath: String {
        let dir = PolterttyConfig.shared.workspaceDir
        return (dir as NSString).appendingPathComponent("notifications.json")
    }

    private func persistToDisk() {
        let snapshot = notifications
        let url = URL(fileURLWithPath: storePath)
        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func loadFromDisk() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: storePath)),
              let loaded = try? decoder.decode([AgentNotification].self, from: data) else { return }
        notifications = loaded
        logger.info("Loaded \(loaded.count) notifications from disk")
    }

    // MARK: - macOS 系统通知

    private func sendSystemNotification(_ notification: AgentNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        if let body = notification.body { content.body = body }
        content.sound = .default
        content.userInfo = [
            "workspaceId": notification.workspaceId?.uuidString ?? "",
            "notificationId": notification.id.uuidString,
        ]
        let request = UNNotificationRequest(
            identifier: notification.id.uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { [logger] error in
            if let error {
                logger.warning("Failed to deliver system notification: \(error.localizedDescription)")
            }
        }
    }
}
