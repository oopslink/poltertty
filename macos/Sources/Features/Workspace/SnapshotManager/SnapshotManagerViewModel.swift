// macos/Sources/Features/Workspace/SnapshotManager/SnapshotManagerViewModel.swift
import Foundation
import AppKit

/// 单个 Workspace 的快照分组（用于 SnapshotManagerView 展示）
struct WorkspaceSnapshotGroup: Identifiable {
    let workspace: WorkspaceModel
    var entries: [SnapshotEntry]   // 从新到旧排列
    var id: UUID { workspace.id }
}

/// SnapshotManagerView 的数据层，负责加载、删除快照，并持有「从此创建」的选中状态
@MainActor
final class SnapshotManagerViewModel: ObservableObject {
    @Published var groups: [WorkspaceSnapshotGroup] = []

    /// 触发「从此创建」sheet 的选中条目（entry + workspace）
    struct SelectedEntry: Identifiable {
        let id = UUID()
        let entry: SnapshotEntry
        let workspace: WorkspaceModel
    }
    @Published var selectedEntry: SelectedEntry? = nil

    private var storageRootURL: URL {
        URL(fileURLWithPath: PolterttyConfig.shared.workspaceDir)
    }

    /// 加载所有非临时 workspace 的快照，过滤掉没有快照的 workspace（后台执行 I/O，不阻塞主线程）
    func load() async {
        let rootURL = storageRootURL
        let workspaces = WorkspaceManager.shared.workspaces.filter { !$0.isTemporary }
        let loaded: [WorkspaceSnapshotGroup] = await Task.detached(priority: .userInitiated) {
            workspaces.compactMap { workspace in
                let store = SnapshotStore(workspaceId: workspace.id, storageRootURL: rootURL)
                let entries = store.loadAll()
                    .sorted { $0.savedAt > $1.savedAt }   // 从新到旧
                guard !entries.isEmpty else { return nil }
                return WorkspaceSnapshotGroup(workspace: workspace, entries: entries)
            }
        }.value
        groups = loaded
    }

    /// 返回指定快照的截图（同步磁盘读取，调用方应在异步任务中调用）
    nonisolated func screenshot(for entryId: UUID, workspaceId: UUID, storageRootURL: URL) -> NSImage? {
        SnapshotStore(workspaceId: workspaceId, storageRootURL: storageRootURL)
            .screenshot(for: entryId)
    }

    /// 删除指定快照，删后重新加载数据
    func delete(entryId: UUID, workspaceId: UUID) {
        SnapshotStore(workspaceId: workspaceId, storageRootURL: storageRootURL)
            .delete(id: entryId)
        Task { await load() }
    }

    /// 触发「从此创建」sheet
    func requestCreate(from entry: SnapshotEntry, workspace: WorkspaceModel) {
        selectedEntry = SelectedEntry(entry: entry, workspace: workspace)
    }

    /// 关闭「从此创建」sheet
    func dismissCreate() {
        selectedEntry = nil
    }
}
