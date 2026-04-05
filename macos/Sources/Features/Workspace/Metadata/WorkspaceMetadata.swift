import Foundation

struct WorkspaceMetadata: Equatable {
    var listeningPorts: [Int] = []
    var prStatus: PRStatus? = nil
    var agentState: AgentState = .none
}

enum PRStatus: Equatable {
    case open(number: Int)
    case draft(number: Int)
    case merged(number: Int)

    var displayText: String {
        switch self {
        case .open(let n):   return "#\(n) Open"
        case .draft(let n):  return "#\(n) Draft"
        case .merged(let n): return "#\(n) Merged"
        }
    }
}

enum AgentState: Equatable {
    case none     // 无 session
    case idle     // session 存在但全部不再存活
    case working  // 至少一个 session isAlive
}
