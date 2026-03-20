// macos/Sources/Features/Tmux/TmuxTabMonitor.swift
import Foundation

/// 追踪已 attach tmux session 的 tab，定时轮询 window 列表更新 TmuxAttachState。
@MainActor
final class TmuxTabMonitor {

    private weak var tabBarViewModel: TabBarViewModel?
    private var timer: Timer?

    init(tabBarViewModel: TabBarViewModel) {
        self.tabBarViewModel = tabBarViewModel
    }

    /// 启动轮询（幂等，重复调用不会创建多个 timer）
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
        // 立即执行一次
        poll()
    }

    /// 停止轮询
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 检查是否还有需要监控的 tmux tab，无则自动停止
    func stopIfIdle() {
        guard let vm = tabBarViewModel else { stop(); return }
        if !vm.tabs.contains(where: { $0.tmuxState != nil }) {
            stop()
        }
    }

    private func poll() {
        guard let vm = tabBarViewModel else { return }
        let tmuxTabs = vm.tabs.filter { $0.tmuxState != nil }
        guard !tmuxTabs.isEmpty else { stop(); return }

        for tab in tmuxTabs {
            guard let state = tab.tmuxState else { continue }
            Task {
                await updateWindows(for: tab.id, sessionName: state.sessionName)
            }
        }
    }

    private func updateWindows(for tabId: UUID, sessionName: String) async {
        guard let vm = tabBarViewModel else { return }

        do {
            let output = try await TmuxCommandRunner.run(
                args: ["list-windows", "-t", sessionName, "-F",
                       "#{window_index}|#{window_name}|#{window_active}"]
            )
            let tmuxWindows = TmuxParser.parseWindows(output, sessionName: sessionName)
            let windowInfos = tmuxWindows.map { w in
                TmuxAttachState.WindowInfo(
                    index: w.windowIndex,
                    name: w.name,
                    active: w.active
                )
            }
            let activeWindow = tmuxWindows.first(where: { $0.active }) ?? tmuxWindows.first
            guard let idx = vm.tabs.firstIndex(where: { $0.id == tabId }) else { return }
            vm.tabs[idx].tmuxState = TmuxAttachState(
                sessionName: sessionName,
                activeWindowIndex: activeWindow?.windowIndex ?? 0,
                activeWindowName: activeWindow?.name ?? "",
                windows: windowInfos
            )
        } catch {
            // Session 不存在或 tmux server 停止 — 清除该 tab 的 tmuxState
            guard let idx = vm.tabs.firstIndex(where: { $0.id == tabId }) else { return }
            vm.tabs[idx].tmuxState = nil
            stopIfIdle()
        }
    }
}
