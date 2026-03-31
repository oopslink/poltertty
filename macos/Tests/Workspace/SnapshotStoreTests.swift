// macos/Tests/Workspace/SnapshotStoreTests.swift
import Testing
import Foundation
@testable import Ghostty

struct SnapshotStoreTests {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    @Test func roundtrip() throws {
        let entry = SnapshotEntry(
            id: UUID(),
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            windowFrame: SnapshotEntry.WindowFrame(CGRect(x: 10, y: 20, width: 1280, height: 800)),
            sidebarWidth: 240,
            sidebarVisible: true,
            tabs: [
                SnapshotEntry.PersistedTab(title: "main", titleLocked: false),
                SnapshotEntry.PersistedTab(title: "server", titleLocked: true),
            ],
            activeTabIndex: 1
        )

        let data = try encoder.encode(entry)
        let decoded = try decoder.decode(SnapshotEntry.self, from: data)

        #expect(decoded.id == entry.id)
        #expect(decoded.savedAt == entry.savedAt)
        #expect(decoded.windowFrame == entry.windowFrame)
        // 验证 CGRect 互转路径
        #expect(decoded.windowFrame?.cgRect == CGRect(x: 10, y: 20, width: 1280, height: 800))
        #expect(decoded.sidebarWidth == 240)
        #expect(decoded.sidebarVisible == true)
        #expect(decoded.tabs?.count == 2)
        #expect(decoded.tabs?[0].title == "main")
        #expect(decoded.tabs?[0].titleLocked == false)
        #expect(decoded.tabs?[1].title == "server")
        #expect(decoded.tabs?[1].titleLocked == true)
        #expect(decoded.activeTabIndex == 1)
    }

    @Test func nilTabsRoundtrip() throws {
        let entry = SnapshotEntry(
            id: UUID(),
            savedAt: Date(timeIntervalSince1970: 1_700_000_001),
            windowFrame: nil,
            sidebarWidth: 200,
            sidebarVisible: false,
            tabs: nil,
            activeTabIndex: nil
        )

        let data = try encoder.encode(entry)
        let decoded = try decoder.decode(SnapshotEntry.self, from: data)

        #expect(decoded.id == entry.id)
        #expect(decoded.savedAt == entry.savedAt)
        #expect(decoded.windowFrame == nil)
        #expect(decoded.sidebarWidth == 200)
        #expect(decoded.sidebarVisible == false)
        #expect(decoded.tabs == nil)
        #expect(decoded.activeTabIndex == nil)
    }

    // MARK: - SnapshotStore 测试

    @Test func storesSaveAndLoadLatest() throws {
        let (store, entry) = makeStoreWithEntry()
        try store.save(entry, screenshot: nil)
        let loaded = store.loadLatest()
        #expect(loaded?.id == entry.id)
        #expect(loaded?.sidebarWidth == entry.sidebarWidth)
    }

    @Test func storesMaxCountEnforced() throws {
        let (store, _) = makeStoreWithEntry()
        var entries: [SnapshotEntry] = []
        for i in 0..<7 {
            let e = makeEntry(savedAt: Date(timeIntervalSince1970: Double(i) * 60))
            entries.append(e)
            try store.save(e, screenshot: nil)
        }
        let all = store.loadAll()
        #expect(all.count == 5)
        #expect(all.first?.id == entries[2].id)  // 最旧的 2 条被淘汰
        #expect(all.last?.id == entries[6].id)
    }

    @Test func storesDeleteEntry() throws {
        let (store, _) = makeStoreWithEntry()
        let e1 = makeEntry()
        let e2 = makeEntry()
        try store.save(e1, screenshot: nil)
        try store.save(e2, screenshot: nil)
        store.delete(id: e1.id)
        let all = store.loadAll()
        #expect(all.count == 1)
        #expect(all[0].id == e2.id)
    }

    @Test func storesLoadAllOrder() throws {
        let (store, _) = makeStoreWithEntry()
        let older = makeEntry(savedAt: Date(timeIntervalSince1970: 1000))
        let newer = makeEntry(savedAt: Date(timeIntervalSince1970: 2000))
        try store.save(older, screenshot: nil)
        try store.save(newer, screenshot: nil)
        let all = store.loadAll()
        #expect(all[0].id == older.id)
        #expect(all[1].id == newer.id)
    }

    // MARK: - 辅助方法

    private func makeStoreWithEntry() -> (SnapshotStore, SnapshotEntry) {
        let workspaceId = UUID()
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let store = SnapshotStore(workspaceId: workspaceId, storageRootURL: tempDir)
        return (store, makeEntry())
    }

    private func makeEntry(savedAt: Date = Date()) -> SnapshotEntry {
        SnapshotEntry(
            id: UUID(),
            savedAt: savedAt,
            windowFrame: SnapshotEntry.WindowFrame(CGRect(x: 0, y: 0, width: 800, height: 600)),
            sidebarWidth: 240,
            sidebarVisible: true,
            tabs: [SnapshotEntry.PersistedTab(title: "zsh", titleLocked: false)],
            activeTabIndex: 0
        )
    }
}
