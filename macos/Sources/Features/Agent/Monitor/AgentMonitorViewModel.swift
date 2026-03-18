// macos/Sources/Features/Agent/Monitor/AgentMonitorViewModel.swift
import Foundation
import Combine

@MainActor
final class AgentMonitorViewModel: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var width: CGFloat = 280
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
            .sink { [weak self] _ in self?.objectWillChange.send() }
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
