// macos/Sources/Features/Agent/Dashboard/PaneLocator.swift
import Foundation
import AppKit

/// 跨窗口 pane 导航：从 surfaceId 定位到目标窗口 → 切 tab → 高亮 pane
@MainActor
enum PaneLocator {
    static let highlightSurface = Notification.Name("poltertty.highlightSurface")

    /// 导航到指定 surfaceId 所在的 pane
    static func navigate(to surfaceId: UUID) {
        // 1. 遍历所有窗口，找到持有该 surfaceId 的 TerminalController
        guard let controller = findController(for: surfaceId) else { return }

        // 2. 前置窗口
        controller.window?.makeKeyAndOrderFront(nil)

        // 3. 切换到包含该 surfaceId 的 tab
        controller.switchToTab(containing: surfaceId)

        // 4. 发送高亮通知
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(
                name: highlightSurface,
                object: nil,
                userInfo: ["surfaceId": surfaceId]
            )
        }
    }

    private static func findController(for surfaceId: UUID) -> TerminalController? {
        for window in NSApp.windows {
            guard let controller = window.windowController as? TerminalController else { continue }
            if controller.surfaceTreeContains(surfaceId) {
                return controller
            }
        }
        return nil
    }
}
