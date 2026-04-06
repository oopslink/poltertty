import Cocoa

/// 浮动 popup 终端窗口。作为 TerminalWindow 的 child window 显示，
/// 自动跟随父窗口移动。
class PopupOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isMovable = false
    }
}
