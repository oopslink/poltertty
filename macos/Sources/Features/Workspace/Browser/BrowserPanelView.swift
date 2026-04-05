// macos/Sources/Features/Workspace/Browser/BrowserPanelView.swift
import SwiftUI
import WebKit

struct BrowserPanelView: View {
    let workspaceId: UUID?
    @ObservedObject var browserStore: BrowserSurfaceStore
    var snapshotsForRestore: [BrowserTabSnapshot]
    var activeSnapshotId: UUID?
    var isExpanded: Bool = false
    var onToggleExpand: () -> Void = {}
    var onClose: () -> Void

    var body: some View {
        if let wsId = workspaceId {
            let mgr = browserStore.manager(
                for: wsId,
                snapshots: snapshotsForRestore.isEmpty ? nil : snapshotsForRestore
            )
            BrowserPanelContent(
                manager: mgr,
                snapshotsForRestore: snapshotsForRestore,
                activeSnapshotId: activeSnapshotId,
                isExpanded: isExpanded,
                onToggleExpand: onToggleExpand,
                onClose: onClose
            )
        } else {
            noWorkspaceView
        }
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

/// 独立子 view，@ObservedObject 观察 manager，确保 showRestorePrompt 等状态变化时正确重渲染。
private struct BrowserPanelContent: View {
    @ObservedObject var manager: BrowserTabManager
    var snapshotsForRestore: [BrowserTabSnapshot]
    var activeSnapshotId: UUID?
    var isExpanded: Bool = false
    var onToggleExpand: () -> Void = {}
    var onClose: () -> Void

    @State private var currentURL: URL? = nil
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // ── Toolbar with Tab Strip ──
            BrowserPanelToolbar(
                manager: manager,
                currentURL: $currentURL,
                isExpanded: isExpanded,
                onToggleExpand: onToggleExpand,
                onClose: onClose
            )

            Divider()

            // ── Restore Banner ──
            if manager.showRestorePrompt {
                BrowserRestoreBanner(
                    tabCount: snapshotsForRestore.count,
                    onRestore: {
                        manager.loadSnapshot(snapshotsForRestore, activeId: activeSnapshotId)
                    },
                    onDismiss: {
                        manager.showRestorePrompt = false
                        if manager.tabs.isEmpty { manager.newTab() }
                    }
                )
                Divider()
            }

            // ── Active WebView ──
            if let activeTab = manager.activeTab {
                BrowserWebView(
                    webView: activeTab.webView,
                    currentURL: $currentURL,
                    canGoBack: $canGoBack,
                    canGoForward: $canGoForward,
                    onTitleUpdate: { title, url in
                        manager.updateTab(id: activeTab.id, title: title, url: url)
                    }
                )
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
