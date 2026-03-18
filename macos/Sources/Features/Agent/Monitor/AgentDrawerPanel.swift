// macos/Sources/Features/Agent/Monitor/AgentDrawerPanel.swift
import SwiftUI

enum DrawerTab: String, CaseIterable {
    case output = "Output"
    case trace  = "Trace"
    case prompt = "Prompt"
    case overview = "Overview"
}

struct AgentDrawerPanel: View {
    let item: DrawerItem
    let onClose: () -> Void
    @State private var tab: DrawerTab

    init(item: DrawerItem, onClose: @escaping () -> Void) {
        self.item = item
        self.onClose = onClose
        switch item {
        case .sessionOverview:   _tab = State(initialValue: .overview)
        case .subagentDetail:    _tab = State(initialValue: .output)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            tabBar
            Divider()
            contentArea
        }
        .background(Color(.windowBackgroundColor))
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

    private func metricsRow(_ sub: SubagentInfo) -> some View {
        let elapsed: String = {
            let end = sub.finishedAt ?? Date()
            let s = max(0, Int(end.timeIntervalSince(sub.startedAt)))
            return s < 60 ? "\(s)s" : "\(s/60)m\(s%60)s"
        }()
        return HStack(spacing: 6) {
            Label(elapsed, systemImage: "clock").font(.system(size: 9)).foregroundStyle(.secondary)
            Label("\(sub.toolCalls.count)", systemImage: "wrench").font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }

    // MARK: - Tab bar

    private var availableTabs: [DrawerTab] {
        switch item {
        case .sessionOverview:  return [.overview]
        case .subagentDetail:   return [.output, .trace, .prompt]
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
            SessionOverviewContent(session: session)
        case .subagentDetail(let session, let sub):
            switch tab {
            case .output:    SubagentOutputContent(session: session, subagent: sub)
            case .trace:     SubagentTraceContent(subagent: sub)
            case .prompt:    SubagentPromptContent(subagent: sub)
            case .overview:  EmptyView()
            }
        }
    }
}
