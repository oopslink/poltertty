// macos/Sources/Features/Agent/Dashboard/AgentDashboardWindowController.swift
import AppKit
import SwiftUI

/// 无 titlebar 浮窗，Esc 关闭。
private final class DashboardWindow: NSWindow {
    override var canBecomeKey: Bool { true }

    /// cancelOperation 由 Esc 键触发（NSResponder 标准行为）
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

final class AgentDashboardWindowController: NSWindowController {
    static let shared = AgentDashboardWindowController()

    private init() {
        let window = DashboardWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
            styleMask: [.resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.setFrameAutosaveName("AgentDashboardWindow")
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 340)
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = NSHostingView(rootView: AgentDashboardView())
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }
}
