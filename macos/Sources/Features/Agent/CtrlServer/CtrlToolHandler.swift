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
        case "screenshot": return try await callScreenshot(arguments: arguments)
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
                    // 截取整个窗口
                    let window: NSWindow?
                    if let paneId {
                        window = Self.tcContaining(paneId: paneId)?.window
                    } else {
                        window = (NSApp.keyWindow as? TerminalWindow)
                            ?? NSApp.windows.first(where: { $0 is TerminalWindow }) as? TerminalWindow
                    }
                    guard let window else {
                        cont.resume(throwing: RPCError(code: -32603, message: "screenshot: window not found"))
                        return
                    }
                    let windowId = CGWindowID(window.windowNumber)
                    guard let cgImage = CGWindowListCreateImage(
                        .null,
                        .optionIncludingWindow,
                        windowId,
                        [.boundsIgnoreFraming]
                    ) else {
                        cont.resume(throwing: RPCError(code: -32603, message: "screenshot: capture failed"))
                        return
                    }
                    let img = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
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
