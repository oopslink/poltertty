// macos/Sources/Features/Agent/Monitor/AgentMonitorViewModel.swift
import Foundation
import Combine

@MainActor
final class AgentMonitorViewModel: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var width: CGFloat = 280

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
}
