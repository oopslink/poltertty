// macos/Tests/Workspace/BrowserTabManagerTests.swift
import Testing
import Foundation
import WebKit
@testable import Ghostty

@MainActor
struct BrowserTabManagerTests {

    // MARK: - newTab

    @Test func newTabCreatesTabAndFocuses() {
        let mgr = BrowserTabManager()
        #expect(mgr.tabs.isEmpty)
        let id = mgr.newTab()
        #expect(mgr.tabs.count == 1)
        #expect(mgr.tabs[0].id == id)
        #expect(mgr.activeTabId == id)
    }

    @Test func newTabWithURLSetsURL() {
        let mgr = BrowserTabManager()
        let url = URL(string: "https://example.com")!
        mgr.newTab(url: url)
        #expect(mgr.tabs[0].url == url)
    }

    @Test func secondNewTabFocusesNewTab() {
        let mgr = BrowserTabManager()
        _ = mgr.newTab()
        let id2 = mgr.newTab()
        #expect(mgr.tabs.count == 2)
        #expect(mgr.activeTabId == id2)
    }

    // MARK: - closeTab

    @Test func closeTabRemovesIt() {
        let mgr = BrowserTabManager()
        let id1 = mgr.newTab()
        _ = mgr.newTab()        // id2 成为 active
        // 关闭非 active 的 id1，active 不应改变
        mgr.closeTab(id: id1)
        #expect(mgr.tabs.count == 1)
        #expect(!mgr.tabs.contains(where: { $0.id == id1 }))
        #expect(mgr.activeTabId != id1)  // active 未被改变
    }

    @Test func closeActiveTabSwitchesToLeftNeighbor() {
        let mgr = BrowserTabManager()
        let id1 = mgr.newTab()
        let id2 = mgr.newTab()
        // active 是 id2
        mgr.closeTab(id: id2)
        #expect(mgr.tabs.count == 1)
        #expect(mgr.activeTabId == id1)
    }

    @Test func closeActiveTabWhenNoLeftNeighborSwitchesToRight() {
        let mgr = BrowserTabManager()
        let id1 = mgr.newTab()
        let id2 = mgr.newTab()
        mgr.focusTab(id: id1)        // active 是 id1（最左端）
        mgr.closeTab(id: id1)
        #expect(mgr.tabs.count == 1)
        #expect(mgr.activeTabId == id2)
    }

    @Test func closeLastTabCreatesNewBlankTab() {
        let mgr = BrowserTabManager()
        let id = mgr.newTab()
        mgr.closeTab(id: id)
        // 关闭最后一个 tab 时自动创建新空白 tab
        #expect(mgr.tabs.count == 1)
        #expect(mgr.tabs[0].url == nil)
        #expect(mgr.activeTabId == mgr.tabs[0].id)
    }

    // MARK: - focusTab

    @Test func focusTabUpdatesActiveId() {
        let mgr = BrowserTabManager()
        let id1 = mgr.newTab()
        _ = mgr.newTab()
        mgr.focusTab(id: id1)
        #expect(mgr.activeTabId == id1)
    }

    @Test func focusUnknownIdIsNoOp() {
        let mgr = BrowserTabManager()
        let id = mgr.newTab()
        mgr.focusTab(id: UUID())   // 不存在的 ID
        #expect(mgr.activeTabId == id)
    }

    // MARK: - activeTab

    @Test func activeTabReturnsCorrectTab() {
        let mgr = BrowserTabManager()
        let id1 = mgr.newTab()
        _ = mgr.newTab()
        mgr.focusTab(id: id1)
        #expect(mgr.activeTab?.id == id1)
    }

    // MARK: - Snapshot / Restore

    @Test func currentSnapshotReturnsAllTabs() {
        let mgr = BrowserTabManager()
        let url = URL(string: "https://example.com")!
        let id = mgr.newTab(url: url)
        mgr.updateTab(id: id, title: "Example", url: url)
        let snaps = mgr.currentSnapshot()
        #expect(snaps.count == 1)
        #expect(snaps[0].id == id)
        #expect(snaps[0].url == url)
        #expect(snaps[0].title == "Example")
    }

    @Test func currentSnapshotCapturesAllTabs() {
        let mgr = BrowserTabManager()
        _ = mgr.newTab()
        _ = mgr.newTab()
        _ = mgr.newTab()
        let snaps = mgr.currentSnapshot()
        #expect(snaps.count == 3)
    }

    @Test func prepareRestoreSetsPromptFlagWhenSnapshotsExist() {
        let mgr = BrowserTabManager()
        let snap = BrowserTabSnapshot(id: UUID(), url: URL(string: "https://a.com"), title: "A")
        mgr.prepareRestore(snapshots: [snap])
        #expect(mgr.showRestorePrompt == true)
        #expect(mgr.tabs.isEmpty)   // prepareRestore 不创建 tab
    }

    @Test func prepareRestoreDoesNothingForEmptySnapshots() {
        let mgr = BrowserTabManager()
        mgr.prepareRestore(snapshots: [])
        #expect(mgr.showRestorePrompt == false)
    }

    @Test func loadSnapshotCreatesTabs() {
        let mgr = BrowserTabManager()
        let id1 = UUID()
        let id2 = UUID()
        let snaps = [
            BrowserTabSnapshot(id: id1, url: URL(string: "https://a.com"), title: "A"),
            BrowserTabSnapshot(id: id2, url: nil, title: "B"),
        ]
        mgr.loadSnapshot(snaps, activeId: id2)
        #expect(mgr.tabs.count == 2)
        #expect(mgr.tabs[0].id == id1)
        #expect(mgr.tabs[1].id == id2)
        #expect(mgr.activeTabId == id2)
        #expect(mgr.showRestorePrompt == false)
    }

    @Test func loadSnapshotFallsBackToFirstTabIfActiveIdUnknown() {
        let mgr = BrowserTabManager()
        let snap = BrowserTabSnapshot(id: UUID(), url: nil, title: "X")
        mgr.loadSnapshot([snap], activeId: UUID())  // 不存在的 activeId
        #expect(mgr.activeTabId == snap.id)
    }

    @Test func loadSnapshotClearsExistingTabs() {
        let mgr = BrowserTabManager()
        _ = mgr.newTab()  // 先有一个 tab
        let snapId = UUID()
        let snap = BrowserTabSnapshot(id: snapId, url: nil, title: "Restored")
        mgr.loadSnapshot([snap], activeId: snapId)
        // 旧 tab 应被清除，只剩 restore 的 tab
        #expect(mgr.tabs.count == 1)
        #expect(mgr.tabs[0].id == snapId)
    }
}
