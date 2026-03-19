// macos/Sources/Features/Agent/Monitor/DrawerItem.swift
import Foundation

enum DrawerItem: Identifiable, Equatable {
    case sessionOverview(AgentSession)
    case subagentDetail(AgentSession, SubagentInfo)

    var id: String {
        switch self {
        case .sessionOverview(let s):      return "session-\(s.id)"
        case .subagentDetail(_, let sub):  return "sub-\(sub.id)"
        }
    }

    static func == (lhs: DrawerItem, rhs: DrawerItem) -> Bool { lhs.id == rhs.id }
}
