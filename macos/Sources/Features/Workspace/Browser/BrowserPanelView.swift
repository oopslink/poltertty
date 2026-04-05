// macos/Sources/Features/Workspace/Browser/BrowserPanelView.swift
import SwiftUI
import WebKit

struct BrowserPanelView: View {
    let workspaceId: UUID?
    @ObservedObject var browserStore: BrowserSurfaceStore
    var snapshotsForRestore: [BrowserTabSnapshot]
    var activeSnapshotId: UUID?
    var onClose: () -> Void

    @State private var currentURL: URL? = nil
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if let wsId = workspaceId {
                let mgr = browserStore.manager(
                    for: wsId,
                    snapshots: snapshotsForRestore.isEmpty ? nil : snapshotsForRestore
                )

                // ── Toolbar with Tab Strip ──
                BrowserPanelToolbar(
                    manager: mgr,
                    currentURL: $currentURL,
                    onClose: onClose
                )

                Divider()

                // ── Restore Banner ──
                if mgr.showRestorePrompt {
                    BrowserRestoreBanner(
                        tabCount: snapshotsForRestore.count,
                        onRestore: {
                            mgr.loadSnapshot(snapshotsForRestore, activeId: activeSnapshotId)
                        },
                        onDismiss: {
                            mgr.showRestorePrompt = false
                            if mgr.tabs.isEmpty { mgr.newTab() }
                        }
                    )
                    Divider()
                }

                // ── Active WebView ──
                if let activeTab = mgr.activeTab {
                    BrowserWebView(
                        webView: activeTab.webView,
                        currentURL: $currentURL,
                        canGoBack: $canGoBack,
                        canGoForward: $canGoForward,
                        onTitleUpdate: { title, url in
                            mgr.updateTab(id: activeTab.id, title: title, url: url)
                        }
                    )
                } else {
                    Spacer()
                }

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
