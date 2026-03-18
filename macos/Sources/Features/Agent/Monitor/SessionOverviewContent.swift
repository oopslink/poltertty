// macos/Sources/Features/Agent/Monitor/SessionOverviewContent.swift
import SwiftUI

/// 跨 subagent 全局工具调用事件（供 Overview ActivityLog 使用）
struct RecentEventEntry {
    let time: Date
    let subagentName: String
    let toolName: String
    let isDone: Bool
}

struct SessionOverviewContent: View {
    let session: AgentSession
    var onSubagentTap: ((SubagentInfo) -> Void)? = nil

    @State private var tick = Date()
    @State private var subagentsExpanded: Bool = true
    @State private var activityExpanded: Bool = true
    @State private var graphExpanded: Bool = false
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    private var subagents: [SubagentInfo] {
        Array(session.subagents.values).sorted { $0.startedAt < $1.startedAt }
    }

    private var recentEvents: [RecentEventEntry] {
        var events: [RecentEventEntry] = []
        for sub in session.subagents.values {
            // subagent 创建事件（Agent tool call）
            events.append(RecentEventEntry(
                time: sub.startedAt,
                subagentName: String(sub.name.prefix(10)),
                toolName: "Agent",
                isDone: !sub.state.isActive
            ))
            // subagent 内部工具调用
            for call in sub.toolCalls {
                events.append(RecentEventEntry(
                    time: call.startedAt,
                    subagentName: String(sub.name.prefix(10)),
                    toolName: call.toolName,
                    isDone: call.isDone
                ))
            }
        }
        return events
            .sorted { $0.time > $1.time }
            .prefix(50)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statRow("总耗时", value: elapsedSinceStart)
                statRow("Cost",   value: costLabel)
                statRow("Tokens", value: tokensLabel)
                statRow("Context", value: String(format: "%.0f%%", session.tokenUsage.contextUtilization * 100))
                contextBar
                    .padding(.bottom, 8)
                Divider().padding(.vertical, 6)

                subagentsSection

                Divider().padding(.vertical, 6)
                Text("点击 subagent 查看详情 · Cmd+Click 并排对比")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)

                // MARK: - Activity Log（可折叠，固定高度）
                let events = recentEvents
                let totalToolCalls = session.subagents.count + session.subagents.values.reduce(0) { $0 + $1.toolCalls.count }
                if !events.isEmpty {
                    Divider().padding(.vertical, 6)
                    activitySection(events, total: totalToolCalls)
                }

