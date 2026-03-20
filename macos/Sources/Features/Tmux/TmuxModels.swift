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
    var panes: [TmuxPane]
    var active: Bool
}

struct TmuxPane: Identifiable, Equatable {
    let id: Int             // pane_id 数字部分（tmux 原始格式 "%N"，去掉 % 前缀）
    var title: String
    var active: Bool
    var width: Int
    var height: Int
}

enum TmuxError: Equatable {
    case notInstalled
    case serverNotRunning(stderr: String)
    case timeout
}

enum TmuxPanelState: Equatable {
    case loading
    case empty
    case loaded([TmuxSession])
    case error(TmuxError)
}
