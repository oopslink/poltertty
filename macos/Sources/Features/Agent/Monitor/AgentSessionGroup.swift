// macos/Sources/Features/Agent/Monitor/AgentSessionGroup.swift
import SwiftUI

struct AgentSessionGroup: View {
    let session: AgentSession
    @ObservedObject var viewModel: AgentMonitorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Session 标题行（可点击 → Overview）──────────
            sessionRow
            // ── Subagent 列表 ────────────────────────────────
            if !session.subagents.isEmpty {
                ForEach(sortedSubagents) { sub in
                    subagentRow(sub)
                }
            }
        }
    }

    // MARK: - Session row

    private var sessionRow: some View {
        let item = DrawerItem.sessionOverview(session)
        let isSelected = viewModel.selectedItems.contains(item)
        return HStack(spacing: 5) {
            AgentStateDot(state: session.state)
            Text(session.definition.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isSelected ? (Color(hex: "#90bfff") ?? .blue) : .primary)
                .lineLimit(1)
            Spacer()
            if activeCount > 0 {
                Text("\(activeCount)↑")
                    .font(.system(size: 8, weight: .medium))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color(hex: "#1a2e1a") ?? Color(.separatorColor))
                    .foregroundStyle(Color(hex: "#4caf50") ?? .green)
                    .clipShape(Capsule())
            } else {
                Text("done")
                    .font(.system(size: 8))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color(.separatorColor).opacity(0.4))
                    .foregroundStyle(.tertiary)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(isSelected ? (Color(hex: "#1a2535") ?? Color.accentColor.opacity(0.2)) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.select(item) }
    }

    // MARK: - Subagent row

    private func subagentRow(_ sub: SubagentInfo) -> some View {
        let item = DrawerItem.subagentDetail(session, sub)
        let isSelected = viewModel.selectedItems.contains(item)
        return HStack(spacing: 4) {
            stateDot(sub.state)
            Text(sub.name)
                .font(.system(size: 9))
                .foregroundStyle(isSelected ? (Color(hex: "#90bfff") ?? .blue) : .secondary)
                .lineLimit(1).truncationMode(.tail)
            Spacer()
            Text(elapsedLabel(sub))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(isSelected ? (Color(hex: "#4a6a99") ?? Color(.tertiaryLabelColor)) : Color(.tertiaryLabelColor))
        }
        .padding(.leading, 20).padding(.trailing, 10).padding(.vertical, 3)
        .background(isSelected ? (Color(hex: "#152040") ?? Color.accentColor.opacity(0.15)) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.select(item) }
        // Cmd+Click 多选
        .simultaneousGesture(TapGesture().modifiers(.command).onEnded { _ in
            viewModel.cmdClick(item)
        })
    }

    // MARK: - Helpers

    private var sortedSubagents: [SubagentInfo] {
        Array(session.subagents.values).sorted { $0.startedAt < $1.startedAt }
    }

    private var activeCount: Int {
        session.subagents.values.filter { $0.state.isActive }.count
    }

    private func stateDot(_ state: AgentState) -> some View {
        let color: Color = {
            switch state {
            case .working:  return Color(hex: "#4caf50") ?? .green
            case .error:    return Color(hex: "#f44336") ?? .red
            case .idle:     return Color(hex: "#ff9800") ?? .orange
            default:        return Color(hex: "#555555") ?? .gray
            }
        }()
        return Circle().fill(color).frame(width: 5, height: 5)
    }

    private func elapsedLabel(_ sub: SubagentInfo) -> String {
        let end = sub.finishedAt ?? Date()
        let secs = max(0, Int(end.timeIntervalSince(sub.startedAt)))
        if secs < 60 { return "\(secs)s" }
        return "\(secs/60)m\(secs%60)s"
    }
}
