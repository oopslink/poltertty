// macos/Sources/Features/Workspace/Browser/BrowserPanelView.swift
import SwiftUI
import WebKit

struct BrowserPanelView: View {
    let workspaceId: UUID?
    @ObservedObject var browserStore: BrowserSurfaceStore
    var onClose: () -> Void

    @State private var currentURL: URL? = nil
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if let wsId = workspaceId {
                let wv = browserStore.webView(for: wsId)
                BrowserPanelToolbar(
                    webView: wv,
                    canGoBack: canGoBack,
                    canGoForward: canGoForward,
                    currentURL: $currentURL,
                    onClose: onClose
                )
                Divider()
                BrowserWebView(
                    webView: wv,
                    currentURL: $currentURL,
                    canGoBack: $canGoBack,
                    canGoForward: $canGoForward
                )
            } else {
                noWorkspaceView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var noWorkspaceView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "globe")
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No workspace selected")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
