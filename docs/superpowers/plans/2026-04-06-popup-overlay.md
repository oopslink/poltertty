# Popup Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 TerminalWindow 上方以 child window 方式叠加浮动终端 popup，⌥⌘I 打开空 shell，⌥⌘G 打开 lazygit，两者均保留会话，关闭只隐藏不销毁。

**Architecture:** 新建 `PopupOverlayWindow`（NSPanel child window）和 `PopupOverlayManager`（生命周期管理），挂载到 `TerminalController`。菜单快捷键通过 `AppDelegate.setupWorkspaceMenu()` 注册，toggle 动作通过 `NotificationCenter` 派发（与现有 `toggleFileBrowser` 模式一致）。

**Tech Stack:** Swift, AppKit (NSPanel, NSWindow child window API), Ghostty.SurfaceView, NotificationCenter

---

## 文件结构

**新增：**
- `macos/Sources/Features/PopupOverlay/PopupOverlayWindow.swift` — NSPanel 子类
- `macos/Sources/Features/PopupOverlay/PopupOverlayManager.swift` — 生命周期管理（持有两个可选 SurfaceView）

**修改：**
- `macos/Sources/Features/Terminal/TerminalController.swift` — 持有 `PopupOverlayManager`，监听 toggle 通知
- `macos/Sources/App/macOS/AppDelegate.swift` — `setupWorkspaceMenu()` 新增两个菜单项 + 两个 `@objc` action

---

## Task 1：PopupOverlayWindow

**Files:**
- Create: `macos/Sources/Features/PopupOverlay/PopupOverlayWindow.swift`

- [ ] **创建文件，内容如下：**

```swift
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
```

- [ ] **Build 确认无错误：**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

- [ ] **Commit:**

```bash
git add macos/Sources/Features/PopupOverlay/PopupOverlayWindow.swift
git commit -m "feat(popup): add PopupOverlayWindow NSPanel"
```

---

## Task 2：PopupOverlayManager

**Files:**
- Create: `macos/Sources/Features/PopupOverlay/PopupOverlayManager.swift`

- [ ] **创建文件，内容如下：**

```swift
import Cocoa
import SwiftUI

/// 管理两种 popup（shell / lazygit）的生命周期。
/// - 关闭只是 orderOut，进程保留；进程自然退出后下次打开重建。
/// - 同一时刻只有一个 popup 显示。
@MainActor
class PopupOverlayManager {

    enum PopupType {
        case shell
        case lazygit
    }

    private let ghostty: Ghostty.App
    private weak var parentWindow: NSWindow?

    private var shellSurface: Ghostty.SurfaceView?
    private var lazygitSurface: Ghostty.SurfaceView?

    private var shellPopupWindow: PopupOverlayWindow?
    private var lazygitPopupWindow: PopupOverlayWindow?

    /// popup 打开前持有焦点的 view，关闭时归还
    private weak var previousFirstResponder: NSResponder?

    init(ghostty: Ghostty.App, parentWindow: NSWindow) {
        self.ghostty = ghostty
        self.parentWindow = parentWindow
    }

    // MARK: - Public

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

    // MARK: - Private

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

        // 记录当前 first responder 以便关闭时归还
        previousFirstResponder = parent.firstResponder

        let surface = getOrCreateSurface(type: type, app: app)
        let popup = getOrCreateWindow(type: type, surface: surface)

        // 计算 frame：父窗口内容区 80% × 70%，居中
        let contentRect = parent.contentLayoutRect
        let popupWidth  = contentRect.width  * 0.8
        let popupHeight = contentRect.height * 0.7
        let originX = parent.frame.origin.x + contentRect.origin.x + (contentRect.width  - popupWidth)  / 2
        let originY = parent.frame.origin.y + contentRect.origin.y + (contentRect.height - popupHeight) / 2
        popup.setFrame(NSRect(x: originX, y: originY, width: popupWidth, height: popupHeight), display: false)

        // 添加为 child window
        if popup.parent == nil {
            parent.addChildWindow(popup, ordered: .above)
        }

        // 动画：alpha 0 → 1
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
        } completionHandler: {
            popup.orderOut(nil)
            popup.alphaValue = 1  // reset for next show
            // 归还焦点
            self.parentWindow?.makeKeyAndOrderFront(nil)
            if let prev = self.previousFirstResponder {
                self.parentWindow?.makeFirstResponder(prev)
            }
        }
    }

    private func getOrCreateSurface(type: PopupType, app: ghostty_app_t) -> Ghostty.SurfaceView {
        switch type {
        case .shell:
            if let existing = shellSurface { return existing }
            var config = Ghostty.SurfaceConfiguration()
            // command = nil → 默认 shell
            let surface = Ghostty.SurfaceView(ghostty.app!, baseConfig: config)
            shellSurface = surface
            observeExit(surface: surface, type: .shell)
            return surface

        case .lazygit:
            if let existing = lazygitSurface { return existing }
            var config = Ghostty.SurfaceConfiguration()
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
            let win = makeWindow(surface: surface)
            shellPopupWindow = win
            return win

        case .lazygit:
            if let existing = lazygitPopupWindow { return existing }
            let win = makeWindow(surface: surface)
            lazygitPopupWindow = win
            return win
        }
    }

    private func makeWindow(surface: Ghostty.SurfaceView) -> PopupOverlayWindow {
        let win = PopupOverlayWindow()
        let hostingView = NSHostingView(
            rootView: Ghostty.SurfaceWrapper(
                app: ghostty,
                view: surface
            )
        )
        win.contentView = hostingView
        return win
    }

    /// surface 进程退出时销毁 surface 和 window，下次 toggle 重建
    private func observeExit(surface: Ghostty.SurfaceView, type: PopupType) {
        NotificationCenter.default.addObserver(
            forName: Ghostty.Notification.ghosttyCloseSurface,
            object: surface,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            switch type {
            case .shell:
                self.shellPopupWindow?.close()
                self.shellPopupWindow = nil
                self.shellSurface = nil
            case .lazygit:
                self.lazygitPopupWindow?.close()
                self.lazygitPopupWindow = nil
                self.lazygitSurface = nil
            }
        }
    }
}
```

