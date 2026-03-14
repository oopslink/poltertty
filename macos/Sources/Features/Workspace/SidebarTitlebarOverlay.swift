// macos/Sources/Features/Workspace/SidebarTitlebarOverlay.swift
import AppKit

class SidebarTitlebarOverlay: NSTitlebarAccessoryViewController {
    private var sidebarWidth: CGFloat

    init(sidebarWidth: CGFloat) {
        self.sidebarWidth = sidebarWidth
        super.init(nibName: nil, bundle: nil)
        self.layoutAttribute = .leading
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func loadView() {
        let overlay = NSView(frame: NSRect(x: 0, y: 0, width: sidebarWidth, height: 38))
        overlay.wantsLayer = true
        // Use the window background color to blend seamlessly
        overlay.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.95).cgColor
        self.view = overlay
    }

    func updateWidth(_ width: CGFloat) {
        sidebarWidth = width
        view.frame.size.width = width
        view.needsLayout = true
    }
}
