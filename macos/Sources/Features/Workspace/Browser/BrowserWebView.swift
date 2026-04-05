// macos/Sources/Features/Workspace/Browser/BrowserWebView.swift
import SwiftUI
import WebKit

/// NSViewRepresentable wrapping a pre-existing WKWebView.
/// 使用不可变容器 NSView，在 updateNSView 中交换 WKWebView 子视图，
/// 避免 SwiftUI identity 变化时 WKWebView frame 被重置为 zero。
struct BrowserWebView: NSViewRepresentable {
    let webView: WKWebView
    @Binding var currentURL: URL?
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    /// 页面标题或 URL 更新时回调，供调用方同步 tab 标题
    var onTitleUpdate: ((String, URL?) -> Void)?

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.autoresizesSubviews = true
        attach(webView, to: container, coordinator: context.coordinator)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        // 若 active tab 切换，将旧 WKWebView 换成新的
        if container.subviews.first !== webView {
            container.subviews.forEach { $0.removeFromSuperview() }
            attach(webView, to: container, coordinator: context.coordinator)
        }
        // 更新 coordinator 回调，始终指向当前 SwiftUI binding
        context.coordinator.onNavigationUpdate = {
            self.currentURL = self.webView.url
            self.canGoBack = self.webView.canGoBack
            self.canGoForward = self.webView.canGoForward
        }
        context.coordinator.onTitleUpdate = {
            let title = self.webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self.onTitleUpdate?(title.isEmpty ? "New Tab" : title, self.webView.url)
        }
        context.coordinator.observeTitle(of: webView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Private

    private func attach(_ webView: WKWebView, to container: NSView, coordinator: Coordinator) {
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = coordinator
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var onNavigationUpdate: (() -> Void)?
        var onTitleUpdate: (() -> Void)?

        private var titleObservation: NSKeyValueObservation?
        private weak var observedWebView: WKWebView?

        /// 观察 webView.title KVO，active tab 切换时重新绑定
        func observeTitle(of webView: WKWebView) {
            guard webView !== observedWebView else { return }
            observedWebView = webView
            titleObservation = webView.observe(\.title, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.onTitleUpdate?() }
            }
            // 立即同步（页面可能在绑定前已加载完成）
            onTitleUpdate?()
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            DispatchQueue.main.async { [weak self] in self?.onNavigationUpdate?() }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { [weak self] in
                self?.onNavigationUpdate?()
                self?.onTitleUpdate?()
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("[Browser] didFailProvisionalNavigation: \(error)")
            DispatchQueue.main.async { [weak self] in self?.onNavigationUpdate?() }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("[Browser] didFail: \(error)")
            DispatchQueue.main.async { [weak self] in self?.onNavigationUpdate?() }
        }
    }
}
