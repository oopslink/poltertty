// macos/Sources/Features/Agent/Monitor/AgentMonitorViewModel.swift
import Foundation
import Combine

@MainActor
final class AgentMonitorViewModel: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var selectedItems: [DrawerItem] = []

    var drawerWidth: CGFloat {
        switch selectedItems.count {
        case 0:  return 0
        case 1:  return 400
        case 2:  return 800
        default: return 1200
        }
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
                        return updatedSessions.values
                            .first(where: { $0.surfaceId == old.surfaceId })
                            .map { .sessionOverview($0) }
                    case .subagentDetail(let oldSession, let oldSub):
                        guard let freshSession = updatedSessions.values
                                .first(where: { $0.surfaceId == oldSession.surfaceId }),
                              let freshSub = freshSession.subagents[oldSub.id]
                        else { return nil }
                        return .subagentDetail(freshSession, freshSub)
                    }
                }
            }
            .store(in: &cancellables)
    }

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
}
