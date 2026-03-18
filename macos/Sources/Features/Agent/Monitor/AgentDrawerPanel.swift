// macos/Sources/Features/Agent/Monitor/AgentDrawerPanel.swift
import SwiftUI

enum DrawerTab: String, CaseIterable {
    case output   = "Messages"
    case trace    = "Trace"
    case overview = "Overview"
}

struct AgentDrawerPanel: View {
    let item: DrawerItem
    let onClose: () -> Void
    let viewModel: AgentMonitorViewModel
    @State private var tab: DrawerTab
    @State private var tick = Date()
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    init(item: DrawerItem, onClose: @escaping () -> Void, viewModel: AgentMonitorViewModel) {
        self.item = item
        self.onClose = onClose
        self.viewModel = viewModel
        switch item {
        case .sessionOverview:   _tab = State(initialValue: .overview)
        case .subagentDetail:    _tab = State(initialValue: .output)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 单面板 sessionOverview 时全局 header 已显示标题，跳过重复的 panelHeader
            if viewModel.selectedItems.count > 1 || isSubagentDetail {
                panelHeader
            }
            // sessionOverview 只有一个 tab，不需要 tab bar
            if availableTabs.count > 1 {
                tabBar
                Divider()
            }
            contentArea
        }
        .background(Color(.windowBackgroundColor))
        .onReceive(timer) { t in if case .subagentDetail(_, let sub) = item, sub.state.isActive { tick = t } }
    }

    private var isSubagentDetail: Bool {
        if case .subagentDetail = item { return true }
        return false
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 6) {
            statusDot
            Text(titleText)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1).truncationMode(.tail)
            Spacer()
            if case .subagentDetail(_, let sub) = item {
                metricsRow(sub)
            }
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 9))
            }
            .buttonStyle(.plain).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color(.windowBackgroundColor).opacity(0.95))
    }

    @ViewBuilder
    private var statusDot: some View {
        switch item {
        case .sessionOverview(let s):
            AgentStateDot(state: s.state)
        case .subagentDetail(_, let sub):
            AgentStateDot(state: sub.state)
        }
    }

    private var titleText: String {
        switch item {
        case .sessionOverview(let s):       return s.definition.name
        case .subagentDetail(_, let sub):   return sub.name
        }
    }

    private static let metricsFmt: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "HH:mm:ss"
        return fmt
    }()

    private func metricsRow(_ sub: SubagentInfo) -> some View {
        let fmt = Self.metricsFmt
        let startStr = fmt.string(from: sub.startedAt)
        let endStr = sub.finishedAt.map { fmt.string(from: $0) }
        let elapsed: String = {
            let end = sub.finishedAt ?? tick
            let s = max(0, Int(end.timeIntervalSince(sub.startedAt)))
            return s < 60 ? "\(s)s" : "\(s/60)m\(s%60)s"
        }()
        return HStack(spacing: 6) {
            // 时间段
            if let end = endStr {
                Text("\(startStr) → \(end)")
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            } else {
                Text(startStr)
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            }
            Text("·").foregroundStyle(.tertiary).font(.system(size: 9))
            // 耗时
            Label(elapsed, systemImage: "clock").font(.system(size: 9)).foregroundStyle(.secondary)
            // 工具调用数
            if sub.toolCalls.count > 0 {
                Label("\(sub.toolCalls.count)", systemImage: "wrench").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Tab bar

    private var availableTabs: [DrawerTab] {
        switch item {
        case .sessionOverview:  return [.overview]
        case .subagentDetail:   return [.output, .trace]
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(availableTabs, id: \.self) { t in
                Button(action: { tab = t }) {
                    Text(t.rawValue)
                        .font(.system(size: 10))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .foregroundStyle(tab == t ? .primary : .secondary)
                        .overlay(alignment: .bottom) {
                            if tab == t {
                                Rectangle().fill(Color.accentColor).frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        switch item {
        case .sessionOverview(let session):
            SessionOverviewContent(session: session) { sub in
                viewModel.selectSubagentInSidebar(sub, in: session)
            }
        case .subagentDetail(let session, let sub):
            switch tab {
            case .output:    SubagentMessagesView(session: session, subagent: sub)
            case .trace:     SubagentTraceContent(subagent: sub)
            case .overview:  EmptyView()
            }
        }
    }
}
