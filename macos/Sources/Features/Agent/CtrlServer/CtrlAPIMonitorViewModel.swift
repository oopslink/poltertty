// macos/Sources/Features/Agent/CtrlServer/CtrlAPIMonitorViewModel.swift
import Foundation
import Combine

@MainActor
final class CtrlAPIMonitorViewModel: ObservableObject {
    @Published private(set) var records: [CtrlAPIRecord] = []
    @Published var selectedWorkspaceId: UUID? = nil
    @Published var selectedSurfaceId: UUID? = nil
    @Published var selectedRecord: CtrlAPIRecord? = nil

    private var cancellable: AnyCancellable?

    init() {
        cancellable = CtrlAPIStore.shared.$records
            .receive(on: RunLoop.main)
            .assign(to: \.records, on: self)
    }

    var filteredRecords: [CtrlAPIRecord] {
        records.filter { record in
            if let wsId = selectedWorkspaceId {
                // workspaceId 为 nil 的记录（/v1/mcp、/v1/health 等）始终通过
                if let recWs = record.workspaceId, recWs != wsId { return false }
            }
            if let sfId = selectedSurfaceId {
                if let recSf = record.surfaceId, recSf != sfId { return false }
            }
            return true
        }.reversed()
    }

    var availableWorkspaceIds: [UUID] {
        Array(Set(records.compactMap(\.workspaceId))).sorted { $0.uuidString < $1.uuidString }
    }

    var availableSurfaceIds: [UUID] {
        Array(Set(records.compactMap(\.surfaceId))).sorted { $0.uuidString < $1.uuidString }
    }

    func clearRecords() {
        CtrlAPIStore.shared.clear()
        selectedRecord = nil
    }
}
