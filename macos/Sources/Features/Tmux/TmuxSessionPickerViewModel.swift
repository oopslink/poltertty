// macos/Sources/Features/Tmux/TmuxSessionPickerViewModel.swift
import Foundation

@MainActor
final class TmuxSessionPickerViewModel: ObservableObject {
    enum Mode {
        case attachExisting
        case createNew
    }

    @Published var mode: Mode = .attachExisting
    @Published var sessions: [TmuxSession] = []
    @Published var selectedSessionName: String? = nil
    @Published var newSessionName: String = ""
    @Published var isLoading: Bool = true
    @Published var errorMessage: String? = nil

    /// 加载现有 tmux sessions（复用 TmuxCommandRunner + TmuxParser）
    func loadSessions() async {
        isLoading = true
        errorMessage = nil
        do {
            let output = try await TmuxCommandRunner.run(
                args: ["list-sessions", "-F", "#{session_name}|#{session_attached}"]
            )
            sessions = TmuxParser.parseSessions(output)
            if selectedSessionName == nil, let first = sessions.first {
                selectedSessionName = first.id
            }
        } catch let error as TmuxError {
            switch error {
            case .notInstalled:
                errorMessage = "tmux 未安装"
            case .serverNotRunning:
                sessions = []
            case .timeout:
                errorMessage = "tmux 响应超时"
            }
        } catch {
            errorMessage = "未知错误"
        }
        if sessions.isEmpty && errorMessage == nil {
            mode = .createNew
        }
        isLoading = false
    }

    var canOpen: Bool {
        switch mode {
        case .attachExisting:
            return selectedSessionName != nil
        case .createNew:
            return true
        }
    }

    func resolveSessionName() async -> String? {
        switch mode {
        case .attachExisting:
            return selectedSessionName
        case .createNew:
            let name = newSessionName.trimmingCharacters(in: .whitespaces)
            if name.isEmpty {
                do {
                    let output = try await TmuxCommandRunner.run(
                        args: ["new-session", "-d", "-P", "-F", "#{session_name}"]
                    )
                    return output.trimmingCharacters(in: .whitespacesAndNewlines)
                } catch {
                    errorMessage = "创建 session 失败"
                    return nil
                }
            } else {
                do {
                    try await TmuxCommandRunner.runSilent(
                        args: ["new-session", "-d", "-s", name]
                    )
                    return name
                } catch {
                    errorMessage = "创建 session \"\(name)\" 失败（可能已存在）"
                    return nil
                }
            }
        }
    }
}
