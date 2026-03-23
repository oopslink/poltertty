// macos/Sources/Features/Agent/Dashboard/AgentDashboardWindowController.swift
import AppKit
import SwiftUI

final class AgentDashboardWindowController: NSWindowController {
    static let shared = AgentDashboardWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Agent Dashboard"
        window.setFrameAutosaveName("AgentDashboardWindow")
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 340)
        window.contentView = NSHostingView(rootView: AgentDashboardView())
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }
}
