// macos/Sources/Features/Workspace/WorkspaceManager.swift
import AppKit
import Foundation
import Combine

class WorkspaceManager: ObservableObject {
    static let shared = WorkspaceManager()

    @Published var workspaces: [WorkspaceModel] = []
    /// Maps workspace ID to its owning NSWindow
    var activeWindows: [UUID: WeakWindow] = [:]

    // MARK: - File Browser ViewModels (per-workspace)
    private var fileBrowserViewModels: [UUID: FileBrowserViewModel] = [:]

    func fileBrowserViewModel(for workspaceId: UUID) -> FileBrowserViewModel {
        if let existing = fileBrowserViewModels[workspaceId] { return existing }
        let ws = workspace(for: workspaceId)
        let vm = FileBrowserViewModel(
            rootDir: ws?.rootDirExpanded ?? "",
            isVisible: ws?.fileBrowserVisible ?? false,
            panelWidth: ws?.fileBrowserWidth ?? 260
        )
        fileBrowserViewModels[workspaceId] = vm
        return vm
    }

    func removeFileBrowserViewModel(for workspaceId: UUID) {
        fileBrowserViewModels[workspaceId]?.stop()
        fileBrowserViewModels.removeValue(forKey: workspaceId)
    }

    /// Only formal (non-temporary) workspaces
    var formalWorkspaces: [WorkspaceModel] {
        workspaces.filter { !$0.isTemporary }
    }

    /// Only temporary workspaces
    var temporaryWorkspaces: [WorkspaceModel] {
        workspaces.filter { $0.isTemporary }
    }

    /// Whether any temporary workspaces exist (controls sidebar section visibility)
    var hasTemporaryWorkspaces: Bool {
        workspaces.contains { $0.isTemporary }
    }

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

    private static let temporaryColors = [
        "#FF6B6B", "#4ECDC4", "#FFD93D", "#6BCB77",
        "#7AA2F7", "#BB9AF7", "#FF9A8B", "#F59E0B"
    ]

    /// Create a temporary workspace with auto-generated name and random color
    @discardableResult
    func createTemporary(rootDir: String = "~") -> WorkspaceModel {
        let name = nextScratchName()
        let color = Self.temporaryColors.randomElement() ?? "#F59E0B"
        var workspace = WorkspaceModel(name: name, rootDir: rootDir, colorHex: color, isTemporary: true)
        workspace.icon = "⏱"
        workspaces.append(workspace)
        // Temporary workspaces are NOT persisted to disk
        return workspace
    }

    private func nextScratchName() -> String {
        let existing = temporaryWorkspaces.map { $0.name }
        if !existing.contains("scratch") { return "scratch" }
        var counter = 2
        while existing.contains("scratch-\(counter)") {
            counter += 1
        }
        return "scratch-\(counter)"
    }

    /// Convert a temporary workspace to formal (persistent)
    func convertToFormal(id: UUID, newName: String) {
        guard let idx = workspaces.firstIndex(where: { $0.id == id && $0.isTemporary }) else { return }
        workspaces[idx].isTemporary = false
        workspaces[idx].name = newName
        workspaces[idx].updatedAt = Date()
        save(workspaces[idx])
    }

    /// Destroy all temporary workspaces (called on app quit)
    func destroyAllTemporary() {
        let tempIds = temporaryWorkspaces.map { $0.id }
        for id in tempIds {
            activeWindows.removeValue(forKey: id)
        }
        workspaces.removeAll { $0.isTemporary }
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
        removeFileBrowserViewModel(for: id)
        let path = snapshotPath(for: id)
        try? FileManager.default.removeItem(atPath: path)
    }

    func workspace(for id: UUID) -> WorkspaceModel? {
        workspaces.first { $0.id == id }
    }

    // MARK: - Window Tracking

    func registerWindow(_ window: NSWindow, for workspaceId: UUID) {
        let isNew = activeWindows[workspaceId]?.window == nil
        activeWindows[workspaceId] = WeakWindow(window)
        if isNew {
            objectWillChange.send()
        }
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

        // Update in-memory model
        if let idx = workspaces.firstIndex(where: { $0.id == workspaceId }) {
            workspaces[idx] = workspace
        }

        // Temporary workspaces are not persisted to disk
        guard !workspace.isTemporary else { return }

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
        // Temporary workspaces are not persisted
        guard !workspace.isTemporary else { return }
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
