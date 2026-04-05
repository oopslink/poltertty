// macos/Sources/Features/Workspace/Browser/BrowserWebView.swift
import SwiftUI
import WebKit

/// NSViewRepresentable wrapping a pre-existing WKWebView.
/// Receives the WKWebView instance from BrowserSurfaceStore so the view
/// survives SwiftUI re-renders without losing page state.
struct BrowserWebView: NSViewRepresentable {
    let webView: WKWebView
    @Binding var currentURL: URL?
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    /// 页面标题或 URL 更新时回调，供调用方同步 tab 标题
    var onTitleUpdate: ((String, URL?) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        webView.autoresizingMask = [.width, .height]
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // WKWebView instance is managed externally; no recreation needed.
        // Update coordinator bindings so they always reference the current SwiftUI bindings.
        context.coordinator.onNavigationUpdate = { [weak nsView] in
            guard let wv = nsView else { return }
            self.currentURL = wv.url
            self.canGoBack = wv.canGoBack
            self.canGoForward = wv.canGoForward
        }
        context.coordinator.onTitleUpdate = { [weak nsView] in
            guard let wv = nsView else { return }
            let title = wv.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self.onTitleUpdate?(title.isEmpty ? "New Tab" : title, wv.url)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var onNavigationUpdate: (() -> Void)?
        var onTitleUpdate: (() -> Void)?

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            DispatchQueue.main.async { [weak webView, weak self] in
                guard webView != nil else { return }
                self?.onNavigationUpdate?()
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { [weak webView, weak self] in
                guard webView != nil else { return }
                self?.onNavigationUpdate?()
                self?.onTitleUpdate?()
            }
        }
    }
}
