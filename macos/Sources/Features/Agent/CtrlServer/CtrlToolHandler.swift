// macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift
import Foundation
import AppKit
import OSLog

/// MCP tool 实现。callTool() 为 async throws，内部用 CheckedContinuation 桥接到 @MainActor。
final class CtrlToolHandler: Sendable {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "CtrlToolHandler"
    )

    struct RPCError: Error, Sendable {
        let code: Int
        let message: String
    }

    private let port: UInt16
    private let version: String
    private let instanceId: String

    init(port: UInt16) {
        self.port = port
        self.version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        self.instanceId = Bundle.main.bundleIdentifier ?? "unknown"
    }

    // MARK: - Public entry point

    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        switch name {
        case "ping":       return try await callPing()
        case "new_tab":    return try await callNewTab(arguments: arguments)
        case "list_panes": return try await callListPanes(arguments: arguments)
        case "focus_pane": return try await callFocusPane(arguments: arguments)
        case "send_text":  return try await callSendText(arguments: arguments)
        case "split_pane": return try await callSplitPane(arguments: arguments)
        case "set_pane_annotation": return try await callSetPaneAnnotation(arguments: arguments)
        case "get_pane_annotation": return try await callGetPaneAnnotation(arguments: arguments)
        case "screenshot":    return try await callScreenshot(arguments: arguments)
        case "click_window":          return try await callClickWindow(arguments: arguments)
        case "test_fullscreen_diff":  return try await callTestFullscreenDiff(arguments: arguments)
        case "git_panel_state":       return try await callGitPanelState(arguments: arguments)
        default:
            throw RPCError(code: -32601, message: "Unknown tool: \(name)")
        }
    }

    // MARK: - ping

    private func callPing() async throws -> String {
        let workspaces: [[String: Any]] = await MainActor.run {
            WorkspaceManager.shared.allWorkspaceIds().map { id in
                let isActive = WorkspaceManager.shared.windowForWorkspace(id)?.isKeyWindow == true
                return ["id": id.uuidString, "isActive": isActive]
            }
        }
        let obj: [String: Any] = [
            "instanceId": instanceId,
            "version": version,
            "port": Int(port),
            "workspaces": workspaces
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let str = String(data: data, encoding: .utf8) else {
            throw RPCError(code: -32603, message: "ping: serialization failed")
        }
        return str
    }

    // MARK: - new_tab

    private func callNewTab(arguments: [String: Any]) async throws -> String {
        let paneId: UUID = try await withCheckedThrowingContinuation { cont in
            Task { @MainActor in
                guard let tc = Self.resolveTC(arguments) else {
                    cont.resume(throwing: RPCError(code: -32603, message: "new_tab: no TerminalController found"))
                    return
                }
                let id = tc.addNewTab()
                cont.resume(returning: id)
            }
        }
        return #"{"paneId":"\#(paneId.uuidString)"}"#
    }

    // MARK: - list_panes

    private func callListPanes(arguments: [String: Any]) async throws -> String {
        let infos: [PaneInfo] = try await withCheckedThrowingContinuation { cont in
            Task { @MainActor in
                var result: [PaneInfo] = []

                if let wsIdStr = arguments["workspaceId"] as? String,
                   let wsId = UUID(uuidString: wsIdStr) {
                    if let tc = Self.tcForWorkspace(wsId) {
                        result = tc.listPanes()
                    }
                } else {
                    for wsId in WorkspaceManager.shared.allWorkspaceIds() {
                        if let tc = Self.tcForWorkspace(wsId) {
                            result.append(contentsOf: tc.listPanes())
                        }
                    }
                }
                cont.resume(returning: result)
            }
        }

        let arr: [[String: Any]] = infos.map { p in
            var d: [String: Any] = [
                "id": p.id.uuidString,
                "tabId": p.tabId.uuidString,
                "workspaceId": p.workspaceId.uuidString,
                "isActive": p.isActive
            ]
            if let title = p.title { d["title"] = title }
            if let annotation = p.annotation { d["annotation"] = annotation }
            return d
        }
        guard let data = try? JSONSerialization.data(withJSONObject: arr),
              let str = String(data: data, encoding: .utf8) else {
            throw RPCError(code: -32603, message: "list_panes: serialization failed")
        }
        return str
    }

    // MARK: - focus_pane

    private func callFocusPane(arguments: [String: Any]) async throws -> String {
        guard let paneIdStr = arguments["paneId"] as? String,
              let paneId = UUID(uuidString: paneIdStr) else {
            throw RPCError(code: -32602, message: "focus_pane: missing or invalid paneId")
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                guard let tc = Self.tcContaining(paneId: paneId) else {
                    cont.resume(throwing: RPCError(code: -32603, message: "focus_pane: pane not found"))
                    return
                }
                tc.switchToTab(containing: paneId)
                guard let view = tc.findSurface(id: paneId) else {
                    cont.resume(throwing: RPCError(code: -32603, message: "focus_pane: surface not found after tab switch"))
                    return
                }
                tc.focusSurface(view)
                Task { await EventBus.shared.emit(.paneFocused(paneId: paneId)) }
                cont.resume()
            }
        }
        return #"{"ok":true}"#
    }

    // MARK: - send_text

    private func callSendText(arguments: [String: Any]) async throws -> String {
        guard let text = arguments["text"] as? String else {
            throw RPCError(code: -32602, message: "send_text: missing text")
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                if let paneIdStr = arguments["paneId"] as? String,
                   let paneId = UUID(uuidString: paneIdStr) {
                    guard let tc = Self.tcContaining(paneId: paneId) else {
                        cont.resume(throwing: RPCError(code: -32603, message: "send_text: pane not found"))
                        return
                    }
                    tc.writeToSurface(text: text, surfaceId: paneId)
                } else {
                    let target = (NSApp.keyWindow as? TerminalWindow)
                        ?? NSApp.windows.first(where: { $0 is TerminalWindow }) as? TerminalWindow
                    guard let tc = target?.terminalController,
                          let surface = tc.focusedSurface else {
                        cont.resume(throwing: RPCError(code: -32603, message: "send_text: no focused surface"))
                        return
                    }
                    tc.writeToSurface(text: text, surfaceId: surface.id)
                }
                cont.resume()
            }
        }
        return #"{"ok":true}"#
    }

    // MARK: - split_pane

    private func callSplitPane(arguments: [String: Any]) async throws -> String {
        guard let paneIdStr = arguments["paneId"] as? String,
              let paneId = UUID(uuidString: paneIdStr) else {
            throw RPCError(code: -32602, message: "split_pane: missing or invalid paneId")
        }
        guard let dirStr = arguments["direction"] as? String,
              let direction = Self.parseDirection(dirStr) else {
            throw RPCError(code: -32602, message: "split_pane: missing or invalid direction (left|right|up|down)")
        }

        let newPaneId: UUID = try await withCheckedThrowingContinuation { cont in
            Task { @MainActor in
                guard let tc = Self.tcContaining(paneId: paneId) else {
                    cont.resume(throwing: RPCError(code: -32603, message: "split_pane: pane not found"))
                    return
                }
                tc.switchToTab(containing: paneId)
                guard let view = tc.findSurface(id: paneId) else {
                    cont.resume(throwing: RPCError(code: -32603, message: "split_pane: surface not found after tab switch"))
                    return
                }
                guard let newView = tc.newSplit(at: view, direction: direction) else {
                    cont.resume(throwing: RPCError(code: -32603, message: "split_pane: split failed"))
                    return
                }
                cont.resume(returning: newView.id)
            }
        }
        return #"{"newPaneId":"\#(newPaneId.uuidString)"}"#
    }

    // MARK: - set_pane_annotation

    private func callSetPaneAnnotation(arguments: [String: Any]) async throws -> String {
        guard let paneIdStr = arguments["paneId"] as? String,
              let paneId = UUID(uuidString: paneIdStr) else {
            throw RPCError(code: -32602, message: "set_pane_annotation: missing or invalid paneId")
        }

        let annotation = arguments["annotation"] as? String

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                if let text = annotation, !text.isEmpty {
                    PaneSelectorViewModel.shared.annotations[paneId] = text
                } else {
                    PaneSelectorViewModel.shared.annotations.removeValue(forKey: paneId)
                }
                cont.resume()
            }
        }
        return #"{"ok":true}"#
    }

    // MARK: - get_pane_annotation

    private func callGetPaneAnnotation(arguments: [String: Any]) async throws -> String {
        guard let paneIdStr = arguments["paneId"] as? String,
              let paneId = UUID(uuidString: paneIdStr) else {
            throw RPCError(code: -32602, message: "get_pane_annotation: missing or invalid paneId")
        }

        let annotation: String? = await MainActor.run {
            PaneSelectorViewModel.shared.annotations[paneId]
        }

        let obj: [String: Any] = ["annotation": annotation as Any]
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let str = String(data: data, encoding: .utf8) else {
            throw RPCError(code: -32603, message: "get_pane_annotation: serialization failed")
        }
        return str
    }

    // MARK: - screenshot

    /// 截屏目录
    private static let screenshotDir: String = {
        let dir = NSTemporaryDirectory() + "poltertty/screenshots"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    private func callScreenshot(arguments: [String: Any]) async throws -> String {
        let target = (arguments["target"] as? String) ?? "pane"
        guard target == "pane" || target == "window" else {
            throw RPCError(code: -32602, message: "screenshot: invalid target (pane|window)")
        }

        let paneId: UUID? = {
            guard let str = arguments["paneId"] as? String else { return nil }
            return UUID(uuidString: str)
        }()

        if arguments["paneId"] != nil && paneId == nil {
            throw RPCError(code: -32602, message: "screenshot: invalid paneId")
        }

        let image: NSImage = try await withCheckedThrowingContinuation { cont in
            Task { @MainActor in
                if target == "pane" {
                    // 截取单个 pane
                    let surface: Ghostty.SurfaceView?
                    if let paneId {
                        surface = Self.tcContaining(paneId: paneId)?.findSurface(id: paneId)
                    } else {
                        let tw = (NSApp.keyWindow as? TerminalWindow)
                            ?? NSApp.windows.first(where: { $0 is TerminalWindow }) as? TerminalWindow
                        surface = tw?.terminalController?.focusedSurface
                    }
                    guard let surface else {
                        cont.resume(throwing: RPCError(code: -32603, message: "screenshot: pane not found"))
                        return
                    }
                    guard let img = surface.asImage else {
                        cont.resume(throwing: RPCError(code: -32603, message: "screenshot: capture failed"))
                        return
                    }
                    cont.resume(returning: img)
                } else {
                    // 截取整个窗口（使用 bitmapImageRepForCachingDisplay 避免 CGWindowListCreateImage 权限问题）
                    let window: NSWindow?
                    if let paneId {
                        window = Self.tcContaining(paneId: paneId)?.window
                    } else {
                        window = (NSApp.keyWindow as? TerminalWindow)
                            ?? NSApp.windows.first(where: { $0 is TerminalWindow }) as? TerminalWindow
                    }
                    guard let window, let contentView = window.contentView else {
                        cont.resume(throwing: RPCError(code: -32603, message: "screenshot: window not found"))
                        return
                    }
                    // 使用 NSView 直接渲染（不需要 Screen Recording 权限，适用于 macOS 14+）
                    let bounds = contentView.bounds
                    guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
                        cont.resume(throwing: RPCError(code: -32603, message: "screenshot: bitmapImageRep failed"))
                        return
                    }
                    contentView.cacheDisplay(in: bounds, to: bitmap)
                    let img = NSImage(size: bounds.size)
                    img.addRepresentation(bitmap)
                    cont.resume(returning: img)
                }
            }
        }

        // NSImage → PNG Data → 写文件
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw RPCError(code: -32603, message: "screenshot: failed to encode PNG")
        }

        let filename = UUID().uuidString + ".png"
        let path = Self.screenshotDir + "/" + filename
        do {
            try pngData.write(to: URL(fileURLWithPath: path))
        } catch {
            throw RPCError(code: -32603, message: "screenshot: failed to save screenshot")
        }

        Self.logger.info("screenshot saved: \(path)")
        return #"{"path":"\#(path)"}"#
    }

    // MARK: - click_window

    /// 在应用窗口内模拟鼠标左键单击。
    /// 参数: x (从左), y (从上，截图坐标系), 均为窗口内容区域的逻辑像素。
    private func callClickWindow(arguments: [String: Any]) async throws -> String {
        guard let x = (arguments["x"] as? Double) ?? (arguments["x"] as? Int).map(Double.init),
              let y = (arguments["y"] as? Double) ?? (arguments["y"] as? Int).map(Double.init) else {
            throw RPCError(code: -32602, message: "click_window: missing x or y (window coords, y from top)")
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                let window = (NSApp.keyWindow as? TerminalWindow)
                    ?? NSApp.windows.first(where: { $0 is TerminalWindow }) as? TerminalWindow
                guard let window else {
                    cont.resume(throwing: RPCError(code: -32603, message: "click_window: no TerminalWindow found"))
                    return
                }

                // AppKit 坐标系 y=0 在左下角，需要翻转
                let contentHeight = window.contentView?.bounds.height ?? window.frame.height
                let appKitY = contentHeight - CGFloat(y)
                let windowPoint = NSPoint(x: CGFloat(x), y: appKitY)

                let makeEvent: (NSEvent.EventType, CGFloat) -> NSEvent? = { type, pressure in
                    NSEvent.mouseEvent(
                        with: type,
                        location: windowPoint,
                        modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber,
                        context: nil,
                        eventNumber: 0,
                        clickCount: 1,
                        pressure: Float(pressure)
                    )
                }

                if let down = makeEvent(.leftMouseDown, 1.0) { window.postEvent(down, atStart: false) }
                Thread.sleep(forTimeInterval: 0.05)
                if let up   = makeEvent(.leftMouseUp, 0.0)   { window.postEvent(up, atStart: false) }
                cont.resume()
            }
        }
        return #"{"ok":true,"x":\#(x),"y":\#(y)}"#
    }

    // MARK: - git_panel_state

    private func callGitPanelState(arguments: [String: Any]) async throws -> String {
        return try await withCheckedThrowingContinuation { cont in
            Task { @MainActor in
                let keyWin = NSApp.keyWindow
                let termWin = NSApp.windows.first(where: { $0 is TerminalWindow }) as? TerminalWindow
                let window = keyWin ?? termWin
                let isTerminal = window is TerminalWindow
                let windowCount = NSApp.windows.count
                let termWindowCount = NSApp.windows.filter { $0 is TerminalWindow }.count
                let wsId = window.flatMap { WorkspaceManager.shared.workspaceId(for: $0) }
                let allIds = WorkspaceManager.shared.allWorkspaceIds()
                let wsIdStr = wsId?.uuidString ?? "nil"
                let allIdsStr = allIds.map { $0.uuidString }.joined(separator: ",")
                var gitState = "no_wsId"
                if let id = wsId {
                    let vm = WorkspaceManager.shared.gitPanelViewModel(for: id)
                    let fbvm = WorkspaceManager.shared.fileBrowserViewModel(for: id)
                    gitState = "{\"isGitRepo\":\(vm.isGitRepo),\"isDiffMaximized\":\(vm.isDiffMaximized),\"hasDiff\":\(vm.selectedDiff != nil),\"changedCount\":\(vm.changedCount),\"isVisible\":\(fbvm.isVisible)}"
                } else if let firstId = allIds.first {
                    let vm = WorkspaceManager.shared.gitPanelViewModel(for: firstId)
                    let fbvm = WorkspaceManager.shared.fileBrowserViewModel(for: firstId)
                    gitState = "{\"isGitRepo\":\(vm.isGitRepo),\"isDiffMaximized\":\(vm.isDiffMaximized),\"hasDiff\":\(vm.selectedDiff != nil),\"changedCount\":\(vm.changedCount),\"isVisible\":\(fbvm.isVisible),\"fromAllIds\":true}"
                }
                cont.resume(returning: "{\"wsId\":\"\(wsIdStr)\",\"allIds\":\"\(allIdsStr)\",\"isTermWin\":\(isTerminal),\"winCount\":\(windowCount),\"termWinCount\":\(termWindowCount),\"state\":\(gitState)}")
            }
        }
    }

    // MARK: - test_fullscreen_diff

    /// 用于测试：切换到 Git 面板并将 diff 设为全屏状态，然后截图返回路径。
    /// 可选参数: workspaceId (UUID string)
    private func callTestFullscreenDiff(arguments: [String: Any]) async throws -> String {
        let path: String = try await withCheckedThrowingContinuation { cont in
            Task { @MainActor in
                // 找到目标 workspace：优先用参数，其次从 keyWindow 反推，最后用 allWorkspaceIds
                let wsId: UUID
                if let str = arguments["workspaceId"] as? String, let id = UUID(uuidString: str) {
                    wsId = id
                } else if let id = (NSApp.keyWindow ?? NSApp.windows.first(where: { $0 is TerminalWindow }))
                                    .flatMap({ WorkspaceManager.shared.workspaceId(for: $0) }) {
                    wsId = id
                } else if let first = WorkspaceManager.shared.allWorkspaceIds().first {
                    wsId = first
                } else {
                    cont.resume(throwing: RPCError(code: -32603, message: "test_fullscreen_diff: no workspace found"))
                    return
                }

                let fileBrowserVM = WorkspaceManager.shared.fileBrowserViewModel(for: wsId)
                let gitPanelVM = WorkspaceManager.shared.gitPanelViewModel(for: wsId)

                // 将根目录指向 poltertty 主仓库，确保加载到真实 git 仓库
                let gitRootPath = "/Users/oopslink/works/codes/oopslink/poltertty"
                fileBrowserVM.switchRoot(to: gitRootPath)

                // 确保面板可见并切换到 git tab
                fileBrowserVM.isVisible = true
                NotificationCenter.default.post(name: .toggleGitPanel, object: nil)

                // 用嵌套 Task + Task.sleep 避免 asyncAfter 重载歧义
                Task { @MainActor in
                    // 等待 git 仓库加载（需要时间检测 git repo）
                    try? await Task.sleep(nanoseconds: 3_000_000_000)

                    // 构造一个简单的测试 diff（GitFileDiff）
                    let lines: [GitDiffLine] = [
                        GitDiffLine(id: 1, origin: .context, oldLineNo: 1, newLineNo: 1, content: " // 测试文件"),
                        GitDiffLine(id: 2, origin: .removed, oldLineNo: 2, newLineNo: nil, content: "-// 旧代码"),
                        GitDiffLine(id: 3, origin: .added, oldLineNo: nil, newLineNo: 3, content: "+// 新代码（全屏修复后不覆盖侧边栏）"),
                    ]
                    let patch = GitPatch(header: "@@ -1,3 +1,3 @@", lines: lines)
                    let diff = GitFileDiff(path: "TestFile.swift", oldPath: nil, delta: .modified, patches: [patch])
                    gitPanelVM.isGitRepo = true
                    gitPanelVM.selectedDiff = diff
                    gitPanelVM.isDiffMaximized = true
                    fileBrowserVM.isPreviewFullscreen = true

                    // 等待布局更新后截图（更长时间确保 SwiftUI 渲染完成）
                    try? await Task.sleep(nanoseconds: 1_000_000_000)

                    // 强制触发 AppKit 渲染管线
                    NSApp.windows.forEach { $0.contentView?.displayIfNeeded() }
                    try? await Task.sleep(nanoseconds: 100_000_000)

                    // 用 workspace 对应的 window（不用 keyWindow，因为 keyWindow 可能是未注册的窗口）
                    let window = WorkspaceManager.shared.windowForWorkspace(wsId)
                        ?? (NSApp.keyWindow as? TerminalWindow)
                        ?? NSApp.windows.first(where: { $0 is TerminalWindow })
                    guard let contentView = window?.contentView else {
                        cont.resume(throwing: RPCError(code: -32603, message: "test_fullscreen_diff: window not found"))
                        return
                    }
                    let bounds = contentView.bounds
                    guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
                        cont.resume(throwing: RPCError(code: -32603, message: "test_fullscreen_diff: bitmap failed"))
                        return
                    }
                    contentView.cacheDisplay(in: bounds, to: bitmap)
                    let img = NSImage(size: bounds.size)
                    img.addRepresentation(bitmap)
                    guard let tiff = img.tiffRepresentation,
                          let bmp = NSBitmapImageRep(data: tiff),
                          let png = bmp.representation(using: .png, properties: [:]) else {
                        cont.resume(throwing: RPCError(code: -32603, message: "test_fullscreen_diff: encode failed"))
                        return
                    }
                    let filename = UUID().uuidString + ".png"
                    let filePath = Self.screenshotDir + "/" + filename
                    try? png.write(to: URL(fileURLWithPath: filePath))
                    cont.resume(returning: filePath)
                }
            }
        }
        return #"{"path":"\#(path)"}"#
    }

    // MARK: - Helpers

    @MainActor
    private static func resolveTC(_ arguments: [String: Any]) -> TerminalController? {
        if let wsIdStr = arguments["workspaceId"] as? String,
           let wsId = UUID(uuidString: wsIdStr) {
            return tcForWorkspace(wsId)
        }
        let target = (NSApp.keyWindow as? TerminalWindow)
            ?? NSApp.windows.first(where: { $0 is TerminalWindow }) as? TerminalWindow
        return target?.terminalController
    }

    @MainActor
    private static func tcForWorkspace(_ wsId: UUID) -> TerminalController? {
        (WorkspaceManager.shared.windowForWorkspace(wsId) as? TerminalWindow)?.terminalController
    }

    @MainActor
    private static func tcContaining(paneId: UUID) -> TerminalController? {
        for wsId in WorkspaceManager.shared.allWorkspaceIds() {
            if let tc = tcForWorkspace(wsId),
               tc.findSurface(id: paneId) != nil {
                return tc
            }
        }
        return nil
    }

    private static func parseDirection(_ s: String) -> SplitTree<Ghostty.SurfaceView>.NewDirection? {
        switch s {
        case "right": return .right
        case "left":  return .left
        case "up":    return .up
        case "down":  return .down
        default:      return nil
        }
    }
}
