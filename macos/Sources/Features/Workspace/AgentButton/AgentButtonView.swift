// macos/Sources/Features/Workspace/AgentButton/AgentButtonView.swift

import SwiftUI

/// Status bar 中的 Agent 按钮：无 session 时显示启动入口，有 session 时显示状态指示器
struct AgentButtonView: View {
    let surfaceId: UUID

    @ObservedObject private var sessionManager = AgentService.shared.sessionManager
    @State private var showPopover = false

    private var session: AgentSession? {
        sessionManager.sessions[surfaceId]
    }

    var body: some View {
        Button(action: { showPopover.toggle() }) {
            if let session {
                agentStateIcon(session: session)
            } else {
                Text("\u{2B21}")
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            if let session {
                AgentSessionPopover(session: session)
            } else {
                AgentPickerPopover(surfaceId: surfaceId, isPresented: $showPopover)
            }
        }
    }

    @ViewBuilder
    private func agentStateIcon(session: AgentSession) -> some View {
        let color = session.definition.iconColor.flatMap { Color(hex: $0) } ?? .secondary
        Text(session.definition.icon)
            .foregroundColor(color)
            .opacity(session.state == .working ? 1.0 : (session.state.isActive ? 0.8 : 0.4))
            .animation(
                session.state == .working
                    ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                    : .default,
                value: session.state == .working
            )
    }
}
