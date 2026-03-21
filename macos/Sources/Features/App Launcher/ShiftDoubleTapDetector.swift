// macos/Sources/Features/App Launcher/ShiftDoubleTapDetector.swift
import AppKit
import Carbon
import OSLog

/// 检测双击 Shift 键（间隔 ≤ 350ms），触发时发送 toggleAppLauncher 通知。
/// 监听 .flagsChanged 事件（Shift 产生此事件，不产生 keyDown）。
/// 两次 Shift 之间有任何其他键按下或修饰符变化则重置计时器。
final class ShiftDoubleTapDetector {
    static let shared = ShiftDoubleTapDetector()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "ShiftDoubleTapDetector"
    )

    private let threshold: TimeInterval = 0.35
    private var lastShiftTime: Date?
    private var flagsMonitor: Any?
    private var keyDownMonitor: Any?

    private init() {}

    deinit { stop() }

    func start() {
        guard flagsMonitor == nil else { return }

        // 监听修饰键变化（Shift 按下/松开）
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        // 监听普通键按下，用于重置计时器
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.lastShiftTime = nil
            return event
        }

        Self.logger.info("ShiftDoubleTapDetector started")
    }

    func stop() {
        if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
        if let m = keyDownMonitor { NSEvent.removeMonitor(m); keyDownMonitor = nil }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let isShift = event.keyCode == UInt16(kVK_Shift) || event.keyCode == UInt16(kVK_RightShift)

        guard isShift else {
            // 非 Shift 修饰符变化（Cmd/Option/Ctrl 等）→ 重置
            lastShiftTime = nil
            return
        }

        // 只处理按下瞬间（.shift 存在），忽略松开（.shift 不存在）
        guard event.modifierFlags.contains(.shift) else { return }

        let now = Date()
        if let last = lastShiftTime, now.timeIntervalSince(last) <= threshold {
            // 双击成立
            lastShiftTime = nil
            Self.logger.debug("double-shift detected, posting toggleAppLauncher")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .toggleAppLauncher, object: nil)
            }
        } else {
            lastShiftTime = now
        }
    }
}

// Temporary — will be moved to PolterttyRootView.swift in Task 6
extension Notification.Name {
    static let toggleAppLauncher = Notification.Name("poltertty.toggleAppLauncher")
}
