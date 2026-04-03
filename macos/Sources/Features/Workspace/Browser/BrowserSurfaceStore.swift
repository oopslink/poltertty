// macos/Sources/Features/Workspace/Browser/BrowserSurfaceStore.swift
import Foundation
import WebKit

/// Manages one WKWebView per workspace.
/// WebViews are lazily created on first open and kept alive until the workspace is deleted.
@MainActor
class BrowserSurfaceStore: ObservableObject {
    @Published private(set) var webViews: [UUID: WKWebView] = [:]

    /// Get or create the WKWebView for a workspace.
    func webView(for workspaceId: UUID) -> WKWebView {
        if let existing = webViews[workspaceId] {
            return existing
        }
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.allowsBackForwardNavigationGestures = true
        webViews[workspaceId] = wv
        return wv
    }

    /// Remove and release the WKWebView for a workspace (call on workspace deletion).
    func removeSurface(for workspaceId: UUID) {
        webViews[workspaceId]?.navigationDelegate = nil
        webViews.removeValue(forKey: workspaceId)
    }

    func hasSurface(for workspaceId: UUID) -> Bool {
        webViews[workspaceId] != nil
    }
}
