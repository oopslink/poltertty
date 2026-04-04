// macos/Sources/Features/Workspace/Browser/BrowserPanelToolbar.swift
import SwiftUI
import WebKit

private let minTabWidth: CGFloat = 52
private let maxTabWidth: CGFloat = 110
// 工具栏固定控件区估算宽度：+ (22) + divider (9) + ‹ (22) + › (22) + ↺ (22) + 地址栏 (min 80) + ✕ (22) = ~199
private let fixedControlsWidth: CGFloat = 200

struct BrowserPanelToolbar: View {
    @ObservedObject var manager: BrowserTabManager
    @Binding var currentURL: URL?
    var onClose: () -> Void

    @State private var addressInput: String = ""
    @FocusState private var isEditingAddress: Bool
    @State private var availableTabWidth: CGFloat = 200

    var body: some View {
        HStack(spacing: 0) {
            // ── Tab Strip（弹性）──
            tabStrip
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { availableTabWidth = geo.size.width }
                            .onChange(of: geo.size.width) { availableTabWidth = $0 }
                    }
                )
                .frame(maxWidth: .infinity)

            // ── New Tab Button ──
            Button {
                manager.newTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 28)
            }
            .buttonStyle(.plain)
            .help("New Tab")

            // ── Divider ──
            Divider()
                .frame(height: 14)
                .padding(.horizontal, 4)

            // ── Back ──
            Button { manager.activeTab?.webView.goBack() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(canGoBack ? Color.primary : Color.secondary.opacity(0.4))
                    .frame(width: 22, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!canGoBack)
            .help("Back")

            // ── Forward ──
            Button { manager.activeTab?.webView.goForward() } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(canGoForward ? Color.primary : Color.secondary.opacity(0.4))
                    .frame(width: 22, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!canGoForward)
            .help("Forward")

            // ── Reload ──
            Button { manager.activeTab?.webView.reload() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 22, height: 28)
            }
            .buttonStyle(.plain)
            .help("Reload")

            // ── Address Bar ──
            TextField("Enter URL", text: $addressInput)
                .onSubmit { navigate(to: addressInput) }
                .focused($isEditingAddress)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isEditingAddress ? Color.accentColor : Color.clear, lineWidth: 1)
                )
                .frame(minWidth: 60, maxWidth: .infinity)
                .onChange(of: currentURL) { newURL in
                    if !isEditingAddress {
                        addressInput = newURL?.absoluteString ?? ""
                    }
                }
                .onChange(of: isEditingAddress) { editing in
                    if editing { addressInput = currentURL?.absoluteString ?? "" }
                }
                .onAppear { addressInput = currentURL?.absoluteString ?? "" }

            // ── Close Panel ──
            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 28)
            }
            .buttonStyle(.plain)
            .help("Close Panel")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Tab Strip

    @ViewBuilder
    private var tabStrip: some View {
        let visible = visibleTabs
        let overflow = overflowTabs

        HStack(spacing: 2) {
            ForEach(visible) { tab in
                tabButton(tab: tab)
            }
            if !overflow.isEmpty {
                BrowserTabOverflowMenu(
                    overflowTabs: overflow,
                    activeTabId: manager.activeTabId,
                    onSelect: { manager.focusTab(id: $0) }
                )
            }
        }
        .padding(.leading, 2)
    }

    @ViewBuilder
    private func tabButton(tab: BrowserTab) -> some View {
        let isActive = tab.id == manager.activeTabId
        HStack(spacing: 3) {
            Text(tab.title.isEmpty ? "New Tab" : tab.title)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isActive ? Color.primary : Color.secondary)

            Button {
                manager.closeTab(id: tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Close Tab")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(minWidth: minTabWidth, maxWidth: maxTabWidth)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isActive
                      ? Color(nsColor: .controlBackgroundColor)
                      : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isActive
                                ? Color(nsColor: .separatorColor)
                                : Color.clear,
                                lineWidth: 0.5)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { manager.focusTab(id: tab.id) }
    }

    // MARK: - 溢出计算

    private var maxVisibleCount: Int {
        max(1, Int(availableTabWidth / minTabWidth))
    }

    private var visibleTabs: [BrowserTab] {
        let tabs = manager.tabs
        guard tabs.count > maxVisibleCount else { return tabs }
        // Active tab 始终保留在可见区域
        var result: [BrowserTab] = []
        var remaining = maxVisibleCount
        if let active = manager.activeTab {
            result.append(active)
            remaining -= 1
        }
        for tab in tabs {
            guard remaining > 0 else { break }
            if tab.id != manager.activeTabId {
                result.append(tab)
                remaining -= 1
            }
        }
        // 按原始 tabs 顺序排列
        return tabs.filter { t in result.contains(where: { $0.id == t.id }) }
    }

    private var overflowTabs: [BrowserTab] {
        let visible = visibleTabs
        return manager.tabs.filter { t in !visible.contains(where: { $0.id == t.id }) }
    }

    // MARK: - 导航辅助

    private var canGoBack: Bool { manager.activeTab?.webView.canGoBack ?? false }
    private var canGoForward: Bool { manager.activeTab?.webView.canGoForward ?? false }

    private func navigate(to input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let urlString = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: urlString) else { return }
        manager.activeTab?.webView.load(URLRequest(url: url))
    }
}
