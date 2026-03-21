// macos/Sources/Features/Agent/Monitor/AgentSessionGroup.swift
import SwiftUI

struct AgentSessionGroup: View {
    let session: AgentSession
    @ObservedObject var viewModel: AgentMonitorViewModel
    @State private var tick = Date()
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

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
        .opacity(session.state.isActive ? 1.0 : 0.55)
        .onReceive(timer) { t in if session.state.isActive { tick = t } }
    }

    // MARK: - Session row

    private var sessionRow: some View {
        let item = DrawerItem.sessionOverview(session)
        let isSelected = viewModel.selectedItems.contains(item)
        return HStack(spacing: 5) {
            if session.state.isActive {
                AgentStateDot(state: session.state)
            } else {
                Circle().fill(Color.secondary.opacity(0.4)).frame(width: 6, height: 6)
            }
            Text(session.definition.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isSelected ? (Color(hex: "#90bfff") ?? .blue) : (session.state.isActive ? .primary : .secondary))
                .lineLimit(1)
            Spacer()
            if activeCount > 0 {
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color(hex: "#4caf50") ?? .green)
                        .frame(width: 5, height: 5)
                    Text("\(activeCount)")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(hex: "#4caf50") ?? .green)
                }
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Color(hex: "#1a2e1a") ?? Color(.separatorColor))
                .clipShape(Capsule())
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .semibold))
                    Text("done")
                        .font(.system(size: 8))
                }
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background((Color(hex: "#1a2e1a") ?? Color(.separatorColor)).opacity(0.8))
                .foregroundStyle((Color(hex: "#4caf50") ?? .green).opacity(0.7))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(isSelected ? (Color(hex: "#1a2535") ?? Color.accentColor.opacity(0.2)) : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2)
                .opacity(isSelected ? 1.0 : 0.0)
        }
        .contentShape(Rectangle())
        .onTapGesture { viewModel.select(item) }
    }

    // MARK: - Subagent row

    private func subagentRow(_ sub: SubagentInfo) -> some View {
        let isSelected = viewModel.selectedSubagentId == sub.id
        return HStack(spacing: 4) {
            AgentStateDot(state: sub.state)
            Text(sub.name)
                .font(.system(size: 9))
                .foregroundStyle(isSelected ? (Color(hex: "#90bfff") ?? .blue) : .secondary)
                .lineLimit(1).truncationMode(.tail)
            Spacer()
            // F2: 工具气泡
            if sub.state.isActive,
               let activeTool = sub.toolCalls.last(where: { !$0.isDone }) {
                Text(String(activeTool.toolName.prefix(12)))
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            Text(elapsedLabel(sub))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(isSelected ? (Color(hex: "#4a6a99") ?? Color(.tertiaryLabelColor)) : Color(.tertiaryLabelColor))
        }
        .padding(.leading, 20).padding(.trailing, 10).padding(.vertical, 3)
        .background(isSelected ? (Color(hex: "#152040") ?? Color.accentColor.opacity(0.15)) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            // 打开统一视图，预选此 subagent
            viewModel.selectSubagentInSidebar(sub, in: session)
        }
    }

    // MARK: - Helpers

    private var sortedSubagents: [SubagentInfo] {
        Array(session.subagents.values).sorted { $0.startedAt < $1.startedAt }
    }

    private var activeCount: Int {
        session.subagents.values.filter { $0.state.isActive }.count
    }

    private func elapsedLabel(_ sub: SubagentInfo) -> String {
        let end = sub.finishedAt ?? tick
        let secs = max(0, Int(end.timeIntervalSince(sub.startedAt)))
        if secs < 60 { return "\(secs)s" }
        return "\(secs/60)m\(secs%60)s"
    }
}
