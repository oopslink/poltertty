// macos/Sources/Features/Agent/Dashboard/AgentDashboardView.swift
import SwiftUI

struct AgentDashboardView: View {
    @StateObject private var viewModel = AgentDashboardViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredRowId: UUID?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(spacing: 0) {
                dashboardToolbar
                Divider()
                if !viewModel.activeSessions.isEmpty {
                    summaryStatsBar(tick: timeline.date)
                    Divider()
                }
                mainContent(tick: timeline.date)
            }
        }
        .frame(minWidth: 720, minHeight: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    // MARK: - Toolbar

    private var dashboardToolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Agent Dashboard")
                    .font(.system(size: 13, weight: .semibold))
            }

            Spacer()

            Toggle("已完成", isOn: $viewModel.showInactive)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .font(.system(size: 11))

            Picker("", selection: $viewModel.viewMode) {
                ForEach(AgentDashboardViewModel.ViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 100)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Summary Stats Bar

    private func summaryStatsBar(tick: Date) -> some View {
        let sessions = viewModel.activeSessions
        let workingCount = sessions.filter {
            if case .working = $0.state { return true }
            return false
        }.count
        let activeSubCount = sessions.reduce(0) {
            $0 + $1.subagents.values.filter { $0.state.isActive }.count
        }
        let totalTokens = sessions.reduce(0) { $0 + $1.tokenUsage.totalTokens }
        let totalCost = sessions.reduce(Decimal(0)) { $0 + $1.tokenUsage.cost }

        return HStack(spacing: 0) {
            statCell(value: "\(sessions.count)", label: "ACTIVE",
                     color: sessions.isEmpty ? .secondary : .primary)
            statDivider
            statCell(value: "\(workingCount)", label: "WORKING",
                     color: workingCount > 0 ? .green : .secondary)
            statDivider
            statCell(value: "\(activeSubCount)", label: "SUBAGENTS",
                     color: activeSubCount > 0 ? .blue : .secondary)
            Spacer()
            statDivider
            statCell(value: formatTokens(totalTokens), label: "TOKENS",
                     color: .secondary, monospaced: true)
            statDivider
            statCell(
                value: String(format: "$%.2f", NSDecimalNumber(decimal: totalCost).doubleValue),
                label: "COST",
                color: totalCost > 0 ? .orange : .secondary,
                monospaced: true
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor)
            .opacity(colorScheme == .dark ? 0.3 : 0.4))
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 12)
    }

    private func statCell(value: String, label: String, color: Color,
                          monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(monospaced
                    ? .system(size: 13, weight: .semibold, design: .monospaced)
                    : .system(size: 13, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .tracking(0.5)
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private func mainContent(tick: Date) -> some View {
        let sessions = viewModel.activeSessions
        if sessions.isEmpty && !viewModel.showInactive {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !sessions.isEmpty {
                        switch viewModel.viewMode {
                        case .table:
                            tableView(sessions: sessions, tick: tick)
                        case .cards:
                            cardsView(sessions: sessions, tick: tick)
                        }
                    }
                    if viewModel.showInactive && !viewModel.historicalSessions.isEmpty {
                        historicalSection
                    }
                }
                .padding(14)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(.quaternary)
            VStack(spacing: 3) {
                Text("当前没有活跃的 Agent")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("双击 Option 键打开 / 关闭 · ⌘⇧A 启动")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Table View

    private func tableView(sessions: [AgentSession], tick: Date) -> some View {
        let groups = viewModel.groupedByWorkspace(sessions)
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 0) {
                    workspaceHeader(group: group, count: group.sessions.count)
                    tableColumnHeader.padding(.top, 4)
                    VStack(spacing: 2) {
                        ForEach(group.sessions) { session in
                            let accentColor = group.colorHex.flatMap { Color(hex: $0) }
                            tableRow(session: session, accentColor: accentColor, tick: tick)
                        }
                    }
                }
            }
        }
    }

    private func workspaceHeader(
        group: AgentDashboardViewModel.WorkspaceSessionGroup, count: Int
    ) -> some View {
        HStack(spacing: 8) {
            if let hex = group.colorHex, let c = Color(hex: hex) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(c)
                    .frame(width: 3, height: 14)
            }
            Text(group.name.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(1.0)
            Text("\(count)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color(nsColor: .separatorColor).opacity(0.5)))
            Spacer()
        }
        .padding(.bottom, 2)
    }

    private var tableColumnHeader: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 3)
            Text("AGENT").frame(width: 124, alignment: .leading).padding(.leading, 8)
            Text("状态").frame(width: 68, alignment: .leading)
            Text("时长").frame(width: 54, alignment: .leading)
            Text("上下文").frame(width: 88, alignment: .leading)
            Text("TOKEN / 费用").frame(width: 104, alignment: .leading)
            Text("子 Agent").frame(width: 56, alignment: .center)
            Text("任务").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.quaternary)
        .tracking(0.4)
        .padding(.vertical, 3)
        .padding(.trailing, 8)
    }

    private func tableRow(session: AgentSession, accentColor: Color?,
                          tick: Date) -> some View {
        let ctx = session.tokenUsage.contextUtilization
        let activeSubagents = session.subagents.values.filter { $0.state.isActive }.count
        let totalSubagents = session.subagents.count
        let isHovered = hoveredRowId == session.id

        return HStack(spacing: 0) {
            // Workspace accent bar
            Rectangle()
                .fill(accentColor ?? Color.clear)
                .frame(width: 3)

            HStack(spacing: 0) {
                // State dot + icon + agent name (+ model subtitle)
                HStack(spacing: 5) {
                    AgentStateDot(state: session.state)
                    AgentIconBadge(agent: session.definition, size: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.definition.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        if let model = session.model {
                            Text(shortModelName(model))
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(width: 124, alignment: .leading)
                .padding(.leading, 8)

                // Status
                Text(stateLabel(session.state))
                    .font(.system(size: 10))
                    .foregroundStyle(stateColor(session.state))
                    .frame(width: 68, alignment: .leading)

                // Duration
                Text(viewModel.durationString(for: session, tick: tick))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .leading)

                // Context utilization
                VStack(alignment: .leading, spacing: 2) {
                    if ctx > 0 {
                        ContextUtilBar(utilization: ctx)
                            .frame(width: 50)
                        Text(String(format: "%.0f%%", ctx * 100))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("—").font(.system(size: 10)).foregroundStyle(.quaternary)
                    }
                }
                .frame(width: 88, alignment: .leading)

                // Token / Cost
                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.tokenString(for: session.tokenUsage))
                        .font(.system(size: 10, design: .monospaced))
                    Text(viewModel.costString(for: session.tokenUsage))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.orange.opacity(0.8))
                }
                .frame(width: 104, alignment: .leading)

                // Subagent badge
                Group {
                    if totalSubagents > 0 {
                        HStack(spacing: 2) {
                            if activeSubagents > 0 {
                                Circle().fill(Color.blue).frame(width: 4, height: 4)
                            }
                            Text(activeSubagents > 0
                                ? "\(activeSubagents)/\(totalSubagents)"
                                : "\(totalSubagents)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(activeSubagents > 0 ? AnyShapeStyle(Color.blue) : AnyShapeStyle(.tertiary))
                        }
                    } else {
                        Text("—").font(.system(size: 10)).foregroundStyle(.quaternary)
                    }
                }
                .frame(width: 56, alignment: .center)

                // Task description
                Text(viewModel.taskDescription(for: session))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 7)
            .padding(.trailing, 10)
        }
        .background(
            isHovered
                ? Color(nsColor: .controlAccentColor).opacity(colorScheme == .dark ? 0.15 : 0.1)
                : Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.35 : 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onHover { hovering in hoveredRowId = hovering ? session.id : nil }
        .onTapGesture(count: 2) {
            PaneLocator.navigate(to: session.surfaceId)
            AgentDashboardWindowController.shared.close()
        }
        .onTapGesture { PaneLocator.navigate(to: session.surfaceId) }
    }

    // MARK: - Cards View

    private func cardsView(sessions: [AgentSession], tick: Date) -> some View {
        let groups = viewModel.groupedByWorkspace(sessions)
        return VStack(alignment: .leading, spacing: 16) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    workspaceHeader(group: group, count: group.sessions.count)
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 260, maximum: 380), spacing: 10)
                    ], spacing: 10) {
                        ForEach(group.sessions) { session in
                            let accentColor = group.colorHex.flatMap { Color(hex: $0) }
                            cardItem(session: session, accentColor: accentColor, tick: tick)
                        }
                    }
                }
            }
        }
    }

    private func cardItem(session: AgentSession, accentColor: Color?,
                          tick: Date) -> some View {
        let ctx = session.tokenUsage.contextUtilization
        let activeSubagents = session.subagents.values.filter { $0.state.isActive }.count
        let totalSubagents = session.subagents.count
        let hasSpark = session.tokenUsage.history.count > 2

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                AgentStateDot(state: session.state)
                AgentIconBadge(agent: session.definition, size: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.definition.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if let model = session.model {
                        Text(shortModelName(model))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(stateLabel(session.state))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(stateColor(session.state))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(stateColor(session.state).opacity(0.12))
                    .clipShape(Capsule())
                Button {
                    PaneLocator.navigate(to: session.surfaceId)
                    AgentDashboardWindowController.shared.close()
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Task description
            Text(viewModel.taskDescription(for: session))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.4))

            // Stats row
            HStack(spacing: 10) {
                Label(viewModel.durationString(for: session, tick: tick), systemImage: "clock")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)

                if totalSubagents > 0 {
                    Label {
                        Text(activeSubagents > 0
                            ? "\(activeSubagents)/\(totalSubagents)"
                            : "\(totalSubagents)")
                            .foregroundStyle(activeSubagents > 0 ? .blue : .secondary)
                    } icon: {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(viewModel.tokenString(for: session.tokenUsage))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(viewModel.costString(for: session.tokenUsage))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.orange.opacity(0.9))
                }

                if hasSpark {
                    TokenSparkline(history: session.tokenUsage.history)
                        .frame(width: 40)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)

            // Context bar
            if ctx > 0 {
                VStack(spacing: 2) {
                    ContextUtilBar(utilization: ctx)
                    HStack {
                        Text("上下文").font(.system(size: 8)).foregroundStyle(.quaternary)
                        Spacer()
                        Text(String(format: "%.0f%%", ctx * 100))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 10).padding(.bottom, 8)
            } else {
                Spacer().frame(height: 8)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor)
            .opacity(colorScheme == .dark ? 0.3 : 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            if let accent = accentColor {
                Rectangle()
                    .fill(accent)
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            PaneLocator.navigate(to: session.surfaceId)
            AgentDashboardWindowController.shared.close()
        }
    }

    // MARK: - Historical Section

    private var historicalSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.vertical, 6)
            HStack(spacing: 6) {
                Text("HISTORY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
                Text("\(viewModel.historicalSessions.count)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.quaternary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color(nsColor: .separatorColor).opacity(0.4)))
            }
            VStack(spacing: 1) {
                ForEach(viewModel.historicalSessions.prefix(30)) { session in
                    historicalRow(session: session)
                }
            }
        }
    }

    private func historicalRow(session: PersistedSession) -> some View {
        let wsName = WorkspaceManager.shared.workspace(for: session.workspaceId)?.name
        return HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.green.opacity(0.5))
                Text(session.agentIcon).font(.system(size: 10))
                Text(session.agentName).font(.system(size: 10))
            }
            .frame(width: 130, alignment: .leading)

            Text(wsName ?? "—")
                .font(.system(size: 9)).foregroundStyle(.quaternary)
                .frame(width: 90, alignment: .leading)

            Text(viewModel.tokenString(for: session.tokenUsage))
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.quaternary)
                .frame(width: 55, alignment: .leading)

            Text(viewModel.costString(for: session.tokenUsage))
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.quaternary)
                .frame(width: 55, alignment: .leading)

            Spacer()

            Text(relativeTime(session.finishedAt))
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .opacity(0.75)
    }

    // MARK: - Helpers

    private func stateColor(_ state: AgentState) -> Color {
        switch state {
        case .working:   return .green
        case .idle:      return .yellow
        case .launching: return .blue
        case .done:      return .secondary
        case .error:     return .red
        }
    }

    private func stateLabel(_ state: AgentState) -> String {
        switch state {
        case .working:   return "working"
        case .idle:      return "idle"
        case .launching: return "launching"
        case .done:      return "done"
        case .error:     return "error"
        }
    }

    /// 将完整模型名缩短为可读标签，如 "claude-sonnet-4-6" → "sonnet-4-6"
    private func shortModelName(_ model: String) -> String {
        model.hasPrefix("claude-") ? String(model.dropFirst(7)) : model
    }

    private func formatTokens(_ n: Int) -> String {
        if n < 1000 { return "\(n)" }
        if n < 1_000_000 { return String(format: "%.1fk", Double(n) / 1000) }
        return String(format: "%.1fM", Double(n) / 1_000_000)
    }

    private func relativeTime(_ date: Date) -> String {
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 3600  { return "\(secs / 60)m" }
        if secs < 86400 { return "\(secs / 3600)h" }
        return "\(secs / 86400)d"
    }
}

// MARK: - Context Utilization Bar

private struct ContextUtilBar: View {
    let utilization: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.secondary.opacity(0.12))
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(barColor)
                    .frame(width: geo.size.width * CGFloat(max(0, min(1, utilization))))
                    .animation(.easeOut(duration: 0.4), value: utilization)
            }
        }
        .frame(height: 3)
    }

    private var barColor: Color {
        if utilization > 0.85 { return .red }
        if utilization > 0.65 { return .orange }
        return .green.opacity(0.75)
    }
}

// MARK: - Token Sparkline

private struct TokenSparkline: View {
    let history: [TokenSnapshot]

    var body: some View {
        Canvas { ctx, size in
            guard history.count > 1 else { return }
            let values = history.map { Double($0.inputTokens + $0.outputTokens) }
            let maxVal = values.max().map { max($0, 1) } ?? 1
            let step = size.width / Double(values.count - 1)

            var path = Path()
            for (i, val) in values.enumerated() {
                let x = Double(i) * step
                let y = size.height * (1.0 - val / maxVal)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else       { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path,
                with: .color(Color.secondary.opacity(0.45)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 18)
    }
}
