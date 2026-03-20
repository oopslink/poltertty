// macos/Sources/Features/Tmux/TmuxPanelViewModel.swift
import Foundation
import SwiftUI

@MainActor
final class TmuxPanelViewModel: ObservableObject {

    // MARK: - Published State

    @Published var state: TmuxPanelState = .loading
    @Published var isVisible: Bool = false
    @Published var panelWidth: CGFloat = 240
    @Published var bannerMessage: String? = nil  // 操作失败时短暂显示

    // MARK: - Private

    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?

    // MARK: - Lifecycle

    init() {}

    deinit {
        timer?.invalidate()
        refreshTask?.cancel()
    }

    func resume() {
        scheduleTimer()
        refresh()
    }

    func pause() {
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    func stop() {
        pause()
    }

    // MARK: - Refresh

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            await loadSessions()
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.refresh()
            }
        }
    }

    private func loadSessions() async {
        do {
            let sessionsOutput = try await TmuxCommandRunner.run(
                args: ["list-sessions", "-F", "#{session_name}|#{session_attached}"]
            )
            var sessions = TmuxParser.parseSessions(sessionsOutput)

            if sessions.isEmpty {
                state = .empty
                return
            }

            // 并发加载每个 session 的 windows + panes
            sessions = await withTaskGroup(of: TmuxSession.self) { group in
                for session in sessions {
                    group.addTask {
                        await self.loadWindowsAndPanes(for: session)
                    }
                }
                var result: [TmuxSession] = []
                for await s in group { result.append(s) }
                // 保持 sessions 原始顺序
                return sessions.map { s in result.first { $0.id == s.id } ?? s }
            }

            state = .loaded(sessions)
        } catch is CancellationError {
            // Task was cancelled, don't update UI state
        } catch let error as TmuxError {
            state = .error(error)
        } catch {
            state = .error(.notInstalled)
        }
    }

    private func loadWindowsAndPanes(for session: TmuxSession) async -> TmuxSession {
        var s = session
        guard let windowsOutput = try? await TmuxCommandRunner.run(
            args: ["list-windows", "-t", session.id, "-F",
                   "#{window_index}|#{window_name}|#{window_active}"]
        ) else { return s }

        var windows = TmuxParser.parseWindows(windowsOutput, sessionName: session.id)

        windows = await withTaskGroup(of: TmuxWindow.self) { group in
            for window in windows {
                group.addTask {
                    await self.loadPanes(for: window, sessionName: session.id)
                }
            }
            var result: [TmuxWindow] = []
            for await w in group { result.append(w) }
            return windows.map { w in result.first { $0.id == w.id } ?? w }
        }

        s.windows = windows
        return s
    }

    private func loadPanes(for window: TmuxWindow, sessionName: String) async -> TmuxWindow {
        var w = window
        guard let panesOutput = try? await TmuxCommandRunner.run(
            args: ["list-panes", "-t", "\(sessionName):\(window.windowIndex)", "-F",
                   "#{pane_id}|#{pane_title}|#{pane_active}|#{pane_width}|#{pane_height}"]
        ) else { return w }
        w.panes = TmuxParser.parsePanes(panesOutput)
        return w
    }

    // MARK: - Banner

    func showBanner(_ message: String) {
        bannerMessage = message
        bannerTask?.cancel()
        bannerTask = Task {
            do {
                try await Task.sleep(nanoseconds: 4_000_000_000)
                bannerMessage = nil
            } catch {
                // Task was cancelled, do nothing
            }
        }
    }

    // MARK: - Commands

    func newSession(name: String) async {
        try? await TmuxCommandRunner.runSilent(
            args: ["new-session", "-d", "-s", name]
        )
        refresh()
    }

    func attachSession(_ sessionName: String) async {
        do {
            try await TmuxCommandRunner.runSilent(
                args: ["switch-client", "-t", sessionName]
            )
        } catch {
            showBanner("无 tmux client，请在终端运行 `tmux attach-session -t \(sessionName)`")
        }
        refresh()
    }

    func renameSession(old: String, new: String) async {
        try? await TmuxCommandRunner.runSilent(
            args: ["rename-session", "-t", old, new]
        )
        refresh()
    }

    func killSession(_ name: String) async {
        try? await TmuxCommandRunner.runSilent(
            args: ["kill-session", "-t", name]
        )
        refresh()
    }

    func switchToWindow(sessionName: String, windowIndex: Int) async {
        do {
            try await TmuxCommandRunner.runSilent(
                args: ["switch-client", "-t", "\(sessionName):\(windowIndex)"]
            )
        } catch {
            showBanner("无 tmux client，请在终端运行 `tmux attach-session -t \(sessionName)`")
        }
        refresh()
    }

    func newWindow(sessionName: String) async {
        try? await TmuxCommandRunner.runSilent(
            args: ["new-window", "-t", sessionName]
        )
        refresh()
    }

    func renameWindow(sessionName: String, windowIndex: Int, newName: String) async {
        try? await TmuxCommandRunner.runSilent(
            args: ["rename-window", "-t", "\(sessionName):\(windowIndex)", newName]
        )
        refresh()
    }

    func killWindow(sessionName: String, windowIndex: Int) async {
        try? await TmuxCommandRunner.runSilent(
            args: ["kill-window", "-t", "\(sessionName):\(windowIndex)"]
        )
        refresh()
    }

    func selectPane(paneId: Int) async {
        try? await TmuxCommandRunner.runSilent(
            args: ["select-pane", "-t", "%\(paneId)"]
        )
        refresh()
    }

    func splitPane(paneId: Int, horizontal: Bool) async {
        let flag = horizontal ? "-h" : "-v"
        try? await TmuxCommandRunner.runSilent(
            args: ["split-window", flag, "-t", "%\(paneId)"]
        )
        refresh()
    }

    func killPane(paneId: Int) async {
        try? await TmuxCommandRunner.runSilent(
            args: ["kill-pane", "-t", "%\(paneId)"]
        )
        refresh()
    }
}
