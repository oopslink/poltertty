// macos/Sources/Features/Splits/CmdDoubleTapDetector.swift
import AppKit
import Carbon
import OSLog

/// 检测双击 Cmd 键（间隔 ≤ 350ms），触发时发送 togglePaneSelector 通知。
/// 监听 .flagsChanged 事件（Cmd 产生此事件，不产生 keyDown）。
/// 两次 Cmd 之间有任何其他键按下或修饰符变化则重置计时器。
final class CmdDoubleTapDetector {
    static let shared = CmdDoubleTapDetector()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "CmdDoubleTapDetector"
    )

    private let threshold: TimeInterval = 0.35
    private var lastCmdTime: Date?
    private var flagsMonitor: Any?
    private var keyDownMonitor: Any?

    private init() {}

    /// 注：单例的 deinit 在正常 App 生命周期中不会被调用。
    /// 如需显式释放（如测试场景），请直接调用 stop()。
    deinit { stop() }

    func start() {
        guard flagsMonitor == nil else { return }

        // 监听修饰键变化（Cmd 按下/松开）
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        // 监听普通键按下，用于重置计时器
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.lastCmdTime = nil
            return event
        }

        Self.logger.info("CmdDoubleTapDetector started")
    }

    func stop() {
        if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
        if let m = keyDownMonitor { NSEvent.removeMonitor(m); keyDownMonitor = nil }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let isCmd = event.keyCode == UInt16(kVK_Command) || event.keyCode == UInt16(kVK_RightCommand)

        guard isCmd else {
            // 非 Cmd 修饰符变化（Shift/Option/Ctrl 等）→ 重置
            lastCmdTime = nil
            return
        }

        // 只处理按下瞬间（.command 存在），忽略松开（.command 不存在）
        guard event.modifierFlags.contains(.command) else { return }

        let now = Date()
        if let last = lastCmdTime, now.timeIntervalSince(last) <= threshold {
            lastCmdTime = nil
            Self.logger.debug("double-cmd detected, posting togglePaneSelector")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .togglePaneSelector, object: NSApp.keyWindow)
            }
        } else {
            lastCmdTime = now
        }
    }
}
