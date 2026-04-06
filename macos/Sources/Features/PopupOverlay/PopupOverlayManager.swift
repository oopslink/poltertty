import Cocoa
import SwiftUI

/// 管理 shell / lazygit 两种 popup 的生命周期。
/// - 关闭只是 orderOut，进程继续保留（会话保留语义）
/// - 进程自然退出时销毁窗口和 surface，下次 toggle 重建
/// - 同一时刻只显示一个 popup（互斥）
@MainActor
class PopupOverlayManager {

    enum PopupType {
        case shell
        case lazygit
    }

    private let ghostty: Ghostty.App
    private weak var parentWindow: NSWindow?
    private let workspaceId: UUID?

    private var shellSurface: Ghostty.SurfaceView?
    private var lazygitSurface: Ghostty.SurfaceView?

    private var shellPopupWindow: PopupOverlayWindow?
    private var lazygitPopupWindow: PopupOverlayWindow?

    /// 打开 popup 前记录的 firstResponder，关闭时归还
    private weak var previousFirstResponder: NSResponder?

    private var shellExitObserver: (any NSObjectProtocol)?
    private var lazygitExitObserver: (any NSObjectProtocol)?

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
    }

    deinit {
        if let token = shellExitObserver {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = lazygitExitObserver {
            NotificationCenter.default.removeObserver(token)
        }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: parentWindow)
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

        [shellPopupWindow, lazygitPopupWindow].compactMap { $0 }.filter { $0.isVisible }.forEach { popup in
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
                dismissOther(than: .shell)
                show(type: .shell)
            }
        case .lazygit:
            if isVisible(lazygitPopupWindow) {
                dismiss(lazygitPopupWindow)
            } else {
                dismissOther(than: .lazygit)
                show(type: .lazygit)
            }
        }
    }

    func dismissAll() {
        dismiss(shellPopupWindow)
        dismiss(lazygitPopupWindow)
    }

    // MARK: - Private helpers

    private func isVisible(_ window: PopupOverlayWindow?) -> Bool {
        window?.isVisible ?? false
    }

    private func dismissOther(than type: PopupType) {
        switch type {
        case .shell:    dismiss(lazygitPopupWindow)
        case .lazygit:  dismiss(shellPopupWindow)
        }
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
            // command = nil → 使用默认 shell
            let surface = Ghostty.SurfaceView(ghostty.app!, baseConfig: config)
            shellSurface = surface
            observeExit(surface: surface, type: .shell)
            return surface

        case .lazygit:
            if let existing = lazygitSurface { return existing }
            var config = Ghostty.SurfaceConfiguration()
            config.workspaceId = workspaceId
            config.command = "lazygit"
            let surface = Ghostty.SurfaceView(ghostty.app!, baseConfig: config)
            lazygitSurface = surface
            observeExit(surface: surface, type: .lazygit)
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
        case .lazygit:
            if let existing = lazygitPopupWindow { return existing }
            let win = makeWindow(surface: surface, type: type)
            lazygitPopupWindow = win
            return win
        }
    }

    private func makeWindow(surface: Ghostty.SurfaceView, type: PopupType) -> PopupOverlayWindow {
        let win = PopupOverlayWindow()
        // SurfaceWrapper 签名：SurfaceWrapper(surfaceView:)，需要注入 ghostty 环境对象
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
        // ghosttyCloseSurface 在 libghostty 进程退出时（processAlive=false）发出
        let token = NotificationCenter.default.addObserver(
            forName: Ghostty.Notification.ghosttyCloseSurface,
            object: surface,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            // 仅在进程已退出时销毁（processAlive=false），保持会话保留语义
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
            case .lazygit:
                if let token = self.lazygitExitObserver {
                    NotificationCenter.default.removeObserver(token)
                    self.lazygitExitObserver = nil
                }
                self.lazygitPopupWindow?.close()
                self.lazygitPopupWindow = nil
                self.lazygitSurface = nil
            }
        }
        switch type {
        case .shell:    shellExitObserver = token
        case .lazygit:  lazygitExitObserver = token
        }
    }
}
