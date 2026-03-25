// macos/Sources/Features/Agent/Dashboard/AgentDashboardViewModel.swift
import Foundation
import Combine

@MainActor
final class AgentDashboardViewModel: ObservableObject {
    enum ViewMode: String, CaseIterable {
        case table = "table"
        case cards = "cards"

        var icon: String {
            switch self {
            case .table: return "list.bullet.rectangle"
            case .cards: return "square.grid.2x2"
            }
        }
    }

    struct WorkspaceSessionGroup: Identifiable {
        let id: UUID           // workspaceId
        let name: String
        let colorHex: String?
        let sessions: [AgentSession]
    }

    @Published var showInactive: Bool = false {
        didSet { if showInactive { loadHistory() } }
    }
    @Published var viewMode: ViewMode = .table
    @Published private(set) var historicalSessions: [PersistedSession] = []

    private var cancellables = Set<AnyCancellable>()

    init() {
        AgentService.shared.sessionManager.$sessions
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Active Sessions

    var activeSessions: [AgentSession] {
        AgentService.shared.sessionManager.sessions.values
            .filter { $0.state.isActive }
            .sorted { $0.startedAt < $1.startedAt }
    }

    func groupedByWorkspace(_ sessions: [AgentSession]) -> [WorkspaceSessionGroup] {
        Dictionary(grouping: sessions) { $0.workspaceId }
            .map { (id, sessions) in
                let ws = WorkspaceManager.shared.workspace(for: id)
                return WorkspaceSessionGroup(
                    id: id,
                    name: ws?.name ?? "Unknown",
                    colorHex: ws?.colorHex,
                    sessions: sessions.sorted { $0.startedAt < $1.startedAt }
                )
            }
            .sorted { $0.name < $1.name }
    }

    // MARK: - History

    func loadHistory() {
        Task.detached(priority: .utility) { [weak self] in
            let sessions = SessionStore.shared.loadAll()
            await MainActor.run { self?.historicalSessions = sessions }
        }
    }

    // MARK: - Display Helpers

    /// 任务描述：最新活跃 subagent 的 name，或回退到状态描述
    func taskDescription(for session: AgentSession) -> String {
        if let latest = session.subagents.values
            .filter({ $0.state.isActive })
            .sorted(by: { $0.startedAt > $1.startedAt })
            .first {
            return latest.name
        }
        switch session.state {
        case .working: return "Working..."
        case .idle: return "Idle"
        case .launching: return "Launching..."
        case .done: return "Done"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    /// 运行时长格式化（支持 TimelineView 传入 tick 精确刷新）
    func durationString(for session: AgentSession, tick: Date = Date()) -> String {
        let elapsed = tick.timeIntervalSince(session.startedAt)
        if elapsed < 60 { return "\(Int(elapsed))s" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m\(Int(elapsed) % 60)s" }
        return "\(Int(elapsed / 3600))h\(Int((elapsed.truncatingRemainder(dividingBy: 3600)) / 60))m"
    }

    /// Token 数量格式化
    func tokenString(for usage: TokenUsage) -> String {
        let total = usage.totalTokens
        if total < 1000 { return "\(total)" }
        return String(format: "%.1fk", Double(total) / 1000.0)
    }

    /// 费用格式化
    func costString(for usage: TokenUsage) -> String {
        let cost = NSDecimalNumber(decimal: usage.cost).doubleValue
        return String(format: "$%.2f", cost)
    }

    /// Pane 位置描述
    func paneLocationString(for session: AgentSession) -> String {
        let short = session.surfaceId.uuidString.prefix(4)
        return "Pane \(short)"
    }
}
