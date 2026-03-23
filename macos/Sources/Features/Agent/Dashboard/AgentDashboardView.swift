// macos/Sources/Features/Agent/Dashboard/AgentDashboardView.swift
import SwiftUI

struct AgentDashboardView: View {
    @StateObject private var viewModel = AgentDashboardViewModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(minWidth: 600, minHeight: 300)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Text("Agent Dashboard")
                .font(.headline)

            Spacer()

            Picker("", selection: $viewModel.viewMode) {
                ForEach(AgentDashboardViewModel.ViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 120)

            Toggle("已完成", isOn: $viewModel.showInactive)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let sessions = viewModel.activeSessions
        if sessions.isEmpty && !viewModel.showInactive {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    if !sessions.isEmpty {
                        switch viewModel.viewMode {
                        case .table:
                            tableView(sessions: sessions)
                        case .cards:
                            cardsView(sessions: sessions)
                        }
                    }

                    if viewModel.showInactive && !viewModel.historicalSessions.isEmpty {
                        historicalSection
                    }
                }
                .padding(16)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("当前没有活跃的 Agent")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Table View

    private func tableView(sessions: [AgentSession]) -> some View {
        let groups = viewModel.groupedByWorkspace(sessions)
        return VStack(spacing: 12) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if let hex = group.colorHex {
                            Circle()
                                .fill(Color(hex: hex) ?? .gray)
                                .frame(width: 8, height: 8)
                        }
                        Text(group.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 8)

                    tableHeader

                    ForEach(group.sessions) { session in
                        tableRow(session: session)
                    }
                }
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            Text("Agent").frame(width: 100, alignment: .leading)
            Text("状态").frame(width: 70, alignment: .leading)
            Text("时长").frame(width: 60, alignment: .leading)
            Text("Tokens").frame(width: 90, alignment: .leading)
            Text("当前任务").frame(maxWidth: .infinity, alignment: .leading)
            Text("Pane").frame(width: 70, alignment: .trailing)
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func tableRow(session: AgentSession) -> some View {
        HStack(spacing: 0) {
            Text(session.definition.name)
                .font(.caption)
                .fontWeight(.medium)
                .frame(width: 100, alignment: .leading)

            HStack(spacing: 4) {
                Circle()
                    .fill(stateColor(session.state))
                    .frame(width: 6, height: 6)
                Text(stateLabel(session.state))
                    .font(.caption2)
            }
            .frame(width: 70, alignment: .leading)

            Text(viewModel.durationString(for: session))
                .font(.caption)
                .monospacedDigit()
                .frame(width: 60, alignment: .leading)

            Text("\(viewModel.tokenString(for: session.tokenUsage)) / \(viewModel.costString(for: session.tokenUsage))")
                .font(.caption2)
                .monospacedDigit()
                .frame(width: 90, alignment: .leading)

            Text(viewModel.taskDescription(for: session))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(viewModel.paneLocationString(for: session))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            PaneLocator.navigate(to: session.surfaceId)
        }
    }

    // MARK: - Cards View

    private func cardsView(sessions: [AgentSession]) -> some View {
        let groups = viewModel.groupedByWorkspace(sessions)
        return VStack(spacing: 16) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        if let hex = group.colorHex {
                            Circle()
                                .fill(Color(hex: hex) ?? .gray)
                                .frame(width: 8, height: 8)
                        }
                        Text(group.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fontWeight(.semibold)
                    }

                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 250, maximum: 350), spacing: 12)
                    ], spacing: 12) {
                        ForEach(group.sessions) { session in
                            cardItem(session: session)
                        }
                    }
                }
            }
        }
    }

    private func cardItem(session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.definition.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(stateColor(session.state))
                        .frame(width: 6, height: 6)
                    Text(stateLabel(session.state))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Label(viewModel.durationString(for: session), systemImage: "clock")
                Spacer()
                Label(
                    "\(viewModel.tokenString(for: session.tokenUsage)) / \(viewModel.costString(for: session.tokenUsage))",
                    systemImage: "text.badge.checkmark"
                )
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text(viewModel.taskDescription(for: session))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                .cornerRadius(4)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            PaneLocator.navigate(to: session.surfaceId)
        }
    }

    // MARK: - Historical Section

    private var historicalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.vertical, 8)

            Text("已完成")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)

            ForEach(viewModel.historicalSessions) { session in
                historicalRow(session: session)
            }
        }
    }

    private func historicalRow(session: PersistedSession) -> some View {
        HStack(spacing: 0) {
            Text(session.agentName)
                .font(.caption)
                .frame(width: 100, alignment: .leading)

            let wsName = WorkspaceManager.shared.workspace(for: session.workspaceId)?.name ?? "Unknown"
            Text(wsName)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .leading)

            Text("done")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .leading)

            Text("\(viewModel.tokenString(for: session.tokenUsage)) / \(viewModel.costString(for: session.tokenUsage))")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 90, alignment: .leading)

            Text(session.finishedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .opacity(0.6)
    }

    // MARK: - Helpers

    private func stateColor(_ state: AgentState) -> Color {
        switch state {
        case .working: return .green
        case .idle: return .yellow
        case .launching: return .blue
        case .done: return .gray
        case .error: return .red
        }
    }

    private func stateLabel(_ state: AgentState) -> String {
        switch state {
        case .working: return "working"
        case .idle: return "idle"
        case .launching: return "launching"
        case .done: return "done"
        case .error: return "error"
        }
    }
}
