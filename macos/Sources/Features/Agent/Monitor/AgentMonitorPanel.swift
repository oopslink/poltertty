// macos/Sources/Features/Agent/Monitor/AgentMonitorPanel.swift
import SwiftUI

struct AgentMonitorPanel: View {
    @ObservedObject var viewModel: AgentMonitorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Text("Agents").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { viewModel.toggle() } label: {
                    Image(systemName: "xmark").font(.system(size: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(.windowBackgroundColor))
            Divider()

            if viewModel.sessions.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Text("No active agents").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("⌘⇧A to launch").font(.system(size: 11)).foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.sessions) { session in
                            AgentSessionRow(session: session)
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(width: viewModel.width)
        .background(Color(.windowBackgroundColor))
    }
}

private struct AgentSessionRow: View {
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(session.definition.icon)
                Text(session.definition.name).font(.system(size: 12, weight: .medium))
                Spacer()
                AgentStateDot(state: session.state)
                Text(stateLabel).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.top, 10)

            if session.tokenUsage.contextUtilization > 0 {
                ContextBar(utilization: session.tokenUsage.contextUtilization)
                    .padding(.horizontal, 12)
            }

            if !session.subagents.isEmpty {
                Text("Subagents (\(session.subagents.count))")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                SubagentListView(subagents: Array(session.subagents.values))
            }

            HStack {
                Text(session.respawnMode.displayName).font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                if session.tokenUsage.cost > 0 {
                    Text(String(format: "$%.2f", NSDecimalNumber(decimal: session.tokenUsage.cost).doubleValue))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 10)
        }
    }

    private var stateLabel: String {
        switch session.state {
        case .launching:      return "Starting..."
        case .working:        return "Working"
        case .idle:           return "Idle"
        case .done:           return "Done"
        case .error(let m):   return "Error: \(m)"
        }
    }
}

private struct ContextBar: View {
    let utilization: Float

    var color: Color {
        utilization < 0.55 ? .green : utilization < 0.75 ? .yellow : .red
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Color(.separatorColor)).frame(height: 4)
                RoundedRectangle(cornerRadius: 2).fill(color)
                    .frame(width: geo.size.width * CGFloat(utilization), height: 4)
            }
        }
        .frame(height: 4)
    }
}
