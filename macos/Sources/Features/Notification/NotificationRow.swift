// macos/Sources/Features/Notification/NotificationRow.swift
import SwiftUI

struct NotificationRow: View {
    let notification: AgentNotification
    @State private var isExpanded = false

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
                    let isLong = body.count > 80
                    let displayText = (!isExpanded && isLong)
                        ? String(body.prefix(80)) + "…"
                        : body
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayText)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(isExpanded ? nil : 2)
                        if isLong {
                            Button(isExpanded ? "收起" : "展开") {
                                isExpanded.toggle()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                        }
                    }
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
        let def = AgentRegistry.shared.definitions.first { $0.id == notification.agentDefinitionId }
        if let def {
            ZStack(alignment: .bottomTrailing) {
                AgentIconBadge(agent: def, size: 16)
                Circle()
                    .fill(typeIndicatorColor)
                    .frame(width: 6, height: 6)
                    .offset(x: 2, y: 2)
            }
        } else {
            // 未知 agent 降级到类型图标
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
    }

    private var typeIndicatorColor: Color {
        switch notification.type {
        case .waiting: return .orange
        case .error:   return .red
        case .done:    return .green
        case .info:    return .blue
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
