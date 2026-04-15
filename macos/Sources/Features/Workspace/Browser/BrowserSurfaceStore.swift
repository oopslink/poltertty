// macos/Sources/Features/Workspace/Browser/BrowserSurfaceStore.swift
import Foundation
import WebKit

/// 管理每个 Workspace 对应的 BrowserTabManager。
/// BrowserTabManager 懒惰创建（首次打开 Browser Panel 时），Workspace 删除时销毁。
@MainActor
class BrowserSurfaceStore: ObservableObject {
    @Published private(set) var managers: [UUID: BrowserTabManager] = [:]

    /// 获取或创建指定 Workspace 的 BrowserTabManager。
    /// 若 WorkspaceModel 有快照且尚未加载，设置 showRestorePrompt。
    func manager(for workspaceId: UUID, snapshots: [BrowserTabSnapshot]? = nil) -> BrowserTabManager {
        if let existing = managers[workspaceId] {
            return existing
        }
        let mgr = BrowserTabManager()
        // 若有持久化快照，提示用户恢复（不自动创建 tab）
        if let snaps = snapshots, !snaps.isEmpty {
            mgr.prepareRestore(snapshots: snaps)
        }
        // 没有快照时创建一个初始空白 tab
        if mgr.tabs.isEmpty && !mgr.showRestorePrompt {
            mgr.newTab()
        }
        managers[workspaceId] = mgr
        return mgr
    }

    /// Workspace 删除时调用，释放所有 WKWebView。
    func removeManager(for workspaceId: UUID) {
        if let mgr = managers[workspaceId] {
            for tab in mgr.tabs {
                tab.webView.navigationDelegate = nil
            }
        }
        managers.removeValue(forKey: workspaceId)
    }

    /// 非创建式查询：只返回已存在的 manager，不触发懒创建。
    /// Ctrl API 查询路径使用此方法，避免用未知 wsId 污染 store。
    func existingManager(for workspaceId: UUID) -> BrowserTabManager? {
        managers[workspaceId]
    }

    /// 跨 workspace 按 tabId 反查 tab 归属。
    /// 用于 Ctrl API 在调用方未指定 workspaceId 时定位 tab。
    func findTab(id tabId: UUID) -> (workspaceId: UUID, manager: BrowserTabManager)? {
        for (wsId, mgr) in managers {
            if mgr.tabs.contains(where: { $0.id == tabId }) {
                return (wsId, mgr)
            }
        }
        return nil
    }
}
