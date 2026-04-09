import Cocoa
import SwiftUI

/// 管理 shell popup 的生命周期。
/// - 关闭只是 orderOut，进程继续保留（会话保留语义）
/// - 进程自然退出时销毁窗口和 surface，下次 toggle 重建
@MainActor
class PopupOverlayManager {

    enum PopupType {
        case shell
    }

    private let ghostty: Ghostty.App
    private weak var parentWindow: NSWindow?
    private let workspaceId: UUID?

    private var shellSurface: Ghostty.SurfaceView?
    private var shellPopupWindow: PopupOverlayWindow?

    /// 打开 popup 前记录的 firstResponder，关闭时归还
    private weak var previousFirstResponder: NSResponder?

    private var shellExitObserver: (any NSObjectProtocol)?

    /// Local event monitor，用于捕获 ESC 键以关闭 shell popup
    private var escapeEventMonitor: Any?

    init(ghostty: Ghostty.App, parentWindow: NSWindow, workspaceId: UUID? = nil) {
        self.ghostty = ghostty
        self.parentWindow = parentWindow
        self.workspaceId = workspaceId
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(parentWindowDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: parentWindow
        )
        setupEscapeMonitor()
    }

    deinit {
        if let token = shellExitObserver {
            NotificationCenter.default.removeObserver(token)
        }
        if let monitor = escapeEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: parentWindow)
    }

    /// 安装 local event monitor，当 shell popup 可见时拦截 ESC 键
    private func setupEscapeMonitor() {
        escapeEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.keyCode == 53 else { return event }
            if self.isVisible(self.shellPopupWindow), let popupWin = self.shellPopupWindow {
                let keyWin = NSApp.keyWindow
                if keyWin === popupWin || keyWin === self.parentWindow {
                    self.dismiss(popupWin)
                    return nil
                }
            }
            return event
        }
    }

    // MARK: - Window Resize

    @objc private func parentWindowDidResize(_ notification: Notification) {
        guard let parent = parentWindow else { return }
        let contentRect = parent.contentLayoutRect
        let popupWidth  = contentRect.width  * 0.8
        let popupHeight = contentRect.height * 0.7
        let originX = parent.frame.origin.x + contentRect.origin.x + (contentRect.width  - popupWidth)  / 2
        let originY = parent.frame.origin.y + contentRect.origin.y + (contentRect.height - popupHeight) / 2
        let newFrame = NSRect(x: originX, y: originY, width: popupWidth, height: popupHeight)

        if let popup = shellPopupWindow, popup.isVisible {
            popup.setFrame(newFrame, display: true)
        }
    }

    // MARK: - Public API

    func toggle(_ type: PopupType) {
        switch type {
        case .shell:
            if isVisible(shellPopupWindow) {
                dismiss(shellPopupWindow)
            } else {
                show(type: .shell)
            }
        }
    }

    func dismissAll() {
        dismiss(shellPopupWindow)
    }

    // MARK: - Private helpers

    private func isVisible(_ window: PopupOverlayWindow?) -> Bool {
        window?.isVisible ?? false
    }

    private func show(type: PopupType) {
        guard let parent = parentWindow, ghostty.app != nil else { return }

        previousFirstResponder = parent.firstResponder

        let surface = getOrCreateSurface(type: type)
        let popup = getOrCreateWindow(type: type, surface: surface)

        let contentRect = parent.contentLayoutRect
        let popupWidth  = contentRect.width  * 0.8
        let popupHeight = contentRect.height * 0.7
        let originX = parent.frame.origin.x + contentRect.origin.x + (contentRect.width  - popupWidth)  / 2
        let originY = parent.frame.origin.y + contentRect.origin.y + (contentRect.height - popupHeight) / 2
        popup.setFrame(NSRect(x: originX, y: originY, width: popupWidth, height: popupHeight), display: false)

        if popup.parent == nil {
            parent.addChildWindow(popup, ordered: .above)
        }

        popup.alphaValue = 0
        popup.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            popup.animator().alphaValue = 1
        }
    }

    private func dismiss(_ popup: PopupOverlayWindow?) {
        guard let popup, popup.isVisible else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            popup.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            popup.orderOut(nil)
            popup.alphaValue = 1
            self?.parentWindow?.makeKeyAndOrderFront(nil)
            if let prev = self?.previousFirstResponder {
                self?.parentWindow?.makeFirstResponder(prev)
            }
        }
    }

    private func getOrCreateSurface(type: PopupType) -> Ghostty.SurfaceView {
        switch type {
        case .shell:
            if let existing = shellSurface { return existing }
            var config = Ghostty.SurfaceConfiguration()
            config.workspaceId = workspaceId
            let surface = Ghostty.SurfaceView(ghostty.app!, baseConfig: config)
            shellSurface = surface
            observeExit(surface: surface, type: .shell)
            return surface
        }
    }

    private func getOrCreateWindow(type: PopupType, surface: Ghostty.SurfaceView) -> PopupOverlayWindow {
        switch type {
        case .shell:
            if let existing = shellPopupWindow { return existing }
            let win = makeWindow(surface: surface, type: type)
            shellPopupWindow = win
            return win
        }
    }

    private func makeWindow(surface: Ghostty.SurfaceView, type: PopupType) -> PopupOverlayWindow {
        let win = PopupOverlayWindow()
        let hostingView = NSHostingView(
            rootView: Ghostty.SurfaceWrapper(surfaceView: surface)
                .environmentObject(ghostty)
        )
        win.contentView = hostingView

        if type == .shell {
            win.onEscapePressed = { [weak self, weak win] in
                guard let win else { return }
                self?.dismiss(win)
            }
        }
        return win
    }

    private func observeExit(surface: Ghostty.SurfaceView, type: PopupType) {
        let token = NotificationCenter.default.addObserver(
            forName: Ghostty.Notification.ghosttyCloseSurface,
            object: surface,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let processAlive = notification.userInfo?["process_alive"] as? Bool ?? false
            guard !processAlive else { return }

            switch type {
            case .shell:
                if let token = self.shellExitObserver {
                    NotificationCenter.default.removeObserver(token)
                    self.shellExitObserver = nil
                }
                self.shellPopupWindow?.close()
                self.shellPopupWindow = nil
                self.shellSurface = nil
            }
        }
        switch type {
        case .shell: shellExitObserver = token
        }
    }
}
