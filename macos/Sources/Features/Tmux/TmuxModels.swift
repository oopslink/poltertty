// macos/Sources/Features/Tmux/TmuxModels.swift
import Foundation

struct TmuxSession: Identifiable, Equatable {
    let id: String          // session name
    var windows: [TmuxWindow]
    var attached: Bool
}

struct TmuxWindow: Identifiable, Equatable {
    let id: String          // 复合 ID："\(sessionName):\(windowIndex)"
    let sessionName: String
    let windowIndex: Int
    var name: String
    var active: Bool
}

enum TmuxError: Error, Equatable {
    case notInstalled
    case serverNotRunning(stderr: String)
    case timeout
}

struct TmuxAttachState: Equatable {
    let sessionName: String
    var activeWindowIndex: Int
    var activeWindowName: String
    var windows: [WindowInfo]

    struct WindowInfo: Equatable, Identifiable {
        let index: Int
        let name: String
        let active: Bool
        var id: Int { index }
    }
}
