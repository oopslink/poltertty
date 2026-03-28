// macos/Sources/Features/Agent/Monitor/AgentSessionGroup.swift
import SwiftUI

struct AgentSessionGroup: View {
    let session: AgentSession
    @ObservedObject var viewModel: AgentMonitorViewModel
    @State private var tick = Date()
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sessionRow
            if !session.subagents.isEmpty {
                ForEach(sortedSubagents) { sub in
                    subagentRow(sub)
                }
            }
        }
        .opacity(session.state.isActive ? 1.0 : 0.6)
        .onReceive(timer) { t in if session.state.isActive { tick = t } }
    }

    // MARK: - Session row

    private var sessionRow: some View {
        let item = DrawerItem.sessionOverview(session)
        let isSelected = viewModel.selectedItems.contains(item)
        return HStack(spacing: 6) {
            if session.state.isActive {
                AgentStateDot(state: session.state)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
            AgentInlineIcon(agent: session.definition, size: 11)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.definition.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? AgentColors.selectedBlue : (session.state.isActive ? .primary : .secondary))
                    .lineLimit(1)
                if let model = session.model {
                    Text(shortModelName(model))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if activeCount > 0 {
                activeCountBadge
            } else {
                sessionStateBadge
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(isSelected ? AgentColors.selectionBgStrong : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(AgentColors.selectionIndicator)
                .frame(width: 2)
                .opacity(isSelected ? 1.0 : 0.0)
        }
        .contentShape(Rectangle())
        .onTapGesture { viewModel.select(item) }
    }

    private var activeCountBadge: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(AgentColors.success)
                .frame(width: 5, height: 5)
            Text("\(activeCount)")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(AgentColors.success)
        }
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(AgentColors.successBadgeBg)
        .clipShape(Capsule())
    }

    // MARK: - Subagent row

    private func subagentRow(_ sub: SubagentInfo) -> some View {
        let isSelected = viewModel.selectedSubagentId == sub.id
        return HStack(spacing: 5) {
            AgentStateDot(state: sub.state)
            Text(sub.name)
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? AgentColors.selectedBlue : .secondary)
                .lineLimit(1).truncationMode(.tail)
            Spacer()
            if sub.state.isActive,
               let activeTool = sub.toolCalls.last(where: { !$0.isDone }) {
                Text(String(activeTool.toolName.prefix(14)))
                    .font(.system(size: 8))
                    .foregroundStyle(AgentColors.active)
                    .lineLimit(1)
            }
            Text(elapsedLabel(sub))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.leading, 22).padding(.trailing, 10).padding(.vertical, 4)
        .background(isSelected ? AgentColors.selectionBg : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectSubagentInSidebar(sub, in: session)
        }
    }

    // MARK: - Session state badge

    @ViewBuilder
    private var sessionStateBadge: some View {
        switch session.state {
        case .working:
            stateBadge(
                dot: AgentColors.active,
                label: "working",
                bg: AgentColors.activeBadgeBg,
                fg: AgentColors.active
            )
        case .idle:
            stateBadge(
                dot: AgentColors.idle,
                label: "idle",
                bg: AgentColors.idleBadgeBg,
                fg: .secondary
            )
        case .launching:
            stateBadge(
                dot: AgentColors.launching,
                label: "launching",
                bg: AgentColors.launchingBadgeBg,
                fg: AgentColors.launching
            )
        case .done:
            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .semibold))
                Text("done")
                    .font(.system(size: 8))
            }
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(AgentColors.successBadgeBg)
            .foregroundStyle(AgentColors.success)
            .clipShape(Capsule())
        case .error:
            HStack(spacing: 3) {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .semibold))
                Text("error")
                    .font(.system(size: 8))
            }
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(AgentColors.errorBadgeBg)
            .foregroundStyle(AgentColors.error)
            .clipShape(Capsule())
        }
    }

    private func stateBadge(dot: Color, label: String, bg: Color, fg: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(dot).frame(width: 5, height: 5)
            Text(label).font(.system(size: 8))
        }
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(bg)
        .foregroundStyle(fg)
        .clipShape(Capsule())
    }

    // MARK: - Helpers

    private var sortedSubagents: [SubagentInfo] {
        Array(session.subagents.values).sorted { $0.startedAt < $1.startedAt }
    }

    private var activeCount: Int {
        session.subagents.values.filter { $0.state.isActive }.count
    }

    private func shortModelName(_ model: String) -> String {
        model.hasPrefix("claude-") ? String(model.dropFirst(7)) : model
    }

    private func elapsedLabel(_ sub: SubagentInfo) -> String {
        let end = sub.finishedAt ?? tick
        let secs = max(0, Int(end.timeIntervalSince(sub.startedAt)))
        if secs < 60 { return "\(secs)s" }
        return "\(secs/60)m\(secs%60)s"
    }
}
