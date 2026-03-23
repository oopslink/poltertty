// macos/Sources/Features/Agent/Dashboard/OptionDoubleTapDetector.swift
import AppKit
import Carbon
import OSLog

/// 检测双击 Option 键（间隔 ≤ 350ms），触发时发送 toggleAgentDashboard 通知。
/// 监听 .flagsChanged 事件（Option 产生此事件，不产生 keyDown）。
/// 两次 Option 之间有任何其他键按下或修饰符变化则重置计时器。
final class OptionDoubleTapDetector {
    static let shared = OptionDoubleTapDetector()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "OptionDoubleTapDetector"
    )

    private let threshold: TimeInterval = 0.35
    /// 触发后的冷却期，防止极快速的第三次按键再次触发
    private let cooldown: TimeInterval = 0.5
    private var lastOptionTime: Date?
    private var lastFiredTime: Date = .distantPast
    private var flagsMonitor: Any?
    private var keyDownMonitor: Any?

    private init() {}

    deinit { stop() }

    func start() {
        guard flagsMonitor == nil else { return }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.lastOptionTime = nil
            return event
        }

        Self.logger.info("OptionDoubleTapDetector started")
    }

    func stop() {
        if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
        if let m = keyDownMonitor { NSEvent.removeMonitor(m); keyDownMonitor = nil }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let isOption = event.keyCode == UInt16(kVK_Option) || event.keyCode == UInt16(kVK_RightOption)

        guard isOption else {
            // 非 Option 修饰符变化 → 重置
            lastOptionTime = nil
            return
        }

        // 只处理按下瞬间（.option 存在），忽略松开
        guard event.modifierFlags.contains(.option) else { return }

        let now = Date()
        if let last = lastOptionTime, now.timeIntervalSince(last) <= threshold {
            lastOptionTime = nil
            // 冷却期内忽略，防止三连击等场景触发两次 toggle
            guard now.timeIntervalSince(lastFiredTime) > cooldown else { return }
            lastFiredTime = now
            Self.logger.debug("double-option detected, posting toggleAgentDashboard")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .toggleAgentDashboard, object: NSApp.keyWindow)
            }
        } else {
            lastOptionTime = now
        }
    }
}
