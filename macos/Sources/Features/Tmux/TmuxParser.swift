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
                // 用 firstIndex/lastIndex 分割，window name 可能含 "|"
                guard let firstSep = line.firstIndex(of: "|"),
                      let lastSep = line.lastIndex(of: "|"),
                      firstSep != lastSep else { return nil }
                let indexStr = String(line[line.startIndex..<firstSep])
                let name = String(line[line.index(after: firstSep)..<lastSep])
                let activeStr = String(line[line.index(after: lastSep)...])
                guard let index = Int(indexStr) else { return nil }
                return TmuxWindow(
                    id: "\(sessionName):\(index)",
                    sessionName: sessionName,
                    windowIndex: index,
                    name: name,
                    active: activeStr == "1"
                )
            }
    }
}
