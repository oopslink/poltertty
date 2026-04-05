// macos/Sources/Features/Workspace/Metadata/WorkspaceMetadataStore.swift
import Foundation
import Combine

@MainActor
final class WorkspaceMetadataStore: ObservableObject {
    static let shared = WorkspaceMetadataStore()

    @Published private(set) var metadata: [UUID: WorkspaceMetadata] = [:]

    private var portScanTask: Task<Void, Never>?
    private var prTasks: [UUID: Task<Void, Never>] = [:]
    private var discoveries: [UUID: ExternalSessionDiscovery] = [:]
    private var discoveryCancellables: [UUID: AnyCancellable] = [:]
    private var workspacesCancellable: AnyCancellable?

    private init() {}

    // MARK: - 启动

    func start() {
        // 订阅 WorkspaceManager 的 workspaces 变化
        workspacesCancellable = WorkspaceManager.shared.$workspaces
            .receive(on: RunLoop.main)
            .sink { [weak self] workspaces in
                self?.syncWorkspaces(workspaces)
            }
        startPortScanLoop()
    }

    // MARK: - 端口扫描（5s 轮询）

    private func startPortScanLoop() {
        portScanTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let workspaces = WorkspaceManager.shared.workspaces.map { (id: $0.id, rootDir: $0.rootDir) }
                let portMap = await PortScanner.scan(workspaces: workspaces)
                guard !Task.isCancelled else { return }
                for (id, ports) in portMap {
                    let sorted = Array(Set(ports)).sorted()
                    self.metadata[id, default: WorkspaceMetadata()].listeningPorts = sorted
                }
                // 清空无端口的 workspace
                for id in self.metadata.keys where portMap[id] == nil {
                    self.metadata[id]?.listeningPorts = []
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    // MARK: - PR 状态（60s TTL，workspace 粒度）

    private func startPRRefresh(for workspace: WorkspaceModel) {
        let id = workspace.id
        let rootDir = workspace.rootDir
        prTasks[id] = Task { [weak self] in
            while !Task.isCancelled {
                let status = await PRStatusFetcher.fetch(rootDir: rootDir)
                guard let self, !Task.isCancelled else { return }
                self.metadata[id, default: WorkspaceMetadata()].prStatus = status
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    // MARK: - Agent 状态（订阅 ExternalSessionDiscovery）

    private func startAgentTracking(for workspace: WorkspaceModel) {
        let id = workspace.id
        let rootDir = workspace.rootDirExpanded
        guard !rootDir.isEmpty else { return }
        let discovery = ExternalSessionDiscovery(workspaceRootDir: rootDir)
        discoveries[id] = discovery
        discoveryCancellables[id] = discovery.$sessions
            .receive(on: RunLoop.main)
            .sink { [weak self] sessions in
                guard let self else { return }
                let state: WorkspaceAgentState
                if sessions.isEmpty {
                    state = .none
                } else if sessions.contains(where: { $0.isAlive }) {
                    state = .working
                } else {
                    state = .idle
                }
                self.metadata[id, default: WorkspaceMetadata()].agentState = state
            }
        discovery.start()
    }

    // MARK: - 生命周期同步

    private func syncWorkspaces(_ workspaces: [WorkspaceModel]) {
        let currentIds = Set(workspaces.map { $0.id })
        let trackedIds = Set(prTasks.keys)

        // 新增 workspace → 开始追踪
        for ws in workspaces where !trackedIds.contains(ws.id) {
            startPRRefresh(for: ws)
            startAgentTracking(for: ws)
        }

        // 移除的 workspace → 停止追踪 + 清空数据
        for id in trackedIds where !currentIds.contains(id) {
            prTasks[id]?.cancel()
            prTasks.removeValue(forKey: id)
            discoveries[id]?.stop()
            discoveries.removeValue(forKey: id)
            discoveryCancellables.removeValue(forKey: id)
            metadata.removeValue(forKey: id)
        }
    }
}
