// macos/Sources/Features/Agent/Monitor/AgentMonitorPanel.swift
import SwiftUI

struct AgentMonitorPanel: View {
    @ObservedObject var viewModel: AgentMonitorViewModel

    /// 当前弹出详情的外部会话
    @State private var selectedExternalSession: ExternalSessionRecord?

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

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    if viewModel.sessions.isEmpty && !viewModel.hasExternalSessions {
                        // 空状态
                        VStack(spacing: 5) {
                            Image(systemName: "circle.hexagongrid")
                                .font(.system(size: 24, weight: .thin))
                                .foregroundStyle(.quaternary)
                                .padding(.bottom, 3)
                            Text("No active agents").font(.system(size: 11)).foregroundStyle(.secondary)
                            Text("⌘⇧A to launch").font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        // Agents 列表
                        ForEach(viewModel.sessions) { session in
                            AgentSessionGroup(session: session, viewModel: viewModel)
                            Divider()
                        }
                    }

                    // 外部会话 section
                    if viewModel.hasExternalSessions {
                        Divider()
                        externalSessionsSectionView
                    }

                    // History section
                    historySectionView
                }
            }
        }
        .frame(width: 180)
        .background(Color(.windowBackgroundColor))
    }

    private var externalSessionsSectionView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("External Session")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(viewModel.externalSessions.count)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color(.separatorColor).opacity(0.5))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)

            ForEach(viewModel.externalSessions) { session in
                ExternalSessionRow(
                    session: session,
                    isSelected: selectedExternalSession?.id == session.id
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if selectedExternalSession?.id == session.id {
                        selectedExternalSession = nil
                    } else {
                        selectedExternalSession = session
                    }
                }
                .popover(
                    isPresented: Binding(
                        get: { selectedExternalSession?.id == session.id },
                        set: { if !$0 { selectedExternalSession = nil } }
                    ),
                    arrowEdge: .trailing
                ) {
                    ExternalSessionDetailView(session: session)
                }
                Divider()
            }
        }
    }

    private var historySectionView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { viewModel.toggleHistory() }) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.historyExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8)).foregroundStyle(.secondary)
                    Text("HISTORY")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
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
    var isSelected: Bool = false

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
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
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
        role == .user ? "You:" : "Assistant:"
    }
}

// MARK: - ExternalSessionDetailView

private struct ExternalSessionDetailView: View {
    let session: ExternalSessionRecord

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 标题行
            HStack(spacing: 6) {
                Text(session.toolType.badge)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(badgeColor)
                Text(toolName)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                statusBadge
            }

            Divider()

            // 详情字段
            detailGrid

            // 最后消息
            if let msg = session.lastMessage {
                Divider()
                lastMessageView(msg)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private var toolName: String {
        switch session.toolType {
        case .claudeCode: return "Claude Code"
        case .openCode:   return "OpenCode"
        case .geminiCli:  return "Gemini CLI"
        }
    }

    private var badgeColor: Color {
        switch session.toolType {
        case .claudeCode: return .orange
        case .openCode:   return .blue
        case .geminiCli:  return .green
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(session.isAlive ? Color.green : Color.gray)
                .frame(width: 6, height: 6)
            Text(session.isAlive ? "Running" : "Stopped")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(session.isAlive ? .primary : .secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(session.isAlive
                      ? Color.green.opacity(0.1)
                      : Color.gray.opacity(0.1))
        )
    }

    private var detailGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            detailRow("Session ID", value: session.id)

            if let pid = session.pid {
                detailRow("PID", value: "\(pid)")
            }

            detailRow("Working Dir", value: session.cwd, monospaced: true)

            detailRow("Started",
                      value: Self.dateFormatter.string(from: session.startedAt))

            detailRow("Duration", value: durationText)
        }
    }

    private func detailRow(_ label: String, value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 11, design: monospaced ? .monospaced : .default))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private func lastMessageView(_ msg: ExternalSessionRecord.LastMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("Last Message")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(Self.dateFormatter.string(from: msg.timestamp))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .top, spacing: 4) {
                Text(msg.role == .user ? "User" : "Assistant")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(msg.role == .user ? .blue : .orange)
                    .frame(width: 24, alignment: .leading)
                Text(msg.text)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(6)
            }
        }
    }

    private var durationText: String {
        let secs = Int(Date().timeIntervalSince(session.startedAt))
        if secs < 60     { return "\(secs)s" }
        if secs < 3600   { return "\(secs / 60)m \(secs % 60)s" }
        let h = secs / 3600
        let m = (secs % 3600) / 60
        return "\(h)h \(m)m"
    }
}
