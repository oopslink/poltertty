// macos/Sources/Features/Agent/Monitor/AgentMonitorViewModel.swift
import Foundation
import Combine

@MainActor
final class AgentMonitorViewModel: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var selectedItems: [DrawerItem] = []
    @Published private(set) var historicalSessions: [PersistedSession] = []
    @Published var historyExpanded: Bool = false
    /// 统一视图中当前选中的 subagent ID（右列显示哪个 subagent）
    @Published var selectedSubagentId: String? = nil

    // MARK: - External Sessions
    @Published private(set) var externalSessions: [ExternalSessionRecord] = []
    private var externalDiscovery: ExternalSessionDiscovery?

    /// drawer 宽度：统一视图按 subagent 数量动态调整，对比模式按面板数
    var drawerWidth: CGFloat {
        if let session = unifiedSession {
            // 没有 subagent 时只需展示 overview，400pt 足够；有 subagent 才用双列 800pt
            return session.subagents.isEmpty ? 400 : 800
        }
        switch selectedItems.count {
        case 0:  return 0
        case 1:  return 400
        case 2:  return 800
        default: return 1200
        }
    }

    /// 当 selectedItems 只有一个 sessionOverview 时，使用统一两列视图
    var unifiedSession: AgentSession? {
        guard viewModel_selectedItemsIsUnified else { return nil }
        if case .sessionOverview(let session) = selectedItems.first { return session }
        return nil
    }

    private var viewModel_selectedItemsIsUnified: Bool {
        guard selectedItems.count == 1, let first = selectedItems.first else { return false }
        if case .sessionOverview = first { return true }
        return false
    }

    let workspaceId: UUID
    private var cancellables = Set<AnyCancellable>()

    init(workspaceId: UUID) {
        self.workspaceId = workspaceId
        AgentService.shared.sessionManager.$sessions
            .receive(on: RunLoop.main)
            .sink { [weak self] updatedSessions in
                guard let self else { return }
                // 用最新 session 数据刷新 selectedItems 快照，保证 state/output 实时更新
                self.selectedItems = self.selectedItems.compactMap { item in
                    switch item {
                    case .sessionOverview(let old):
                        // 历史 session 的 surfaceId 不在 updatedSessions 中，直接保留
                        if let fresh = updatedSessions.values.first(where: { $0.surfaceId == old.surfaceId }) {
                            return .sessionOverview(fresh)
                        }
                        return item
                    case .subagentDetail(let oldSession, let oldSub):
                        guard let freshSession = updatedSessions.values
                                .first(where: { $0.surfaceId == oldSession.surfaceId }),
                              let freshSub = freshSession.subagents[oldSub.id]
                        else { return item }  // 历史 session 保留原样
                        return .subagentDetail(freshSession, freshSub)
                    }
                }
            }
            .store(in: &cancellables)

        // 获取 workspace rootDir 并启动外部 session 监控
        if let rootDir = WorkspaceManager.shared.workspace(for: workspaceId)?.rootDirExpanded,
           !rootDir.isEmpty {
            let discovery = ExternalSessionDiscovery(workspaceRootDir: rootDir)
            externalDiscovery = discovery
            discovery.$sessions
                .receive(on: RunLoop.main)
                .assign(to: &$externalSessions)
            discovery.start()
        }
    }

    // deinit：捕获 discovery 引用并派发到主线程；不直接调用 @MainActor 方法
    deinit {
        if let discovery = externalDiscovery {
            Task { @MainActor in discovery.stop() }
        }
    }

    var hasExternalSessions: Bool { !externalSessions.isEmpty }

    var sessions: [AgentSession] {
        AgentService.shared.sessionManager.sessions.values
            .filter { $0.workspaceId == workspaceId }
            .sorted { $0.startedAt < $1.startedAt }
    }

    func toggle() { isVisible.toggle() }

    /// 单击：替换整个 selectedItems
    func select(_ item: DrawerItem) {
        selectedItems = [item]
    }

    /// Cmd+Click：追加（已存在则移除），最多 3 个
    func cmdClick(_ item: DrawerItem) {
        if let idx = selectedItems.firstIndex(of: item) {
            selectedItems.remove(at: idx)
        } else if selectedItems.count < 3 {
            selectedItems.append(item)
        }
    }

    func closePanel(_ item: DrawerItem) {
        selectedItems.removeAll { $0 == item }
    }

    func closeDrawer() {
        selectedItems = []
    }

    /// 侧边栏点击 subagent：打开统一视图并预选该 subagent
    func selectSubagentInSidebar(_ sub: SubagentInfo, in session: AgentSession) {
        selectedSubagentId = sub.id
        selectedItems = [.sessionOverview(session)]
    }

    func loadHistory() {
        let wid = workspaceId
        Task.detached(priority: .utility) { [weak self] in
            let sessions = SessionStore.shared.load(for: wid)
            await MainActor.run { self?.historicalSessions = sessions }
        }
    }

    func toggleHistory() {
        historyExpanded.toggle()
        if historyExpanded { loadHistory() }
    }

    /// 点击历史 session → 在 Drawer 中显示只读 Overview
    func selectHistory(_ ps: PersistedSession) {
        let session = ps.toAgentSession()
        selectedItems = [.sessionOverview(session)]
    }
}
