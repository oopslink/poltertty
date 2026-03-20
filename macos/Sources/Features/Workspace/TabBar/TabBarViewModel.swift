import SwiftUI
import GhosttyKit

/// 代表单个 terminal tab 的数据
struct TabItem: Identifiable {
    let id: UUID
    var title: String
    var titleLocked: Bool   // true = 用户手动设置，忽略 PTY 变化
    var isActive: Bool
    let surfaceId: UUID     // 对应 surfaces 字典的 key（非强引用）
    var tmuxState: TmuxAttachState?  // nil = 普通 tab，非 nil = 已 attach tmux session

    init(title: String, surfaceId: UUID) {
        self.id = UUID()
        self.title = title
        self.titleLocked = false
        self.isActive = false
        self.surfaceId = surfaceId
    }
}

/// 管理所有 tab 状态，作为 SurfaceView 实例的唯一所有者
@MainActor
final class TabBarViewModel: ObservableObject {
    @Published var tabs: [TabItem] = []
    @Published var activeTabId: UUID?
    // @Published 确保 surfaces 变化触发 UI 更新（activeSurface 是计算属性）
    @Published private(set) var surfaces: [UUID: Ghostty.SurfaceView] = [:]

    /// 当前活跃的 SurfaceView
    var activeSurface: Ghostty.SurfaceView? {
        guard let activeTabId,
              let tab = tabs.first(where: { $0.id == activeTabId })
        else { return nil }
        return surfaces[tab.surfaceId]
    }

    // MARK: - Tab 操作

    /// 添加一个新 tab，传入已创建好的 SurfaceView
    func addTab(surface: Ghostty.SurfaceView, title: String = "Terminal") {
        let surfaceId = UUID()
        surfaces[surfaceId] = surface
        var item = TabItem(title: title, surfaceId: surfaceId)
        item.isActive = true
        for i in tabs.indices { tabs[i].isActive = false }
        tabs.append(item)
        activeTabId = item.id
    }

    /// 切换到指定 tab
    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        for i in tabs.indices {
            tabs[i].isActive = (tabs[i].id == id)
        }
        activeTabId = id
    }

    /// 关闭指定 tab，返回需要清理的 surfaceId
    @discardableResult
    func closeTab(_ id: UUID) -> UUID? {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return nil }
        let surfaceId = tabs[idx].surfaceId
        tabs.remove(at: idx)
        surfaces.removeValue(forKey: surfaceId)
        if !tabs.isEmpty {
            let newIdx = min(idx, tabs.count - 1)
            selectTab(tabs[newIdx].id)
        } else {
            activeTabId = nil
        }
        return surfaceId
    }

    /// 移动 tab（拖拽重排）
    func moveTab(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
    }

    /// 更新 PTY 标题（仅当 titleLocked == false 时生效）
    func updateTitle(forSurfaceId surfaceId: UUID, title: String) {
        guard let idx = tabs.firstIndex(where: { $0.surfaceId == surfaceId }),
              !tabs[idx].titleLocked
        else { return }
        tabs[idx].title = title
    }

    /// 手动重命名（空字符串 = 解锁，恢复 PTY 标题）
    func renameTab(_ id: UUID, title: String) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        if title.isEmpty {
            tabs[idx].titleLocked = false
        } else {
            tabs[idx].title = title
            tabs[idx].titleLocked = true
        }
    }

    // MARK: - 持久化支持

    struct PersistedTab: Codable {
        let title: String
        let titleLocked: Bool
    }

    var persistedTabs: [PersistedTab] {
        tabs.map { PersistedTab(title: $0.title, titleLocked: $0.titleLocked) }
    }

    var activeTabIndex: Int? {
        guard let activeTabId else { return nil }
        return tabs.firstIndex(where: { $0.id == activeTabId })
    }

    // MARK: - Agent 状态查询

    func agentState(for surfaceId: UUID) -> AgentState? {
        AgentService.shared.sessionManager.session(for: surfaceId)?.state
    }

    func agentCostDisplay(for surfaceId: UUID) -> String? {
        guard let cost = AgentService.shared.sessionManager.session(for: surfaceId)?.tokenUsage.cost,
              cost > 0 else { return nil }
        return String(format: "$%.2f", NSDecimalNumber(decimal: cost).doubleValue)
    }
}
