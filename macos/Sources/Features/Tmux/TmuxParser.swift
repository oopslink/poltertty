// macos/Sources/Features/Tmux/TmuxParser.swift
import Foundation

enum TmuxParser {

    /// 解析 `tmux list-sessions -F "#{session_name}|#{session_attached}"` 输出
    static func parseSessions(_ output: String) -> [TmuxSession] {
        output.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { line -> TmuxSession? in
                // 用 lastIndex(of:) 从末尾分割，session name 可能含 "|"
                guard let sep = line.lastIndex(of: "|") else { return nil }
                let name = String(line[line.startIndex..<sep])
                let attachedStr = String(line[line.index(after: sep)...])
                guard !name.isEmpty else { return nil }
                return TmuxSession(id: name, windows: [], attached: attachedStr == "1")
            }
    }

    /// 解析 `tmux list-windows -t <s> -F "#{window_index}|#{window_name}|#{window_active}"` 输出
    static func parseWindows(_ output: String, sessionName: String) -> [TmuxWindow] {
        output.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { line -> TmuxWindow? in
                let parts = line.components(separatedBy: "|")
                guard parts.count >= 3,
                      let index = Int(parts[0]) else { return nil }
                let name = parts[1]
                let active = parts[2] == "1"
                return TmuxWindow(
                    id: "\(sessionName):\(index)",
                    sessionName: sessionName,
                    windowIndex: index,
                    name: name,
                    panes: [],
                    active: active
                )
            }
    }

    /// 解析 `tmux list-panes -t <s> -F "#{pane_id}|#{pane_title}|#{pane_active}|#{pane_width}|#{pane_height}"` 输出
    static func parsePanes(_ output: String) -> [TmuxPane] {
        output.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { line -> TmuxPane? in
                let parts = line.components(separatedBy: "|")
                guard parts.count >= 5 else { return nil }
                // pane_id 格式是 "%N"，去掉 % 前缀
                let rawId = parts[0].hasPrefix("%") ? String(parts[0].dropFirst()) : parts[0]
                guard let paneId = Int(rawId),
                      let width = Int(parts[3]),
                      let height = Int(parts[4]) else { return nil }
                return TmuxPane(
                    id: paneId,
                    title: parts[1],
                    active: parts[2] == "1",
                    width: width,
                    height: height
                )
            }
    }
}
