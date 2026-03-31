// macos/Sources/Features/Workspace/SnapshotStore/SnapshotStore.swift
import AppKit
import Foundation

/// 管理单个 Workspace 的历史快照，最多保存 maxCount 条（超出自动淘汰最旧的）
///
/// 所有文件操作在内部串行队列中执行，线程安全。
final class SnapshotStore {
    static let maxCount = 5

    private let snapshotsDir: URL
    private let fm = FileManager.default

    /// 内部串行队列，保证并发安全
    private let queue: DispatchQueue

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// - Parameters:
    ///   - workspaceId: Workspace 的 UUID
    ///   - storageRootURL: WorkspaceManager 的 storageDir（PolterttyConfig.workspaceDir 对应的 URL）
    init(workspaceId: UUID, storageRootURL: URL) {
        snapshotsDir = storageRootURL
            .appendingPathComponent(workspaceId.uuidString)
            .appendingPathComponent("snapshots")
        queue = DispatchQueue(label: "com.poltertty.snapshotstore.\(workspaceId.uuidString)")
    }

    // MARK: - Index（维护快照 ID 的有序列表）

    private var indexURL: URL { snapshotsDir.appendingPathComponent("index.json") }

    /// 读取 index.json，失败返回空数组
    private func loadIndex() -> [UUID] {
        guard let data = try? Data(contentsOf: indexURL),
              let ids = try? Self.decoder.decode([UUID].self, from: data)
        else { return [] }
        return ids
    }

    /// 将快照 ID 列表写入 index.json
    private func saveIndex(_ ids: [UUID]) throws {
        let data = try Self.encoder.encode(ids)
        try data.write(to: indexURL, options: .atomic)
    }

    // MARK: - CRUD

    /// 保存新快照（超出 maxCount 自动淘汰最旧），线程安全
    func save(_ entry: SnapshotEntry, screenshot: Data?) throws {
        try queue.sync {
            try fm.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)

            // 先写文件，再更新 index，降低 index 与文件不一致的风险
            let entryURL = snapshotsDir.appendingPathComponent("\(entry.id.uuidString).json")
            let data = try Self.encoder.encode(entry)
            try data.write(to: entryURL, options: .atomic)

            if let screenshotData = screenshot {
                let screenshotURL = snapshotsDir.appendingPathComponent("\(entry.id.uuidString).jpg")
                try screenshotData.write(to: screenshotURL, options: .atomic)
            }

            // 追加新 id，超出 maxCount 淘汰最旧的一条
            var ids = loadIndex()
            ids.append(entry.id)
            if ids.count > Self.maxCount {
                let oldestId = ids.removeFirst()
                removeFiles(for: oldestId)
            }
            try saveIndex(ids)
        }
    }

    /// 按时间从旧到新返回所有快照（遵照 index 顺序）
    func loadAll() -> [SnapshotEntry] {
        queue.sync {
            loadIndex().compactMap { id in
                let url = snapshotsDir.appendingPathComponent("\(id.uuidString).json")
                guard let data = try? Data(contentsOf: url),
                      let entry = try? Self.decoder.decode(SnapshotEntry.self, from: data)
                else { return nil }
                return entry
            }
        }
    }

    /// 返回最新的快照（index 最后一条）
    func loadLatest() -> SnapshotEntry? {
        queue.sync {
            guard let lastId = loadIndex().last else { return nil }
            let url = snapshotsDir.appendingPathComponent("\(lastId.uuidString).json")
            guard let data = try? Data(contentsOf: url),
                  let entry = try? Self.decoder.decode(SnapshotEntry.self, from: data)
            else { return nil }
            return entry
        }
    }

    /// 返回指定快照的截图
    func screenshot(for entryId: UUID) -> NSImage? {
        queue.sync {
            let url = snapshotsDir.appendingPathComponent("\(entryId.uuidString).jpg")
            return NSImage(contentsOf: url)
        }
    }

    /// 删除单条快照及其截图，并更新 index
    func delete(id: UUID) {
        queue.sync {
            var ids = loadIndex()
            ids.removeAll { $0 == id }
            removeFiles(for: id)
            try? saveIndex(ids)
        }
    }

    // MARK: - 私有辅助

    /// 删除指定 id 对应的 .json 和 .jpg 文件（调用方负责加锁）
    private func removeFiles(for id: UUID) {
        let jsonURL = snapshotsDir.appendingPathComponent("\(id.uuidString).json")
        let jpgURL = snapshotsDir.appendingPathComponent("\(id.uuidString).jpg")
        try? fm.removeItem(at: jsonURL)
        try? fm.removeItem(at: jpgURL)
    }
}