                // MARK: - Agent Graph（可折叠，固定高度）
                if !session.subagents.isEmpty {
                    Divider().padding(.vertical, 6)
                    agentGraphSection
                }
            }
            .padding(12)
        }
        .onReceive(timer) { t in
            if session.state.isActive {
                tick = t
                // F1: 保底 token 更新（仅 active session；历史 session 的 isActive==false，不会触发）
                AgentService.shared.tokenTracker?.pollLiveTokens(surfaceId: session.surfaceId)
            }
        }
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 10, design: .monospaced)).foregroundStyle(.primary)
        }
        .padding(.bottom, 3)
    }

    private var contextBar: some View {
        let u = CGFloat(session.tokenUsage.contextUtilization)
        let color: Color = u < 0.55 ? (Color(hex: "#4caf50") ?? .green) : u < 0.75 ? .yellow : .red
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Color(.separatorColor)).frame(height: 3)
                RoundedRectangle(cornerRadius: 2).fill(color)
                    .frame(width: geo.size.width * u, height: 3)
            }
        }
        .frame(height: 3)
    }

    private func overviewRow(_ sub: SubagentInfo) -> some View {
        HStack(spacing: 6) {
            stateIcon(sub.state)
            Text(sub.name)
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: "#569cd6") ?? .blue)
                .lineLimit(1).truncationMode(.tail)
            stateBadge(sub.state)
            Spacer()
            Text(elapsed(sub)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func stateIcon(_ state: AgentState) -> some View {
        let (sym, col): (String, Color) = {
            switch state {
            case .done:    return ("checkmark", Color(hex: "#4caf50") ?? .green)
            case .error:   return ("xmark",     Color(hex: "#f44336") ?? .red)
            case .working: return ("circle.fill", Color(hex: "#ff9800") ?? .orange)
            default:       return ("circle", .secondary)
            }
        }()
        return Image(systemName: sym).font(.system(size: 9)).foregroundStyle(col)
    }

    private func stateBadge(_ state: AgentState) -> some View {
        let (label, bg, fg): (String, Color, Color) = {
            switch state {
            case .done:    return ("done",    Color(hex: "#1a2e1a") ?? .clear, Color(hex: "#4caf50") ?? .green)
            case .error:   return ("error",   Color(hex: "#2e1a1a") ?? .clear, Color(hex: "#f44336") ?? .red)
            case .working: return ("running", Color(hex: "#1a2535") ?? .clear, Color(hex: "#90bfff") ?? .blue)
            default:       return ("idle",    Color(.separatorColor).opacity(0.4), .secondary)
            }
        }()
        return Text(label)
            .font(.system(size: 8, weight: .medium))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(bg).foregroundStyle(fg)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var elapsedSinceStart: String {
        let secs = max(0, Int(tick.timeIntervalSince(session.startedAt)))
        if secs < 60 { return "\(secs)s" }
        return "\(secs/60)m \(secs%60)s"
    }

    private var costLabel: String {
        let d = NSDecimalNumber(decimal: session.tokenUsage.cost).doubleValue
        return d > 0 ? String(format: "$%.4f", d) : "—"
    }

    private var tokensLabel: String {
        let input = session.tokenUsage.inputTokens
        let output = session.tokenUsage.outputTokens
        guard input > 0 || output > 0 else { return "—" }
        return "↑\(formatK(input)) ↓\(formatK(output))"
    }

    private func formatK(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fK", Double(n) / 1000) : "\(n)"
    }

    private func elapsed(_ sub: SubagentInfo) -> String {
        let end = sub.finishedAt ?? tick
        let s = max(0, Int(end.timeIntervalSince(sub.startedAt)))
        return s < 60 ? "\(s)s" : "\(s/60)m\(s%60)s"
    }

    private static let eventTimeFmt: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "HH:mm:ss"
        return fmt
    }()

    // MARK: - Subagents Section（可折叠，固定高度）

    private var subagentsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { subagentsExpanded.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: subagentsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8)).foregroundStyle(.tertiary)
                    Text("SUBAGENTS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 4)

            if subagentsExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(subagents) { sub in
                        overviewRow(sub)
                            .onTapGesture { onSubagentTap?(sub) }
                            .contentShape(Rectangle())
                    }
                }
                .frame(maxHeight: 200)
                .clipped()
            }
        }
    }

    private func activitySection(_ events: [RecentEventEntry], total: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { activityExpanded.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: activityExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8)).foregroundStyle(.tertiary)
                    Text("ACTIVITY")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 4)

            if activityExpanded {
                eventLogSection(events, total: total)
                    .frame(maxHeight: 200)
                    .clipped()
            }
        }
    }

    private func eventLogSection(_ events: [RecentEventEntry], total: Int) -> some View {
        let fmt = Self.eventTimeFmt
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.offset) { _, ev in
                HStack(spacing: 4) {
                    Text(fmt.string(from: ev.time))
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                        .frame(width: 54, alignment: .leading)
                    Text(ev.subagentName)
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                        .lineLimit(1).truncationMode(.tail)
                    Text(ev.toolName)
                        .font(.system(size: 9)).foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    if ev.isDone {
                        Text("✓").font(.system(size: 9)).foregroundStyle(Color(hex: "#4caf50") ?? .green)
                    } else {
                        Text("⏳").font(.system(size: 9)).foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 1)
            }
            if total > 50 {
                Text("… and \(total - 50) more")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Agent Graph（可折叠，固定高度）

    private var agentGraphSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { graphExpanded.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: graphExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8)).foregroundStyle(.tertiary)
                    Text("AGENT GRAPH")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 4)

            if graphExpanded {
                AgentGraphView(session: session, tick: tick) { sub in
                    onSubagentTap?(sub)
                }
                .frame(height: 240)
                .clipped()
            }
        }
    }
}
