// macos/Sources/Features/Notification/NotificationRow.swift
import SwiftUI

struct NotificationRow: View {
    let notification: AgentNotification

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 状态图标
            typeIcon
                .frame(width: 16, height: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(notification.title)
                        .font(.system(size: 12, weight: notification.isRead ? .regular : .semibold))
                        .foregroundColor(notification.isRead ? .secondary : .primary)
                        .lineLimit(1)

                    Spacer()

                    Text(relativeTime)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                if let body = notification.body, !body.isEmpty {
                    Text(body)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            // 未读指示器
            if !notification.isRead {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var typeIcon: some View {
        switch notification.type {
        case .waiting:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.orange)
        case .error:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .info:
            Image(systemName: "info.circle.fill")
                .foregroundColor(.blue)
        }
    }

    private var relativeTime: String {
        let interval = Date().timeIntervalSince(notification.timestamp)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60))分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600))小时前" }
        return "\(Int(interval / 86400))天前"
    }
}
