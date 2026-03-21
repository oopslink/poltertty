// macos/Sources/Features/Workspace/AgentButton/AgentSessionPopover.swift

import SwiftUI

struct AgentSessionPopover: View {
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Agent 名称 + 图标
            HStack(spacing: 6) {
                Text(session.definition.icon)
                    .foregroundColor(
                        session.definition.iconColor.flatMap { Color(hex: $0) } ?? .secondary
                    )
                Text(session.definition.name)
                    .fontWeight(.medium)
            }

            Divider()

            // 状态
            HStack {
                Text("Status")
                    .foregroundColor(.secondary)
                Spacer()
                Text(stateText)
                    .foregroundColor(stateColor)
            }

            // 启动时间
            HStack {
                Text("Started")
                    .foregroundColor(.secondary)
                Spacer()
                Text(session.startedAt, style: .relative)
            }

            // Token 用量
            if session.tokenUsage.totalTokens > 0 {
                HStack {
                    Text("Tokens")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatTokens(session.tokenUsage.totalTokens))
                }
            }
        }
        .font(.system(size: 11))
        .padding(12)
        .frame(width: 200)
    }

    private var stateText: String {
        switch session.state {
        case .launching: return "Launching"
        case .working:   return "Working"
        case .idle:      return "Idle"
        case .done(let code): return code == 0 ? "Done" : "Done (exit \(code))"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    private var stateColor: Color {
        switch session.state {
        case .launching: return .blue
        case .working:   return .green
        case .idle:      return .yellow
        case .done:      return .secondary
        case .error:     return .red
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        }
        return "\(count)"
    }
}
