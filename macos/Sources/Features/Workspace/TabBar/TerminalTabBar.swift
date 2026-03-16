import SwiftUI

struct TerminalTabBar: View {
    @ObservedObject var viewModel: TabBarViewModel
    let accentColor: Color
    let onNewTab: () -> Void
    let onCloseTab: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(viewModel.tabs) { tab in
                            TerminalTabItem(
                                tab: tab,
                                accentColor: accentColor,
                                isLastTab: viewModel.tabs.count == 1,
                                onSelect: { viewModel.selectTab(tab.id) },
                                onClose: { onCloseTab(tab.id) },
                                onRename: { viewModel.renameTab(tab.id, title: $0) },
                                onCloseOthers: {
                                    viewModel.tabs
                                        .filter { $0.id != tab.id }
                                        .forEach { onCloseTab($0.id) }
                                }
                            )
                            .id(tab.id)
                            .dropDestination(for: String.self) { items, _ in
                                handleDrop(items: items, onto: tab)
                            }
                        }

                        Spacer(minLength: 0)

                        // "+" 新建 tab 按钮，固定在最右侧
                        Button(action: onNewTab) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(height: 36)
                .onChange(of: viewModel.activeTabId) { id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                }
            }

            Divider()
        }
        .background(.background.opacity(0.95))
    }

    private func handleDrop(items: [String], onto target: TabItem) -> Bool {
        guard let uuidStr = items.first,
              let sourceId = UUID(uuidString: uuidStr),
              let sourceIdx = viewModel.tabs.firstIndex(where: { $0.id == sourceId }),
              let targetIdx = viewModel.tabs.firstIndex(where: { $0.id == target.id }),
              sourceIdx != targetIdx
        else { return false }
        viewModel.moveTab(from: IndexSet(integer: sourceIdx), to: targetIdx)
        return true
    }
}
