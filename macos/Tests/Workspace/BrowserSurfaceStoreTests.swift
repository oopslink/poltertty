// macos/Tests/Workspace/BrowserSurfaceStoreTests.swift
import Testing
import Foundation
import WebKit
@testable import Ghostty

@MainActor
struct BrowserSurfaceStoreTests {

    // MARK: - manager(for:) 懒创建

    @Test func managerIsCreatedOnFirstAccess() {
        let store = BrowserSurfaceStore()
        let wsId = UUID()
        let mgr = store.manager(for: wsId)
        // 懒创建后应该存在
        #expect(store.managers[wsId] != nil)
        // 同一 wsId 应返回同一实例
        #expect(store.manager(for: wsId) === mgr)
    }

    @Test func differentWorkspacesGetDifferentManagers() {
        let store = BrowserSurfaceStore()
        let id1 = UUID()
        let id2 = UUID()
        let mgr1 = store.manager(for: id1)
        let mgr2 = store.manager(for: id2)
        #expect(mgr1 !== mgr2)
    }

    @Test func managerWithoutSnapshotsCreatesBlankTab() {
        let store = BrowserSurfaceStore()
        let wsId = UUID()
        let mgr = store.manager(for: wsId)
        // 无快照时应自动创建一个空白 tab
        #expect(mgr.tabs.count == 1)
        #expect(mgr.tabs[0].url == nil)
        #expect(mgr.showRestorePrompt == false)
    }

    // MARK: - 快照恢复提示

    @Test func managerWithSnapshotsSetsRestorePrompt() {
        let store = BrowserSurfaceStore()
        let wsId = UUID()
        let snaps = [
            BrowserTabSnapshot(id: UUID(), url: URL(string: "https://example.com"), title: "Example"),
            BrowserTabSnapshot(id: UUID(), url: nil, title: "New Tab"),
        ]
        let mgr = store.manager(for: wsId, snapshots: snaps)
        // 有快照时不应自动创建 tab，而是等待用户确认恢复
        #expect(mgr.showRestorePrompt == true)
        #expect(mgr.tabs.isEmpty)
    }

    @Test func managerWithEmptySnapshotsCreatesBlankTab() {
        let store = BrowserSurfaceStore()
        let wsId = UUID()
        // 明确传入空数组 → 等同于无快照
        let mgr = store.manager(for: wsId, snapshots: [])
        #expect(mgr.showRestorePrompt == false)
        #expect(mgr.tabs.count == 1)
    }

    @Test func managerWithNilSnapshotsCreatesBlankTab() {
        let store = BrowserSurfaceStore()
        let wsId = UUID()
        let mgr = store.manager(for: wsId, snapshots: nil)
        #expect(mgr.showRestorePrompt == false)
        #expect(mgr.tabs.count == 1)
    }

    // MARK: - 已存在的 manager 不受 snapshots 参数影响

    @Test func subsequentCallWithSnapshotsDoesNotResetExistingManager() {
        let store = BrowserSurfaceStore()
        let wsId = UUID()
        // 第一次调用：无快照，创建空白 tab
        let mgr = store.manager(for: wsId)
        #expect(mgr.tabs.count == 1)
        // 第二次调用：传入快照 → 不应重置已存在的 manager
        let snaps = [BrowserTabSnapshot(id: UUID(), url: URL(string: "https://a.com"), title: "A")]
        let mgr2 = store.manager(for: wsId, snapshots: snaps)
        #expect(mgr2 === mgr)             // 同一实例
        #expect(mgr2.tabs.count == 1)     // 未被重置
        #expect(mgr2.showRestorePrompt == false)  // prompt 未被触发
    }

    // MARK: - removeManager

    @Test func removeManagerDeletesFromStore() {
        let store = BrowserSurfaceStore()
        let wsId = UUID()
        _ = store.manager(for: wsId)
        #expect(store.managers[wsId] != nil)
        store.removeManager(for: wsId)
        #expect(store.managers[wsId] == nil)
    }

    @Test func removeManagerClearsDelegatesOnAllTabs() {
        let store = BrowserSurfaceStore()
        let wsId = UUID()
        let mgr = store.manager(for: wsId)
        // 确保有 tab（有 webView）
        #expect(mgr.tabs.count == 1)
        let webView = mgr.tabs[0].webView
        // 设一个 navigationDelegate，removeManager 应清除它
        class MockDelegate: NSObject, WKNavigationDelegate {}
        let delegate = MockDelegate()
        webView.navigationDelegate = delegate
        // removeManager 内部应将所有 tab.webView.navigationDelegate 置 nil
        store.removeManager(for: wsId)
        #expect(webView.navigationDelegate == nil)
    }

    @Test func removeNonExistentManagerIsNoOp() {
        let store = BrowserSurfaceStore()
        // 不应 crash
        store.removeManager(for: UUID())
    }

    // MARK: - 多 workspace 隔离

    @Test func multipleWorkspacesOperateIndependently() {
        let store = BrowserSurfaceStore()
        let id1 = UUID()
        let id2 = UUID()

        let mgr1 = store.manager(for: id1)
        let mgr2 = store.manager(for: id2)

        // id1 新建一个带 URL 的 tab
        let url = URL(string: "https://localhost:3000")!
        mgr1.newTab(url: url)
        // id2 不受影响
        #expect(mgr2.tabs.count == 1)   // 只有初始空白 tab
        #expect(mgr1.tabs.count == 2)   // 初始 + 新建

        // 删除 id1 不影响 id2
        store.removeManager(for: id1)
        #expect(store.managers[id1] == nil)
        #expect(store.managers[id2] != nil)
    }
}
