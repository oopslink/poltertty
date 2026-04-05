// macos/Sources/Features/Workspace/Browser/BrowserTabManager.swift
import Foundation
import WebKit

@MainActor
final class BrowserTabManager: ObservableObject {
    @Published private(set) var tabs: [BrowserTab] = []
    @Published private(set) var activeTabId: UUID?
    @Published var showRestorePrompt: Bool = false

    private let webViewFactory: () -> WKWebView

    init(webViewFactory: @escaping @MainActor () -> WKWebView = { WKWebView() }) {
        self.webViewFactory = webViewFactory
    }

    // MARK: - Private Helpers

    private func makeWebView() -> WKWebView {
        let wv = webViewFactory()
        wv.allowsBackForwardNavigationGestures = true
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"
        if #available(macOS 13.3, *) {
            wv.isInspectable = true
        }
        return wv
    }

    // MARK: - Public API

    @discardableResult
    func newTab(url: URL? = nil) -> UUID {
        let wv = makeWebView()
        var tab = BrowserTab(webView: wv)
        tab.url = url
        if let url {
            wv.load(URLRequest(url: url))
        }
        tabs.append(tab)
        activeTabId = tab.id
        return tab.id
    }

    /// 接受一个已存在的 WKWebView（如来自 window.open 的 createWebView 回调）
    @discardableResult
    func newTab(existingWebView wv: WKWebView) -> UUID {
        wv.allowsBackForwardNavigationGestures = true
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"
        if #available(macOS 13.3, *) {
            wv.isInspectable = true
        }
        let tab = BrowserTab(webView: wv)
        tabs.append(tab)
        activeTabId = tab.id
        return tab.id
    }

    func closeTab(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = activeTabId == id
        tabs[idx].webView.navigationDelegate = nil
        tabs.remove(at: idx)
        if wasActive {
            if tabs.isEmpty {
                newTab()
            } else {
                let newIdx = max(0, idx - 1)
                activeTabId = tabs[newIdx].id
            }
        }
    }

    func focusTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabId = id
    }

    var activeTab: BrowserTab? {
        tabs.first { $0.id == activeTabId }
    }

    // MARK: - Restore

    func loadSnapshot(_ snapshots: [BrowserTabSnapshot], activeId: UUID?) {
        // 清空旧 tabs，释放 WebView delegate
        for tab in tabs { tab.webView.navigationDelegate = nil }
        tabs.removeAll()

        for snap in snapshots {
            let wv = makeWebView()
            let tab = BrowserTab(id: snap.id, title: snap.title, url: snap.url, webView: wv)
            if let url = snap.url {
                wv.load(URLRequest(url: url))
            }
            tabs.append(tab)
        }
        if let activeId, tabs.contains(where: { $0.id == activeId }) {
            activeTabId = activeId
        } else {
            activeTabId = tabs.first?.id
        }
        showRestorePrompt = false
    }

    func currentSnapshot() -> [BrowserTabSnapshot] {
        tabs.map { BrowserTabSnapshot(from: $0) }
    }

    func prepareRestore(snapshots: [BrowserTabSnapshot]) {
        guard !snapshots.isEmpty else { return }
        showRestorePrompt = true
    }

    func updateTab(id: UUID, title: String?, url: URL?) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        if let title { tabs[idx].title = title }
        if let url   { tabs[idx].url = url }
    }
}
