// macos/Sources/Features/Agent/Monitor/SessionDetailView.swift
import SwiftUI

/// 统一两列视图：左列 Session Overview，右列选中 subagent 的 Messages/Trace
struct SessionDetailView: View {
    let session: AgentSession
    @ObservedObject var viewModel: AgentMonitorViewModel
    @State private var tab: Tab = .messages

    enum Tab: String, CaseIterable {
        case messages = "Messages"
        case trace = "Trace"
    }

    private var selectedSub: SubagentInfo? {
        guard let id = viewModel.selectedSubagentId else { return nil }
        return session.subagents[id]
    }

    private var sortedSubagents: [SubagentInfo] {
        Array(session.subagents.values).sorted { $0.startedAt < $1.startedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            HStack(spacing: 0) {
                overviewColumn
                    .frame(maxWidth: .infinity)
                Divider()
                detailColumn
                    .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if viewModel.selectedSubagentId == nil {
                viewModel.selectedSubagentId = sortedSubagents.first?.id
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { t in
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

    // MARK: - Overview Column (左列)

    private var overviewColumn: some View {
        SessionOverviewContent(session: session) { sub in
            viewModel.selectedSubagentId = sub.id
        }
    }

    // MARK: - Detail Column (右列)

    @ViewBuilder
    private var detailColumn: some View {
        if let sub = selectedSub {
            switch tab {
            case .messages:
                SubagentMessagesView(session: session, subagent: sub)
            case .trace:
                SubagentTraceContent(subagent: sub)
            }
        } else if session.subagents.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Text("等待 subagent 启动…")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            VStack(spacing: 8) {
                Spacer()
                Text("点击左侧 subagent 查看详情")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}
