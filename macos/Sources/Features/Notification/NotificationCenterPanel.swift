// macos/Sources/Features/Notification/NotificationCenterPanel.swift
import SwiftUI

struct NotificationCenterPanel: View {
    @ObservedObject var store = AgentNotificationStore.shared
    let workspaceId: UUID?
    let onJumpToSurface: (UUID) -> Void
    let onClose: () -> Void

    @State private var typeFilter: AgentNotificationType? = nil

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            header
            Divider()

            // 筛选栏
            filterBar
            Divider()

            // 通知列表
            notificationList
        }
        .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
        .background(Color(nsColor: .controlBackgroundColor))
        .backport.onKeyPress(.escape) { _ in onClose(); return .handled }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Notifications")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            if let wsId = workspaceId {
                Button("Mark all read") {
                    store.markAllRead(workspace: wsId)
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 6) {
            FilterChip("All", isSelected: typeFilter == nil) {
                typeFilter = nil
            }
            FilterChip("Waiting", isSelected: typeFilter == .waiting) {
                typeFilter = .waiting
            }
            FilterChip("Error", isSelected: typeFilter == .error) {
                typeFilter = .error
            }
            FilterChip("Done", isSelected: typeFilter == .done) {
                typeFilter = .done
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Notification List

    @ViewBuilder
    private var notificationList: some View {
        let items = store.filtered(workspace: workspaceId, type: typeFilter)
        if items.isEmpty {
            Spacer()
            Text("No notifications")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { notification in
                        NotificationRow(notification: notification)
                            .onTapGesture(count: 2) {
                                store.markRead(notification.id)
                                if let sid = notification.surfaceId {
                                    onJumpToSurface(sid)
                                }
                            }
                            .onTapGesture {
                                store.markRead(notification.id)
                            }
                            .background(
                                notification.isRead
                                    ? Color.clear
                                    : Color.accentColor.opacity(0.03)
                            )

                        Divider().padding(.leading, 36)
                    }
                }
            }
        }
    }
}
