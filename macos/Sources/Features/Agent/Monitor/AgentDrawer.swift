// macos/Sources/Features/Agent/Monitor/AgentDrawer.swift
import SwiftUI

struct AgentDrawer: View {
    @ObservedObject var viewModel: AgentMonitorViewModel

    var body: some View {
        if !viewModel.selectedItems.isEmpty {
            HStack(spacing: 0) {
                Divider()
                VStack(spacing: 0) {
                    drawerHeader
                    Divider()
                    if let session = viewModel.unifiedSession {
                        // 统一两列视图：左 overview + 右 subagent detail
                        SessionDetailView(session: session, viewModel: viewModel)
                    } else {
                        // 对比模式：多面板并排
                        HStack(spacing: 0) {
                            ForEach(viewModel.selectedItems) { item in
                                AgentDrawerPanel(item: item, onClose: { viewModel.closePanel(item) }, viewModel: viewModel)
                                .id(item.id)
                                if item != viewModel.selectedItems.last {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .frame(width: viewModel.drawerWidth)
                .background(Color(.windowBackgroundColor))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.selectedItems.count)
            }
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    // MARK: - Global header

    private var drawerHeader: some View {
        HStack(spacing: 8) {
            if let state = singleItemState {
                if state.isActive {
                    AgentStateDot(state: state)
                } else {
                    Circle().fill(Color.secondary.opacity(0.4)).frame(width: 6, height: 6)
                }
            }
            Text(headerTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Button(action: viewModel.closeDrawer) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .frame(width: 16, height: 16)
                    .background(Color(.separatorColor).opacity(0.3))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Color(.windowBackgroundColor))
    }

    private var headerTitle: String {
        guard viewModel.selectedItems.count == 1, let first = viewModel.selectedItems.first else {
            return "对比模式"
        }
        switch first {
        case .sessionOverview(let s):       return s.definition.name
        case .subagentDetail(let s, _):     return s.definition.name
        }
    }

    private var singleItemState: AgentState? {
        guard viewModel.selectedItems.count == 1, let first = viewModel.selectedItems.first else {
            return nil
        }
        switch first {
        case .sessionOverview(let s):       return s.state
        case .subagentDetail(_, let sub):   return sub.state
        }
    }
}
