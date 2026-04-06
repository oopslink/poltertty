import Cocoa

/// 浮动 popup 终端窗口。作为 TerminalWindow 的 child window 显示，
/// 自动跟随父窗口移动。
class PopupOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// ESC 键回调（仅 shell popup 使用）。设置此回调后，ESC 不透传给终端进程。
    var onEscapePressed: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // keyCode 53 = Escape
        if event.keyCode == 53, let handler = onEscapePressed {
            handler()
            return
        }
        super.keyDown(with: event)
    }

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
