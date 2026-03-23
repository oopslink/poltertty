import AppKit
import SwiftUI

// MARK: - 宽度追踪器

/// AppKit 侧观察 NSHostingView 的实际渲染宽度，传给 SwiftUI 用于计算可见 tab 数
final class ToolbarWidthTracker: ObservableObject {
    @Published var availableWidth: CGFloat = 400
}

// MARK: - NSToolbar 代理

/// 通过 NSToolbar + .unifiedCompact 将自定义 tab bar 合并进 titlebar。
/// 布局：[workspace名] [flexibleSpace] [tabs + ... + 按钮]
final class WorkspaceToolbarDelegate: NSObject, NSToolbarDelegate {
    private let tabBarViewModel: TabBarViewModel
    private let workspaceName: String
    private let accentColor: Color
    private let onNewTab: () -> Void
    private let onCloseTab: (UUID) -> Void
    private let onSwitchTab: (UUID) -> Void
    private let widthTracker = ToolbarWidthTracker()

    init(
        tabBarViewModel: TabBarViewModel,
        workspaceName: String,
        accentColor: Color,
        onNewTab: @escaping () -> Void,
        onCloseTab: @escaping (UUID) -> Void,
        onSwitchTab: @escaping (UUID) -> Void
    ) {
        self.tabBarViewModel = tabBarViewModel
        self.workspaceName = workspaceName
        self.accentColor = accentColor
        self.onNewTab = onNewTab
        self.onCloseTab = onCloseTab
        self.onSwitchTab = onSwitchTab
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.workspaceBar]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.workspaceBar]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == .workspaceBar else {
            return NSToolbarItem(itemIdentifier: itemIdentifier)
        }

        let barView = WorkspaceBarView(
            viewModel: tabBarViewModel,
            widthTracker: widthTracker,
            workspaceName: workspaceName,
            accentColor: accentColor,
            onNewTab: onNewTab,
            onCloseTab: onCloseTab,
            onSwitchTab: onSwitchTab
        )
        let hosting = NSHostingView(rootView: barView)
        // 低 hugging = 愿意拉伸填满 toolbar；低 compression = 可被压缩
        hosting.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hosting.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // 观察实际渲染宽度，传给 SwiftUI 计算可见 tab 数
        hosting.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: hosting,
            queue: .main
        ) { [weak hosting, weak widthTracker] _ in
            guard let hosting, let widthTracker else { return }
            let w = hosting.frame.width
            if w > 0, abs(widthTracker.availableWidth - w) > 1 {
                widthTracker.availableWidth = w
            }
        }

        let item = NSToolbarItem(itemIdentifier: .workspaceBar)
        item.view = hosting
        item.isBordered = false
        item.visibilityPriority = .user
        return item
    }
}

private extension NSToolbarItem.Identifier {
    static let workspaceBar = NSToolbarItem.Identifier("WorkspaceBar")
}

// MARK: - 完整 bar 视图：[workspace名] [spacer] [tabs] [...] [+]

struct WorkspaceBarView: View {
    @ObservedObject var viewModel: TabBarViewModel
    @ObservedObject var widthTracker: ToolbarWidthTracker
    let workspaceName: String
    let accentColor: Color
    let onNewTab: () -> Void
    let onCloseTab: (UUID) -> Void
    let onSwitchTab: (UUID) -> Void

    private static let tabWidth: CGFloat = 96
    private static let plusWidth: CGFloat = 32
    private static let overflowWidth: CGFloat = 36
    // workspace 名 + padding 的大致宽度，用于计算 tab 可用空间
    private var titleReservedWidth: CGFloat {
        CGFloat(workspaceName.count) * 8 + 24  // 粗略估算
    }

    var body: some View {
        let tabsAvailable = max(widthTracker.availableWidth - titleReservedWidth, 0)
        let layout = computeLayout(availableWidth: tabsAvailable)
        HStack(spacing: 0) {
            // Workspace 名称（左对齐）
            Text(workspaceName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)

            // tab 少时推到右侧，tab 多时压缩到 0
            Spacer(minLength: 0)

            ForEach(Array(layout.visible.enumerated()), id: \.element.id) { index, tab in
                let nextIsActive = index + 1 < layout.visible.count && layout.visible[index + 1].isActive
                let isLast = index == layout.visible.count - 1
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
                    agentState: viewModel.agentState(for: tab.surfaceId),
                    isNextActive: nextIsActive,
                    isLastVisible: isLast
                )
                .id(tab.id)
            }

            if !layout.overflow.isEmpty {
                overflowButton(tabs: layout.overflow, count: layout.overflow.count)
            }

            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: Self.plusWidth, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 0.5, height: 14)
            }
        }
        .frame(height: 28)
    }

    // MARK: - 溢出按钮

    @ViewBuilder
    private func overflowButton(tabs: [TabItem], count: Int) -> some View {
        Button {
            showOverflowMenu(tabs: tabs)
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .medium))
                Text("\(count)")
                    .font(.system(size: 10))
            }
            .foregroundColor(.secondary)
            .frame(width: Self.overflowWidth, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func showOverflowMenu(tabs: [TabItem]) {
        let menu = NSMenu()
        for tab in tabs {
            let item = NSMenuItem(title: tab.title, action: nil, keyEquivalent: "")
            item.state = tab.isActive ? .on : .off
            item.target = OverflowMenuTarget.shared
            item.representedObject = tab.id
            item.action = #selector(OverflowMenuTarget.menuItemClicked(_:))
            OverflowMenuTarget.shared.onSelect = { [onSwitchTab] id in onSwitchTab(id) }
            menu.addItem(item)
        }
        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: NSApp.keyWindow?.contentView ?? NSView())
        }
    }

    // MARK: - 布局计算

    private func computeLayout(availableWidth: CGFloat) -> (visible: [TabItem], overflow: [TabItem]) {
        let allTabs = viewModel.tabs
        guard !allTabs.isEmpty else { return ([], []) }

        let maxWithout = Int(floor((availableWidth - Self.plusWidth) / Self.tabWidth))
        if maxWithout >= allTabs.count {
            return (allTabs, [])
        }

        let maxVisible = max(Int(floor((availableWidth - Self.plusWidth - Self.overflowWidth) / Self.tabWidth)), 1)
        let activeIdx = allTabs.firstIndex { $0.isActive } ?? 0

        let windowStart: Int
        if activeIdx < maxVisible {
            windowStart = 0
        } else {
            windowStart = min(activeIdx - maxVisible + 1, allTabs.count - maxVisible)
        }
        let windowEnd = min(windowStart + maxVisible, allTabs.count)

        let visible = Array(allTabs[windowStart..<windowEnd])
        var overflow: [TabItem] = []
        if windowStart > 0 {
            overflow.append(contentsOf: allTabs[0..<windowStart])
        }
        if windowEnd < allTabs.count {
            overflow.append(contentsOf: allTabs[windowEnd..<allTabs.count])
        }
        return (visible, overflow)
    }
}

// MARK: - NSMenu 回调

private class OverflowMenuTarget: NSObject {
    static let shared = OverflowMenuTarget()
    var onSelect: ((UUID) -> Void)?

    @objc func menuItemClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onSelect?(id)
    }
}
