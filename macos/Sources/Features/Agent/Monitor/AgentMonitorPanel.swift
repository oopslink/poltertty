// macos/Sources/Features/Agent/Monitor/AgentMonitorPanel.swift
import SwiftUI

struct AgentMonitorPanel: View {
    @ObservedObject var viewModel: AgentMonitorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Text("Agents").font(.system(size: 11, weight: .semibold))
                Spacer()
                Button { viewModel.toggle() } label: {
                    Image(systemName: "xmark").font(.system(size: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color(.windowBackgroundColor))
            Divider()

            if viewModel.sessions.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Text("No active agents").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("⌘⇧A to launch").font(.system(size: 10)).foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.sessions) { session in
                            AgentSessionGroup(session: session, viewModel: viewModel)
                            Divider()
                        }
                    }
                }
            }
            // F5: HISTORY section — 放在 if/else 之外，无论是否有活跃 session 均显示
            historySectionView
        }
        .frame(width: 180)
        .background(Color(.windowBackgroundColor))
    }

    private var historySectionView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 折叠/展开 header

            Button(action: { viewModel.toggleHistory() }) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.historyExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8)).foregroundStyle(.tertiary)
                    Text("HISTORY")
                        .font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
            }
            .buttonStyle(.plain)

            if viewModel.historyExpanded {
                ForEach(viewModel.historicalSessions) { ps in
                    historyRow(ps)
                }
            }
        }
        .background(Color(.windowBackgroundColor))
        .onAppear {
            viewModel.loadHistory()
            if viewModel.sessions.isEmpty {
                viewModel.historyExpanded = true
            }
        }
    }

    private func historyRow(_ ps: PersistedSession) -> some View {
        Button(action: {
            viewModel.isVisible = true
            viewModel.selectHistory(ps)
        }) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 8)).foregroundStyle(Color(hex: "#4caf50") ?? .green)
                Text(ps.agentName)
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
                Spacer()
                let cost = NSDecimalNumber(decimal: ps.tokenUsage.cost).doubleValue
                if cost > 0 {
                    Text(String(format: "$%.2f", cost))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Color(hex: "#4caf50") ?? .green)
                }
                Text(relativeTime(ps.finishedAt))
                    .font(.system(size: 8, design: .monospaced)).foregroundStyle(.tertiary)
            }
            .padding(.leading, 18).padding(.trailing, 10).padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }

    private func relativeTime(_ date: Date) -> String {
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 3600  { return "\(secs / 60)m" }
        if secs < 86400 { return "\(secs / 3600)h" }
        return "\(secs / 86400)d"
    }
}
