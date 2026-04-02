// macos/Sources/Features/Agent/Monitor/SessionOverviewContent.swift
import SwiftUI

/// 跨 subagent 全局工具调用事件（供 Overview ActivityLog 使用）
struct RecentEventEntry {
    enum Kind {
        case toolCall       // 普通工具调用
        case compact        // 上下文压缩
        case permDenied     // 权限拒绝
    }
    let time: Date
    let subagentName: String
    let toolName: String
    let isDone: Bool
    var kind: Kind = .toolCall
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
        // Subagent 事件
        for sub in session.subagents.values {
            events.append(RecentEventEntry(
                time: sub.startedAt,
                subagentName: String(sub.name.prefix(10)),
                toolName: "Agent",
                isDone: !sub.state.isActive
            ))
            for call in sub.toolCalls {
                events.append(RecentEventEntry(
                    time: call.startedAt,
                    subagentName: String(sub.name.prefix(10)),
                    toolName: call.toolName,
                    isDone: call.isDone
                ))
            }
        }
        // 顶层工具调用（非 subagent）
        for call in session.topLevelToolCalls {
            events.append(RecentEventEntry(
                time: call.startedAt,
                subagentName: "",
                toolName: call.toolName,
                isDone: call.isDone
            ))
        }
        // 上下文压缩事件
        for compactAt in session.compactEvents {
            events.append(RecentEventEntry(
                time: compactAt,
                subagentName: "",
                toolName: "context compacted",
                isDone: true,
                kind: .compact
            ))
        }
        return events
            .sorted { $0.time > $1.time }
            .prefix(50)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Stats grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                    statCell("Duration", value: elapsedSinceStart)
                    statCell("Cost", value: costLabel)
                    statCell("Tokens", value: tokensLabel)
                    statCell("Context", value: String(format: "%.0f%%", session.tokenUsage.contextUtilization * 100))
                }
                .padding(.bottom, 6)

                contextBar
                    .padding(.bottom, 8)

                Divider().padding(.vertical, 6)
                subagentsSection

                Divider().padding(.vertical, 6)
                Text("Click to view  ·  ⌘Click to compare")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)

                let events = recentEvents
                let totalToolCalls = session.subagents.count + session.subagents.values.reduce(0) { $0 + $1.toolCalls.count } + session.topLevelToolCalls.count
                if !events.isEmpty {
                    Divider().padding(.vertical, 6)
                    activitySection(events, total: totalToolCalls)
                }

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
                AgentService.shared.tokenTracker?.pollLiveTokens(surfaceId: session.surfaceId)
            }
        }
    }

    // MARK: - Stat Cell

    private func statCell(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color(.separatorColor).opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - Context Bar

    private var contextBar: some View {
        let u = CGFloat(session.tokenUsage.contextUtilization)
        let color: Color = u < 0.55 ? AgentColors.success : u < 0.75 ? AgentColors.idle : AgentColors.error
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(.separatorColor).opacity(0.3))
                    .frame(height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: max(0, geo.size.width * u), height: 4)
                    .animation(.easeInOut(duration: 0.4), value: u)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Subagent Overview Row

    private func overviewRow(_ sub: SubagentInfo) -> some View {
        HStack(spacing: 6) {
            stateIcon(sub.state)
            Text(sub.name)
                .font(.system(size: 10))
                .foregroundStyle(AgentColors.linkBlue)
                .lineLimit(1).truncationMode(.tail)
            stateBadge(sub.state)
            Spacer()
            Text(elapsed(sub))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }

    private func stateIcon(_ state: AgentState) -> some View {
        let (sym, col): (String, Color) = {
            switch state {
            case .done:    return ("checkmark.circle.fill", AgentColors.success)
            case .error:   return ("xmark.circle.fill", AgentColors.error)
            case .working: return ("circle.fill", AgentColors.active)
            default:       return ("circle", .secondary)
            }
        }()
        return Image(systemName: sym)
            .font(.system(size: 9))
            .foregroundStyle(col)
    }

    private func stateBadge(_ state: AgentState) -> some View {
        let (label, bg, fg): (String, Color, Color) = {
            switch state {
            case .done:    return ("done",    AgentColors.successBadgeBg,   AgentColors.success)
            case .error:   return ("error",   AgentColors.errorBadgeBg,     AgentColors.error)
            case .working: return ("running", AgentColors.activeBadgeBg,    AgentColors.active)
            default:       return ("idle",    AgentColors.idleBadgeBg,      .secondary)
            }
        }()
        return Text(label)
            .font(.system(size: 8, weight: .medium))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(bg)
            .foregroundStyle(fg)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    // MARK: - Computed Labels

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

    // MARK: - Subagents Section

    private var subagentsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("SUBAGENTS", expanded: $subagentsExpanded)
                .padding(.bottom, 4)

            if subagentsExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(subagents) { sub in
                            overviewRow(sub)
                                .onTapGesture { onSubagentTap?(sub) }
                                .contentShape(Rectangle())
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
    }

    // MARK: - Activity Section

    private func activitySection(_ events: [RecentEventEntry], total: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                sectionHeader("ACTIVITY", expanded: $activityExpanded)
                if session.deniedToolCount > 0 {
                    Text("\(session.deniedToolCount) denied")
                        .font(.system(size: 8, weight: .medium))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(AgentColors.errorBadgeBg)
                        .foregroundStyle(AgentColors.error)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .padding(.bottom, 4)

            if activityExpanded {
                // 使用 ScrollView 替代 .clipped()，符合 ui-ux-rules.md 规范
                ScrollView {
                    eventLogSection(events, total: total)
                }
                .frame(maxHeight: 200)
            }
        }
    }

    private func eventLogSection(_ events: [RecentEventEntry], total: Int) -> some View {
        let fmt = Self.eventTimeFmt
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.offset) { idx, ev in
                HStack(spacing: 4) {
                    Text(fmt.string(from: ev.time))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 54, alignment: .leading)
                    Text(ev.subagentName)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                        .lineLimit(1).truncationMode(.tail)
                    switch ev.kind {
                    case .compact:
                        // 上下文压缩：橙色加刷新图标
                        Label(ev.toolName, systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    case .permDenied:
                        // 权限拒绝：红色加锁图标
                        Label(ev.toolName, systemImage: "lock.slash")
                            .font(.system(size: 9))
                            .foregroundStyle(AgentColors.error)
                            .lineLimit(1)
                    case .toolCall:
                        Text(ev.toolName)
                            .font(.system(size: 9))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    Spacer()
                    switch ev.kind {
                    case .compact:
                        EmptyView()
                    case .permDenied:
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(AgentColors.error)
                    case .toolCall:
                        if ev.isDone {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(AgentColors.success)
                        } else {
                            Circle()
                                .fill(AgentColors.active.opacity(0.7))
                                .frame(width: 5, height: 5)
                        }
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .background(AgentColors.rowStripeBg.opacity(idx % 2 == 0 ? 0 : 1))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            if total > 50 {
                Text("… and \(total - 50) more")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Agent Graph Section

    private var agentGraphSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("AGENT GRAPH", expanded: $graphExpanded)
                .padding(.bottom, 4)

            if graphExpanded {
                AgentGraphView(session: session, tick: tick) { sub in
                    onSubagentTap?(sub)
                }
                .frame(height: 240)
            }
        }
    }

    // MARK: - Section Header Helper

    private func sectionHeader(_ title: String, expanded: Binding<Bool>) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) { expanded.wrappedValue.toggle() }
        }) {
            HStack(spacing: 4) {
                Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
