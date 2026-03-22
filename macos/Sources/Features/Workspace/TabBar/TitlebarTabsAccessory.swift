import AppKit
import SwiftUI

/// 将自定义 tab bar 嵌入 macOS titlebar 右侧区域
final class TitlebarTabsAccessory: NSTitlebarAccessoryViewController {
    private let tabBarViewModel: TabBarViewModel
    private let accentColor: Color
    private let onNewTab: () -> Void
    private let onCloseTab: (UUID) -> Void
    private let onSwitchTab: (UUID) -> Void

    init(
        tabBarViewModel: TabBarViewModel,
        accentColor: Color,
        onNewTab: @escaping () -> Void,
        onCloseTab: @escaping (UUID) -> Void,
        onSwitchTab: @escaping (UUID) -> Void
    ) {
        self.tabBarViewModel = tabBarViewModel
        self.accentColor = accentColor
        self.onNewTab = onNewTab
        self.onCloseTab = onCloseTab
        self.onSwitchTab = onSwitchTab
        super.init(nibName: nil, bundle: nil)
        self.layoutAttribute = .trailing
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let tabsView = TitlebarTabsView(
            viewModel: tabBarViewModel,
            accentColor: accentColor,
            onNewTab: onNewTab,
            onCloseTab: onCloseTab,
            onSwitchTab: onSwitchTab
        )
        let hosting = NSHostingView(rootView: tabsView)
        self.view = hosting
    }
}

/// Titlebar 内右侧 tab bar 视图（含分隔线 + underline + + 按钮）
struct TitlebarTabsView: View {
    @ObservedObject var viewModel: TabBarViewModel
    let accentColor: Color
    let onNewTab: () -> Void
    let onCloseTab: (UUID) -> Void
    let onSwitchTab: (UUID) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(viewModel.tabs) { tab in
                            TerminalTabItem(
                                tab: tab,
                                accentColor: accentColor,
                                isLastTab: viewModel.tabs.count == 1,
                                onSelect: { onSwitchTab(tab.id) },
                                onClose: { onCloseTab(tab.id) },
                                onRename: { viewModel.renameTab(tab.id, title: $0) },
                                onCloseOthers: {
                                    viewModel.tabs
                                        .filter { $0.id != tab.id }
                                        .forEach { onCloseTab($0.id) }
                                },
                                agentState: viewModel.agentState(for: tab.surfaceId)
                            )
                            .id(tab.id)
                            // 保留拖拽重排支持（与原 TerminalTabBar 一致）
                            .dropDestination(for: String.self) { items, _ in
                                guard let uuidStr = items.first,
                                      let sourceId = UUID(uuidString: uuidStr),
                                      let sourceIdx = viewModel.tabs.firstIndex(where: { $0.id == sourceId }),
                                      let targetIdx = viewModel.tabs.firstIndex(where: { $0.id == tab.id }),
                                      sourceIdx != targetIdx
                                else { return false }
                                let dest = sourceIdx < targetIdx ? targetIdx + 1 : targetIdx
                                viewModel.moveTab(from: IndexSet(integer: sourceIdx), to: dest)
                                return true
                            }
                        }
                    }
                }
                .onChange(of: viewModel.activeTabId) { id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                }
            }

            // "+" 新建 tab 按钮
            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 28)
            }
            .buttonStyle(.plain)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 0.5, height: 14)
            }
        }
        .frame(height: 28)
        .background(Color.clear)
    }
}
