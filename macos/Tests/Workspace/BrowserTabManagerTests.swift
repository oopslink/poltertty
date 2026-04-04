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
        let id = mgr.newTab(url: url)
        #expect(mgr.tabs[0].url == url)
        _ = id
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
        let id = mgr.newTab()
        mgr.closeTab(id: id)
        #expect(mgr.tabs.isEmpty == false) // 最後の tab を閉じると新 blank tab が生成される
    }

    @Test func closeActiveTabSwitchesToLeftNeighbor() {
        let mgr = BrowserTabManager()
        let id1 = mgr.newTab()
        let id2 = mgr.newTab()
        // active は id2
        mgr.closeTab(id: id2)
        #expect(mgr.tabs.count == 1)
        #expect(mgr.activeTabId == id1)
    }

    @Test func closeActiveTabWhenNoLeftNeighborSwitchesToRight() {
        let mgr = BrowserTabManager()
        let id1 = mgr.newTab()
        let id2 = mgr.newTab()
        mgr.focusTab(id: id1)        // active は id1（左端）
        mgr.closeTab(id: id1)
        #expect(mgr.tabs.count == 1)
        #expect(mgr.activeTabId == id2)
    }

    @Test func closeLastTabCreatesNewBlankTab() {
        let mgr = BrowserTabManager()
        let id = mgr.newTab()
        mgr.closeTab(id: id)
        // 最後の tab を閉じると新しい blank tab が自動生成される
        #expect(mgr.tabs.count == 1)
        #expect(mgr.tabs[0].url == nil)
        #expect(mgr.activeTabId == mgr.tabs[0].id)
    }

    // MARK: - focusTab

    @Test func focusTabUpdatesActiveId() {
        let mgr = BrowserTabManager()
        let id1 = mgr.newTab()
        let id2 = mgr.newTab()
        mgr.focusTab(id: id1)
        #expect(mgr.activeTabId == id1)
        _ = id2
    }

    @Test func focusUnknownIdIsNoOp() {
        let mgr = BrowserTabManager()
        let id = mgr.newTab()
        mgr.focusTab(id: UUID())   // 存在しない ID
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
}
