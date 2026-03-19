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

            if viewModel.sessions.isEmpty && !viewModel.hasExternalSessions {
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
            // 外部会话 section（FSEvents 监控独立启动的 AI 工具实例）
            if viewModel.hasExternalSessions {
                Divider()
                externalSessionsSectionView
            }
            // F5: HISTORY section — 放在 if/else 之外，无论是否有活跃 session 均显示
            historySectionView
        }
        .frame(width: 180)
        .background(Color(.windowBackgroundColor))
    }

    private var externalSessionsSectionView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("外部会话 (\(viewModel.externalSessions.count))")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            ForEach(viewModel.externalSessions) { session in
                ExternalSessionRow(session: session)
                Divider()
            }
        }
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

// MARK: - ExternalSessionRow

private struct ExternalSessionRow: View {
    let session: ExternalSessionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                // Badge
                Text(session.toolType.badge)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(badgeColor)
                    .opacity(session.isAlive ? 1.0 : 0.4)

                // cwd 最后一段
                Text(cwdName)
                    .font(.system(size: 11))
                    .lineLimit(1)

                Spacer()

                // 存活指示
                Circle()
                    .fill(session.isAlive ? Color.green : Color.gray)
                    .frame(width: 5, height: 5)

                // pid（仅 Claude Code）
                if let pid = session.pid {
                    Text("\(pid)")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            // 最后一条消息
            if let msg = session.lastMessage {
                Text(rolePrefix(msg.role) + msg.text)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // 启动时间
            Text(session.startedAt, style: .time)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .opacity(session.isAlive ? 1.0 : 0.6)
    }

    private var cwdName: String {
        URL(fileURLWithPath: session.cwd).lastPathComponent
    }

    private var badgeColor: Color {
        switch session.toolType {
        case .claudeCode: return .orange
        case .openCode:   return .blue
        case .geminiCli:  return .green
        }
    }

    private func rolePrefix(_ role: ExternalSessionRecord.LastMessage.Role) -> String {
        role == .user ? "你：" : "助手："
    }
}
