// macos/Sources/Features/Agent/Monitor/AgentMonitorPanel.swift
import SwiftUI

struct AgentMonitorPanel: View {
    @ObservedObject var viewModel: AgentMonitorViewModel

    @State private var selectedExternalSession: ExternalSessionRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if viewModel.sessions.isEmpty && !viewModel.hasExternalSessions {
                        emptyStateView
                    } else {
                        ForEach(viewModel.sessions) { session in
                            AgentSessionGroup(session: session, viewModel: viewModel)
                            Divider()
                        }
                    }

                    if viewModel.hasExternalSessions {
                        Divider()
                        externalSessionsSectionView
                    }

                    historySectionView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 200, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Panel Header

    private var panelHeader: some View {
        HStack(spacing: 6) {
            Text("Agents")
                .font(.system(size: 11, weight: .semibold))
            if viewModel.sessions.count > 0 {
                Text("\(viewModel.sessions.count)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(AgentColors.selectionBg)
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
            }
            Spacer()
            Button { viewModel.toggle() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .frame(width: 16, height: 16)
                    .background(Color(.separatorColor).opacity(0.3))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close Agents panel")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 22, weight: .thin))
                .foregroundStyle(.quaternary)
                .padding(.bottom, 2)
            Text("No active agents")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("⌘⇧A to launch")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: - External Sessions Section

    private var externalSessionsSectionView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("External Sessions")
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

    // MARK: - History Section

    private var historySectionView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { viewModel.toggleHistory() }) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.historyExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8)).foregroundStyle(.secondary)
                    Text("HISTORY")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if viewModel.historyExpanded {
                ForEach(viewModel.historicalSessions) { ps in
                    historyRow(ps)
                    Divider()
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
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(AgentColors.success.opacity(0.8))
                VStack(alignment: .leading, spacing: 1) {
                    Text(ps.agentName)
                        .font(.system(size: 10))
                        .foregroundStyle(.primary)
                        .lineLimit(1).truncationMode(.tail)
                    Text(relativeTime(ps.finishedAt))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                let cost = NSDecimalNumber(decimal: ps.tokenUsage.cost).doubleValue
                if cost > 0 {
                    Text(String(format: "$%.2f", cost))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(AgentColors.success.opacity(0.9))
                }
            }
            .padding(.leading, 10).padding(.trailing, 10).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func relativeTime(_ date: Date) -> String {
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 3600  { return "\(secs / 60)m ago" }
        if secs < 86400 { return "\(secs / 3600)h ago" }
        return "\(secs / 86400)d ago"
    }
}

// MARK: - ExternalSessionRow

private struct ExternalSessionRow: View {
    let session: ExternalSessionRecord
    var isSelected: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(session.toolType.badge)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(badgeColor)
                    .opacity(session.isAlive ? 1.0 : 0.5)

                Text(cwdName)
                    .font(.system(size: 11))
                    .lineLimit(1)

                Spacer()

                Circle()
                    .fill(session.isAlive ? AgentColors.success : Color.secondary.opacity(0.4))
                    .frame(width: 5, height: 5)
            }

            if let msg = session.lastMessage {
                HStack(spacing: 3) {
                    Text(msg.role == .user ? "↑" : "↓")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(msg.role == .user ? Color.blue.opacity(0.7) : Color.orange.opacity(0.7))
                    Text(msg.text)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? AgentColors.selectionBg : Color.clear)
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
            detailGrid

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
                .fill(session.isAlive ? AgentColors.success : Color.secondary.opacity(0.5))
                .frame(width: 6, height: 6)
            Text(session.isAlive ? "Running" : "Stopped")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(session.isAlive ? .primary : .secondary)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(session.isAlive
                      ? AgentColors.success.opacity(0.1)
                      : Color.secondary.opacity(0.1))
        )
    }

    private var detailGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            detailRow("Session ID", value: session.id)
            if let pid = session.pid {
                detailRow("PID", value: "\(pid)")
            }
            detailRow("Working Dir", value: session.cwd, monospaced: true)
            detailRow("Started", value: Self.dateFormatter.string(from: session.startedAt))
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
                    .foregroundStyle(msg.role == .user ? Color.blue : Color.orange)
                    .frame(width: 52, alignment: .leading)
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
        if secs < 60   { return "\(secs)s" }
        if secs < 3600 { return "\(secs / 60)m \(secs % 60)s" }
        let h = secs / 3600
        let m = (secs % 3600) / 60
        return "\(h)h \(m)m"
    }
}