- [ ] **Build 确认无错误：**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`（若有编译错误参考下方说明）

> **SurfaceWrapper 签名核查：** 若 `Ghostty.SurfaceWrapper` 初始化参数不匹配，在 Xcode 中搜索 `struct SurfaceWrapper` 或 `SurfaceWrapper(` 确认实际参数名，按实际调整。

- [ ] **Commit:**

```bash
git add macos/Sources/Features/PopupOverlay/PopupOverlayManager.swift
git commit -m "feat(popup): add PopupOverlayManager with shell/lazygit lifecycle"
```

---

## Task 3：接入 TerminalController

**Files:**
- Modify: `macos/Sources/Features/Terminal/TerminalController.swift`

- [ ] **在 TerminalController 类顶部（其他 private var 属性旁）添加：**

```swift
/// Popup overlay manager（shell + lazygit popup）
private var popupOverlayManager: PopupOverlayManager?
```

- [ ] **在 `windowDidLoad()` 或 `windowDidBecomeKey()` 的适当位置（window 已初始化后）添加初始化：**

找到 `TerminalController.swift` 中 `windowDidLoad` 方法，在末尾添加：

```swift
// 初始化 popup overlay manager
if let win = window {
    popupOverlayManager = PopupOverlayManager(ghostty: ghostty, parentWindow: win)
}
```

- [ ] **在 TerminalController 中添加 toggle 响应方法（与其他 `@objc` 方法放在一起）：**

```swift
@objc func toggleShellPopup(_ sender: Any?) {
    popupOverlayManager?.toggle(.shell)
}

@objc func toggleLazygitPopup(_ sender: Any?) {
    popupOverlayManager?.toggle(.lazygit)
}
```

- [ ] **在窗口关闭时关闭 popup（找到 `windowWillClose` 或 `deinit`，添加）：**

```swift
popupOverlayManager?.dismissAll()
```

- [ ] **Build 确认无错误：**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Commit:**

```bash
git add macos/Sources/Features/Terminal/TerminalController.swift
git commit -m "feat(popup): wire PopupOverlayManager into TerminalController"
```

---

## Task 4：注册菜单快捷键

**Files:**
- Modify: `macos/Sources/App/macOS/AppDelegate.swift`

- [ ] **在 `Notification.Name` 扩展中添加两个通知名（与 `toggleFileBrowser` / `toggleBrowserPanel` 同处）：**

搜索 `static let toggleFileBrowser`，在旁边添加：

```swift
static let toggleShellPopup    = Notification.Name("poltertty.toggleShellPopup")
static let toggleLazygitPopup  = Notification.Name("poltertty.toggleLazygitPopup")
```

- [ ] **在 `setupWorkspaceMenu()` 的 File Browser 菜单项后面添加两条（`workspaceMenu.addItem(toggleFileBrowser)` 之后）：**

```swift
let shellPopupItem = NSMenuItem(
    title: "Toggle Shell Popup",
    action: #selector(toggleShellPopup(_:)),
    keyEquivalent: "i"
)
shellPopupItem.keyEquivalentModifierMask = [.command, .option]
workspaceMenu.addItem(shellPopupItem)

let lazygitPopupItem = NSMenuItem(
    title: "Toggle Lazygit Popup",
    action: #selector(toggleLazygitPopup(_:)),
    keyEquivalent: "g"
)
lazygitPopupItem.keyEquivalentModifierMask = [.command, .option]
workspaceMenu.addItem(lazygitPopupItem)
```

- [ ] **在 AppDelegate 中添加两个 `@objc` action（与 `toggleFileBrowser` 同处）：**

```swift
@objc func toggleShellPopup(_ sender: Any?) {
    guard let tc = NSApp.keyWindow?.windowController as? TerminalController else { return }
    tc.toggleShellPopup(sender)
}

@objc func toggleLazygitPopup(_ sender: Any?) {
    guard let tc = NSApp.keyWindow?.windowController as? TerminalController else { return }
    tc.toggleLazygitPopup(sender)
}
```

- [ ] **Build 确认无错误：**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Commit:**

```bash
git add macos/Sources/App/macOS/AppDelegate.swift
git commit -m "feat(popup): register ⌥⌘I / ⌥⌘G menu shortcuts for popup overlay"
```

---

## Task 5：ESC 关闭 shell popup

Shell popup 按 ESC 应隐藏 popup（不透传给 shell 进程）。

**Files:**
- Modify: `macos/Sources/Features/PopupOverlay/PopupOverlayWindow.swift`

- [ ] **在 `PopupOverlayWindow` 中 override `keyDown`：**

```swift
/// ESC 键关闭 shell popup（不透传）。
/// lazygit popup 的 ESC 由 lazygit 进程自行处理，无需拦截。
var onEscapePressed: (() -> Void)?

override func keyDown(with event: NSEvent) {
    // keyCode 53 = Escape
    if event.keyCode == 53, let handler = onEscapePressed {
        handler()
        return
    }
    super.keyDown(with: event)
}
```

- [ ] **在 `PopupOverlayManager.makeWindow(surface:)` 中，shell popup 设置 ESC handler，lazygit popup 不设置：**

将 `makeWindow` 拆为带 type 参数：

```swift
private func makeWindow(surface: Ghostty.SurfaceView, type: PopupType) -> PopupOverlayWindow {
    let win = PopupOverlayWindow()
    let hostingView = NSHostingView(
        rootView: Ghostty.SurfaceWrapper(
            app: ghostty,
            view: surface
        )
    )
    win.contentView = hostingView

    if type == .shell {
        win.onEscapePressed = { [weak self] in
            self?.dismiss(win)
        }
    }
    return win
}
```

同步更新 `getOrCreateWindow` 中的调用：
```swift
let win = makeWindow(surface: surface, type: type)
```

- [ ] **Build 确认无错误：**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Commit:**

```bash
git add macos/Sources/Features/PopupOverlay/PopupOverlayWindow.swift \
        macos/Sources/Features/PopupOverlay/PopupOverlayManager.swift
git commit -m "feat(popup): ESC closes shell popup without propagating to process"
```

---

## Task 6：父窗口 resize 时更新 popup frame

**Files:**
- Modify: `macos/Sources/Features/PopupOverlay/PopupOverlayManager.swift`

- [ ] **在 `init` 中注册 resize 通知：**

```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(parentWindowDidResize(_:)),
    name: NSWindow.didResizeNotification,
    object: parentWindow
)
```

- [ ] **添加 resize handler（将 show 中的 frame 计算逻辑提取为独立方法）：**

```swift
@objc private func parentWindowDidResize(_ notification: Notification) {
    [shellPopupWindow, lazygitPopupWindow].compactMap { $0 }.filter { $0.isVisible }.forEach { popup in
        guard let parent = parentWindow else { return }
        let contentRect = parent.contentLayoutRect
        let popupWidth  = contentRect.width  * 0.8
        let popupHeight = contentRect.height * 0.7
        let originX = parent.frame.origin.x + contentRect.origin.x + (contentRect.width  - popupWidth)  / 2
        let originY = parent.frame.origin.y + contentRect.origin.y + (contentRect.height - popupHeight) / 2
        popup.setFrame(NSRect(x: originX, y: originY, width: popupWidth, height: popupHeight), display: true)
    }
}
```

- [ ] **Build 确认无错误：**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Commit:**

```bash
git add macos/Sources/Features/PopupOverlay/PopupOverlayManager.swift
git commit -m "feat(popup): update popup frame on parent window resize"
```

---

## Task 7：手动验证

- [ ] **运行 App，按 ⌥⌘I：** 出现浮动 shell popup，覆盖父窗口约 80%×70%，居中
- [ ] **按 ESC：** popup 以动画关闭，焦点回到原终端
- [ ] **再按 ⌥⌘I：** popup 重新打开，shell 历史仍在（会话保留）
- [ ] **按 ⌥⌘G：** lazygit popup 打开（shell popup 若开着先关闭）
- [ ] **在 lazygit 里按 q 退出：** popup 关闭；再按 ⌥⌘G 重新创建 lazygit 进程
- [ ] **拖动父窗口：** popup 自动跟随（child window 机制）
- [ ] **拖动父窗口边缘 resize：** popup 重新居中、尺寸更新

- [ ] **最终 commit:**

```bash
git add -A
git commit -m "feat(popup): popup overlay complete - ⌥⌘I shell, ⌥⌘G lazygit"
```
