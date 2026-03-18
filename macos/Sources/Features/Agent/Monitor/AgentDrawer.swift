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
                    HStack(spacing: 0) {
                        ForEach(viewModel.selectedItems) { item in
                            AgentDrawerPanel(item: item) {
                                viewModel.closePanel(item)
                            }
                            .id(item.id)
                            if item != viewModel.selectedItems.last {
                                Divider()
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
            Text(headerTitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            // 布局切换按钮（上下分屏暂不实现，保留 UI）
            HStack(spacing: 3) {
                layoutBtn(icon: "square.split.2x1", isActive: true)
                layoutBtn(icon: "square.split.1x2", isActive: false)
                    .opacity(0.4)  // disabled
            }
            Button(action: viewModel.closeDrawer) {
                Image(systemName: "xmark").font(.system(size: 10))
            }
            .buttonStyle(.plain).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(.windowBackgroundColor))
    }

    private var headerTitle: String {
        guard viewModel.selectedItems.count == 1, let first = viewModel.selectedItems.first else {
            return "对比模式"
        }
        switch first {
        case .sessionOverview(let s):   return s.definition.name
        case .subagentDetail(let s, _): return s.definition.name
        }
    }

    private func layoutBtn(icon: String, isActive: Bool) -> some View {
        Image(systemName: icon)
            .font(.system(size: 10))
            .padding(4)
            .background(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
