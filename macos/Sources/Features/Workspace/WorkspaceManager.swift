// macos/Sources/Features/Workspace/WorkspaceManager.swift
import AppKit
import Foundation
import Combine

class WorkspaceManager: ObservableObject {
    static let shared = WorkspaceManager()

    @Published var workspaces: [WorkspaceModel] = []
    /// Maps workspace ID to its owning NSWindow
    var activeWindows: [UUID: WeakWindow] = [:]

    class WeakWindow {
        weak var window: NSWindow?
        init(_ window: NSWindow) { self.window = window }
    }

    private let storageDir: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        self.storageDir = PolterttyConfig.shared.workspaceDir
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        ensureStorageDir()
        loadAll()
    }

    // MARK: - CRUD

    @discardableResult
    func create(name: String, rootDir: String, colorHex: String = "#FF6B6B", description: String = "") -> WorkspaceModel {
        var workspace = WorkspaceModel(name: name, rootDir: rootDir, colorHex: colorHex)
        workspace.description = description
        workspaces.append(workspace)
        save(workspace)
        return workspace
    }

    func update(_ workspace: WorkspaceModel) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        var updated = workspace
        updated.updatedAt = Date()
        workspaces[idx] = updated
        save(updated)
    }

    func delete(id: UUID) {
        workspaces.removeAll { $0.id == id }
        activeWindows.removeValue(forKey: id)
        let path = snapshotPath(for: id)
        try? FileManager.default.removeItem(atPath: path)
    }

    func workspace(for id: UUID) -> WorkspaceModel? {
        workspaces.first { $0.id == id }
    }

    // MARK: - Window Tracking

    func registerWindow(_ window: NSWindow, for workspaceId: UUID) {
        activeWindows[workspaceId] = WeakWindow(window)
        touchLastActive(workspaceId)
        objectWillChange.send()
    }

    func unregisterWindow(for workspaceId: UUID) {
        activeWindows.removeValue(forKey: workspaceId)
        objectWillChange.send()
    }

    func windowForWorkspace(_ id: UUID) -> NSWindow? {
        activeWindows[id]?.window
    }

    func workspaceId(for window: NSWindow) -> UUID? {
        activeWindows.first { $0.value.window === window }?.key
    }

    func touchLastActive(_ id: UUID) {
        guard let idx = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[idx].lastActiveAt = Date()
    }

    // MARK: - Snapshot Persistence

    func saveSnapshot(for workspaceId: UUID, window: NSWindow, sidebarWidth: CGFloat, sidebarVisible: Bool) {
        guard var workspace = workspace(for: workspaceId) else { return }
        workspace.updatedAt = Date()

        let snapshot = WorkspaceSnapshot(
            workspace: workspace,
            windowFrame: WorkspaceSnapshot.WindowFrame(from: window.frame),
            sidebarWidth: sidebarWidth,
            sidebarVisible: sidebarVisible
        )

        let path = snapshotPath(for: workspaceId)
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: URL(fileURLWithPath: path))
        }

        // Update in-memory model
        if let idx = workspaces.firstIndex(where: { $0.id == workspaceId }) {
            workspaces[idx] = workspace
        }
    }

    func loadSnapshot(for workspaceId: UUID) -> WorkspaceSnapshot? {
        let path = snapshotPath(for: workspaceId)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? decoder.decode(WorkspaceSnapshot.self, from: data)
    }

    // MARK: - Private

    private func snapshotPath(for id: UUID) -> String {
        (storageDir as NSString).appendingPathComponent("\(id.uuidString).json")
    }

    private func ensureStorageDir() {
        try? FileManager.default.createDirectory(
            atPath: storageDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func loadAll() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: storageDir) else { return }
        for file in files where file.hasSuffix(".json") {
            let path = (storageDir as NSString).appendingPathComponent(file)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let snapshot = try? decoder.decode(WorkspaceSnapshot.self, from: data) else { continue }
            workspaces.append(snapshot.workspace)
        }
        workspaces.sort { $0.createdAt < $1.createdAt }
    }

    private func save(_ workspace: WorkspaceModel) {
        let snapshot = WorkspaceSnapshot(
            workspace: workspace,
            sidebarWidth: CGFloat(PolterttyConfig.shared.sidebarWidth),
            sidebarVisible: PolterttyConfig.shared.sidebarVisible
        )
        let path = snapshotPath(for: workspace.id)
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
