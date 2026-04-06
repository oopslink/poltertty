// macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift
import Foundation
import AppKit
import OSLog
import WebKit

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
        case "get_instance_info": return try await callPing()
        case "create_tab":       return try await callNewTab(arguments: arguments)
        case "list_panes":       return try await callListPanes(arguments: arguments)
        case "focus_pane":       return try await callFocusPane(arguments: arguments)
        case "send_text":        return try await callSendText(arguments: arguments)
        case "split_pane":       return try await callSplitPane(arguments: arguments)
        case "set_pane_annotation": return try await callSetPaneAnnotation(arguments: arguments)
        case "get_pane_annotation": return try await callGetPaneAnnotation(arguments: arguments)
        case "list_worktrees":      return try await callListWorktrees(arguments: arguments)
        case "create_worktree":          return try await callCreateWorktree(arguments: arguments)
        case "open_worktree_in_split":   return try await callOpenWorktreeInSplit(arguments: arguments)
        case "get_git_status":           return try await callGetGitStatus(arguments: arguments)
        case "click_window":          return try await callClickWindow(arguments: arguments)
        case "test_fullscreen_diff":  return try await callTestFullscreenDiff(arguments: arguments)
        case "git_panel_state":       return try await callGitPanelState(arguments: arguments)
        case "open_workspace":        return try await callOpenWorkspace(arguments: arguments)
        case "show_agent_dashboard":  return try await callShowAgentDashboard()
        case "show_file_browser":     return try await callShowFileBrowser(arguments: arguments)
        case "show_git_panel":        return try await callShowGitPanel(arguments: arguments)
        case "browser_new_tab":        return try await callBrowserNewTab(arguments: arguments)
        case "browser_close_tab":      return try await callBrowserCloseTab(arguments: arguments)
        case "browser_focus_tab":      return try await callBrowserFocusTab(arguments: arguments)
        case "browser_list_tabs":      return try await callBrowserListTabs(arguments: arguments)
        case "browser_navigate":       return try await callBrowserNavigate(arguments: arguments)
        case "browser_snapshot":       return try await callBrowserSnapshot(arguments: arguments)
        case "browser_click":          return try await callBrowserClick(arguments: arguments)
        case "browser_fill":           return try await callBrowserFill(arguments: arguments)
        case "notify":               return try await callNotify(arguments: arguments)
        case "open_in_file_browser": return try await callOpenInFileBrowser(arguments: arguments)
        case "set_agent_label":      return try await callSetAgentLabel(arguments: arguments)
        case "get_workspace_state":  return try await callGetWorkspaceState(arguments: arguments)
        case "show_agent_monitor":    return try await callShowAgentMonitor(arguments: arguments)
        case "send_key":              return try await callSendKey(arguments: arguments)
        default:
            throw RPCError(code: -32601, message: "Unknown tool: \(name)")
        }
    }

    // MARK: - ping

    private func callPing() async throws -> String {
        let workspaces: [[String: Any]] = await MainActor.run {
            WorkspaceManager.shared.allWorkspaceIds().map { id in
                let ws = WorkspaceManager.shared.workspace(for: id)
                let isActive = WorkspaceManager.shared.windowForWorkspace(id)?.isKeyWindow == true
                var d: [String: Any] = ["id": id.uuidString, "isActive": isActive]
                if let ws {
                    d["name"] = ws.name
                    d["rootDirectory"] = ws.rootDirExpanded
                }
                return d
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
                "isActive": p.isActive,
                "tabIndex": p.tabIndex,
                "paneIndex": p.paneIndex
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
        let command = arguments["command"] as? String

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

        // 若指定了初始命令，等 100ms 让 PTY 初始化后写入
        if let command, !command.isEmpty {
            try? await Task.sleep(nanoseconds: 100_000_000)
            await MainActor.run {
                if let tc = Self.tcContaining(paneId: newPaneId) {
                    tc.writeToSurface(text: command + "\n", surfaceId: newPaneId)
                }
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

        // 无注释时省略 annotation 字段（规范：不返回 null 值字段）
        var obj: [String: Any] = [:]
        if let annotation { obj["annotation"] = annotation }
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let str = String(data: data, encoding: .utf8) else {
            throw RPCError(code: -32603, message: "get_pane_annotation: serialization failed")
        }
        return str
    }

    private static let screenshotDir: String = {
        let dir = NSTemporaryDirectory() + "poltertty/screenshots"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - list_worktrees

    private func callListWorktrees(arguments: [String: Any]) async throws -> String {
        let directory: String = await MainActor.run {
            if let d = arguments["directory"] as? String, !d.isEmpty { return d }
            let kw = NSApp.keyWindow as? TerminalWindow
            if let wsId = kw.flatMap({ WorkspaceManager.shared.workspaceId(for: $0) }),
               let ws = WorkspaceManager.shared.workspace(for: wsId) {
                return ws.rootDirExpanded
            }
            if let firstId = WorkspaceManager.shared.allWorkspaceIds().first,
               let ws = WorkspaceManager.shared.workspace(for: firstId) {
                return ws.rootDirExpanded
            }
            return ""
        }
        guard !directory.isEmpty else {
            throw RPCError(code: -32602, message: "list_worktrees: no directory specified and no active workspace")
        }

        let result = CtrlShellRunner.git(["-C", directory, "worktree", "list", "--porcelain"])
        guard result.succeeded else {
            throw RPCError(code: -32603, message: "list_worktrees: \(result.trimmedStderr)")
        }

        let worktrees = GitWorktreeParser.parse(porcelain: result.stdout, currentPath: directory)
        let arr: [[String: Any]] = worktrees.map { wt in
            var d: [String: Any] = [
                "path": wt.path,
                "isMain": wt.isMain,
                "isCurrent": wt.isCurrent,
                "exists": wt.exists
            ]
            if let branch = wt.branch { d["branch"] = branch }
            return d
        }
        guard let data = try? JSONSerialization.data(withJSONObject: arr),
              let str = String(data: data, encoding: .utf8) else {
            throw RPCError(code: -32603, message: "list_worktrees: serialization failed")
        }
        return str
    }

    // MARK: - create_worktree

    private func callCreateWorktree(arguments: [String: Any]) async throws -> String {
        guard let directory = arguments["directory"] as? String, !directory.isEmpty else {
            throw RPCError(code: -32602, message: "create_worktree: missing required parameter 'directory'")
        }
        guard let path = arguments["path"] as? String, !path.isEmpty else {
            throw RPCError(code: -32602, message: "create_worktree: missing required parameter 'path'")
        }

        let branch = arguments["branch"] as? String
        let baseBranch = arguments["baseBranch"] as? String

        // 将相对路径解析为绝对路径
        let resolvedPath = path.hasPrefix("/")
            ? path
            : URL(fileURLWithPath: directory).appendingPathComponent(path).path

        // 构建 git worktree add 参数
        var args = ["-C", directory, "worktree", "add"]
        if let branch { args += ["-b", branch] }
        args.append(resolvedPath)
        if let baseBranch { args.append(baseBranch) }

        let result = CtrlShellRunner.git(args)
        guard result.succeeded else {
            throw RPCError(code: -32603, message: "create_worktree: \(result.trimmedStderr)")
        }

        // 读取新 worktree 当前分支
        let branchResult = CtrlShellRunner.git(["-C", resolvedPath, "branch", "--show-current"])
        let currentBranch = branchResult.succeeded ? branchResult.trimmedStdout : branch

        var obj: [String: Any] = ["path": resolvedPath]
        if let b = currentBranch, !b.isEmpty { obj["branch"] = b }
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let str = String(data: data, encoding: .utf8) else {
            throw RPCError(code: -32603, message: "create_worktree: serialization failed")
        }
        return str
    }

    // MARK: - open_worktree_in_split

    private func callOpenWorktreeInSplit(arguments: [String: Any]) async throws -> String {
        guard let worktreePath = arguments["worktreePath"] as? String, !worktreePath.isEmpty else {
            throw RPCError(code: -32602, message: "open_worktree_in_split: missing required parameter 'worktreePath'")
        }
        guard let dirStr = arguments["direction"] as? String,
              let direction = Self.parseDirection(dirStr) else {
            throw RPCError(code: -32602, message: "open_worktree_in_split: missing or invalid direction (left|right|up|down)")
        }

        let newPaneId: UUID = try await withCheckedThrowingContinuation { cont in
            Task { @MainActor in
                let tc: TerminalController?
                let surface: Ghostty.SurfaceView?

                if let paneIdStr = arguments["paneId"] as? String,
                   let paneId = UUID(uuidString: paneIdStr) {
                    tc = Self.tcContaining(paneId: paneId)
                    guard let foundTC = tc else {
                        cont.resume(throwing: RPCError(code: -32603, message: "open_worktree_in_split: pane not found"))
                        return
                    }
                    foundTC.switchToTab(containing: paneId)
                    surface = foundTC.findSurface(id: paneId)
                } else {
                    let window = (NSApp.keyWindow as? TerminalWindow)
                        ?? NSApp.windows.first(where: { $0 is TerminalWindow }) as? TerminalWindow
                    tc = window?.terminalController
                    surface = tc?.focusedSurface
                }

                guard let resolvedTC = tc, let resolvedSurface = surface else {
                    cont.resume(throwing: RPCError(code: -32603, message: "open_worktree_in_split: no surface available"))
                    return
                }

                var config = Ghostty.SurfaceConfiguration()
                config.workingDirectory = worktreePath

                guard let newView = resolvedTC.newSplit(at: resolvedSurface, direction: direction, baseConfig: config) else {
                    cont.resume(throwing: RPCError(code: -32603, message: "open_worktree_in_split: split failed"))
                    return
                }
                cont.resume(returning: newView.id)
            }
        }
        return #"{"newPaneId":"\#(newPaneId.uuidString)"}"#
    }

    // MARK: - get_git_status

    private func callGetGitStatus(arguments: [String: Any]) async throws -> String {
        let directory: String = await MainActor.run {
            if let d = arguments["directory"] as? String, !d.isEmpty { return d }
            let kw = NSApp.keyWindow as? TerminalWindow
            if let wsId = kw.flatMap({ WorkspaceManager.shared.workspaceId(for: $0) }),
               let ws = WorkspaceManager.shared.workspace(for: wsId) {
                return ws.rootDirExpanded
            }
            if let firstId = WorkspaceManager.shared.allWorkspaceIds().first,
               let ws = WorkspaceManager.shared.workspace(for: firstId) {
                return ws.rootDirExpanded
            }
            return ""
        }
        guard !directory.isEmpty else {
            throw RPCError(code: -32602, message: "get_git_status: no directory specified and no active workspace")
        }

        // 检测是否为 git 仓库
        let revParse = CtrlShellRunner.git(["-C", directory, "rev-parse", "--git-dir"])
        guard revParse.succeeded else {
            guard let data = try? JSONSerialization.data(withJSONObject: ["isGitRepo": false]),
                  let str = String(data: data, encoding: .utf8) else {
                throw RPCError(code: -32603, message: "get_git_status: serialization failed")
            }
            return str
        }

        // 当前分支
        let branchResult = CtrlShellRunner.git(["-C", directory, "branch", "--show-current"])
        let branch = branchResult.succeeded ? branchResult.trimmedStdout : nil

        // 文件状态（--porcelain v1: "XY filename"）
        let statusResult = CtrlShellRunner.git(["-C", directory, "status", "--porcelain"])
        var staged: [String] = []
        var unstaged: [String] = []
        var untracked: [String] = []

        if statusResult.succeeded {
            for line in statusResult.stdout.components(separatedBy: "\n") {
                guard line.count >= 3 else { continue }
                let x = String(line.prefix(1))
                let y = String(line.dropFirst(1).prefix(1))
                let file = String(line.dropFirst(3))
                if x == "?" && y == "?" {
                    untracked.append(file)
                } else {
                    if x != " " && x != "?" { staged.append(file) }
                    if y != " " && y != "?" { unstaged.append(file) }
                }
            }
        }

        var obj: [String: Any] = [
            "isGitRepo": true,
            "staged": staged,
            "unstaged": unstaged,
            "untracked": untracked
        ]
        if let branch, !branch.isEmpty { obj["branch"] = branch }

        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let str = String(data: data, encoding: .utf8) else {
            throw RPCError(code: -32603, message: "get_git_status: serialization failed")
        }
        return str
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
                    let ws = WorkspaceManager.shared.workspace(for: id)
                    gitState = "{\"panelVisible\":\(ws?.panelVisible ?? false)}"
                } else if let firstId = allIds.first {
                    let ws = WorkspaceManager.shared.workspace(for: firstId)
                    gitState = "{\"panelVisible\":\(ws?.panelVisible ?? false),\"fromAllIds\":true}"
                }
                cont.resume(returning: "{\"wsId\":\"\(wsIdStr)\",\"allIds\":\"\(allIdsStr)\",\"isTermWin\":\(isTerminal),\"winCount\":\(windowCount),\"termWinCount\":\(termWindowCount),\"state\":\(gitState)}")
            }
        }
    }

    // MARK: - test_fullscreen_diff

    /// 已废弃：Git 面板已迁移到 yazi，此方法保留接口兼容性。
    private func callTestFullscreenDiff(arguments: [String: Any]) async throws -> String {
        throw RPCError(code: -32603, message: "test_fullscreen_diff: git panel has been replaced by yazi")
    }

    // MARK: - send_key

    /// 向指定 pane 发送键盘事件（通过 NSEvent，走完整键处理管线）。
    /// 支持的 key 名称：enter/return, escape, tab, backspace, up, down, left, right,
    ///   ctrl+c, ctrl+u, ctrl+d 等 "ctrl+<char>" 组合。
    private func callSendKey(arguments: [String: Any]) async throws -> String {
        guard let keyName = arguments["key"] as? String else {
            throw RPCError(code: -32602, message: "send_key: missing required parameter 'key'")
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                // 确定目标 surface view
                let targetView: NSView?
                if let paneIdStr = arguments["paneId"] as? String,
                   let paneId = UUID(uuidString: paneIdStr),
                   let tc = Self.tcContaining(paneId: paneId) {
                    tc.switchToTab(containing: paneId)
                    targetView = tc.findSurface(id: paneId)
                } else {
                    let window = (NSApp.keyWindow as? TerminalWindow)
                        ?? NSApp.windows.first(where: { $0 is TerminalWindow }) as? TerminalWindow
                    targetView = window?.terminalController?.focusedSurface
                }
                guard let view = targetView else {
                    cont.resume(throwing: RPCError(code: -32603, message: "send_key: target view not found"))
                    return
                }

                // 解析 key 名称
                let (keyCode, chars, mods) = Self.parseKeyName(keyName)
                guard keyCode >= 0 else {
                    cont.resume(throwing: RPCError(code: -32602, message: "send_key: unknown key '\(keyName)'"))
                    return
                }

                let makeEvent: (NSEvent.EventType) -> NSEvent? = { type in
                    NSEvent.keyEvent(
                        with: type,
                        location: NSPoint(x: 0, y: 0),
                        modifierFlags: mods,
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: view.window?.windowNumber ?? 0,
                        context: nil,
                        characters: chars,
                        charactersIgnoringModifiers: chars,
                        isARepeat: false,
                        keyCode: UInt16(keyCode)
                    )
                }
                if let down = makeEvent(.keyDown) { view.keyDown(with: down) }
                if let up   = makeEvent(.keyUp)   { view.keyUp(with: up) }
                cont.resume()
            }
        }
        return #"{"ok":true,"key":"\#(keyName)"}"#
    }

    private static func parseKeyName(_ name: String) -> (keyCode: Int, chars: String, mods: NSEvent.ModifierFlags) {
        let lower = name.lowercased()

        // ctrl+<char> 组合
        if lower.hasPrefix("ctrl+"), lower.count == 6 {
            let ch = lower.last!
            let asciiCtrl = Int(ch.asciiValue ?? 0) - Int(Character("a").asciiValue ?? 0) + 1
            let ctrlStr = String(UnicodeScalar(asciiCtrl)!)
            // key code for the letter
            let letterCode = Self.letterKeyCode(ch)
            return (letterCode, ctrlStr, [.control])
        }

        switch lower {
        case "enter", "return":   return (36, "\r", [])
        case "escape", "esc":     return (53, "\u{1B}", [])
        case "tab":               return (48, "\t", [])
        case "backspace", "delete": return (51, "\u{7F}", [])
        case "up":                return (126, "\u{1B}[A", [])
        case "down":              return (125, "\u{1B}[B", [])
        case "left":              return (123, "\u{1B}[D", [])
        case "right":             return (124, "\u{1B}[C", [])
        default:                  return (-1, "", [])
        }
    }

    private static func letterKeyCode(_ ch: Character) -> Int {
        // macOS key codes for letters a-z
        let map: [Character: Int] = [
            "a":0,"b":11,"c":8,"d":2,"e":14,"f":3,"g":5,"h":4,"i":34,"j":38,
            "k":40,"l":37,"m":46,"n":45,"o":31,"p":35,"q":12,"r":15,"s":1,
            "t":17,"u":32,"v":9,"w":13,"x":7,"y":16,"z":6
        ]
        return map[ch] ?? -1
    }

    // MARK: - open_workspace

    /// 打开指定目录为新 Workspace 窗口，返回 workspaceId 和第一个 paneId。
    private func callOpenWorkspace(arguments: [String: Any]) async throws -> String {
        guard let directory = arguments["directory"] as? String, !directory.isEmpty else {
            throw RPCError(code: -32602, message: "open_workspace: missing required parameter 'directory'")
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDir), isDir.boolValue else {
            throw RPCError(code: -32602, message: "open_workspace: directory does not exist: \(directory)")
        }
        let name = (arguments["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? URL(fileURLWithPath: directory).lastPathComponent

        let result: (UUID, UUID) = try await withCheckedThrowingContinuation { cont in
            Task { @MainActor in
                guard let appDelegate = NSApp.delegate as? AppDelegate else {
                    cont.resume(throwing: RPCError(code: -32603, message: "open_workspace: cannot access AppDelegate"))
                    return
                }
                let workspace = WorkspaceManager.shared.create(name: name, rootDir: directory)
                var config = Ghostty.SurfaceConfiguration()
                config.workingDirectory = workspace.rootDirExpanded
                let controller = TerminalController(
                    appDelegate.ghostty, withBaseConfig: config, workspaceId: workspace.id
                )
                controller.showWindow(nil)
                if let window = controller.window {
                    WorkspaceManager.shared.registerWindow(window, for: workspace.id)
                }
                let panes = controller.listPanes()
                guard let firstPane = panes.first else {
                    cont.resume(throwing: RPCError(code: -32603, message: "open_workspace: no pane created"))
                    return
                }
                cont.resume(returning: (workspace.id, firstPane.id))
            }
        }
        return #"{"workspaceId":"\#(result.0.uuidString)","paneId":"\#(result.1.uuidString)"}"#
    }

    // MARK: - show_agent_dashboard

    /// 打开 Agent Dashboard 浮动窗口。
    private func callShowAgentDashboard() async throws -> String {
        await MainActor.run {
            AgentDashboardWindowController.shared.showWindow(nil)
            AgentDashboardWindowController.shared.window?.makeKeyAndOrderFront(nil)
        }
        return #"{"ok":true}"#
    }

    // MARK: - show_file_browser

    /// 打开 yazi 文件管理面板。
    private func callShowFileBrowser(arguments: [String: Any]) async throws -> String {
        await MainActor.run {
            NotificationCenter.default.post(name: .toggleFileBrowser, object: nil)
        }
        return #"{"ok":true}"#
    }

    // MARK: - show_git_panel

    /// Git 面板已迁移到 yazi，此方法转发到 show_file_browser。
    private func callShowGitPanel(arguments: [String: Any]) async throws -> String {
        return try await callShowFileBrowser(arguments: arguments)
    }

    // MARK: - show_agent_monitor

    /// 打开 Agent Monitor 侧边抽屉。
    private func callShowAgentMonitor(arguments: [String: Any]) async throws -> String {
        await MainActor.run {
            NotificationCenter.default.post(name: .init("poltertty.toggleAgentMonitor"), object: nil)
        }
        return #"{"ok":true}"#
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

    // MARK: - Browser Tab API

    /// browser_new_tab — 在指定（或 active）workspace 的 Browser Panel 新建 tab。
    /// 参数: workspaceId (optional), url (optional)
    /// 返回: { "tabId": "uuid" }
    private func callBrowserNewTab(arguments: [String: Any]) async throws -> String {
        let tabId: UUID = try await withCheckedThrowingContinuation { cont in
            Task { @MainActor in
                guard let store = WorkspaceManager.shared.browserSurfaceStore else {
                    cont.resume(throwing: RPCError(code: -32603, message: "browser_new_tab: browserStore not available"))
                    return
                }
                let wsId = Self.resolveBrowserWorkspaceId(arguments)
                let mgr = store.manager(for: wsId)
                let url = (arguments["url"] as? String).flatMap { URL(string: $0) }
                let id = mgr.newTab(url: url)
                cont.resume(returning: id)
            }
        }
        return #"{"tabId":"\#(tabId.uuidString)"}"#
    }

    /// browser_close_tab — 关闭指定 tab。
    /// 参数: tabId (required), workspaceId (optional)
    private func callBrowserCloseTab(arguments: [String: Any]) async throws -> String {
        guard let tabIdStr = arguments["tabId"] as? String,
              let tabId = UUID(uuidString: tabIdStr) else {
            throw RPCError(code: -32602, message: "browser_close_tab: missing or invalid tabId")
        }
        await MainActor.run {
            guard let store = WorkspaceManager.shared.browserSurfaceStore else { return }
            let wsId = Self.resolveBrowserWorkspaceId(arguments)
            store.manager(for: wsId).closeTab(id: tabId)
        }
        return #"{"ok":true}"#
    }

    /// browser_focus_tab — 将指定 tab 设为 active。
    /// 参数: tabId (required), workspaceId (optional)
    private func callBrowserFocusTab(arguments: [String: Any]) async throws -> String {
        guard let tabIdStr = arguments["tabId"] as? String,
              let tabId = UUID(uuidString: tabIdStr) else {
            throw RPCError(code: -32602, message: "browser_focus_tab: missing or invalid tabId")
        }
        await MainActor.run {
            guard let store = WorkspaceManager.shared.browserSurfaceStore else { return }
            let wsId = Self.resolveBrowserWorkspaceId(arguments)
            store.manager(for: wsId).focusTab(id: tabId)
        }
        return #"{"ok":true}"#
    }

    /// browser_list_tabs — 列出指定 workspace 的所有 browser tab。
    /// 参数: workspaceId (optional)
    /// 返回: [{ tabId, title, url, active }]
    private func callBrowserListTabs(arguments: [String: Any]) async throws -> String {
        let result: String = try await withCheckedThrowingContinuation { cont in
            Task { @MainActor in
                guard let store = WorkspaceManager.shared.browserSurfaceStore else {
                    cont.resume(throwing: RPCError(code: -32603, message: "browser_list_tabs: browserStore not available"))
                    return
                }
                let wsId = Self.resolveBrowserWorkspaceId(arguments)
                let mgr = store.manager(for: wsId)
                let arr: [[String: Any]] = mgr.tabs.map { tab in
                    var d: [String: Any] = [
                        "tabId":  tab.id.uuidString,
                        "title":  tab.title,
                        "active": tab.id == mgr.activeTabId
                    ]
                    if let url = tab.url { d["url"] = url.absoluteString }
                    return d
                }
                guard let data = try? JSONSerialization.data(withJSONObject: arr),
                      let str = String(data: data, encoding: .utf8) else {
                    cont.resume(throwing: RPCError(code: -32603, message: "browser_list_tabs: serialization failed"))
                    return
                }
                cont.resume(returning: str)
            }
        }
        return result
    }

    // MARK: - Browser Agent API

    // MARK: - Browser Snapshot JS

    private static let snapshotJS = """
    (function() {
      var selectors = [
        'a[href]', 'button', 'input', 'select', 'textarea',
        '[role="button"]', '[role="link"]', '[role="combobox"]',
        '[role="textbox"]', '[role="checkbox"]', '[role="radio"]',
        '[contenteditable="true"]'
      ];
      var seen = new Set();
      var elements = [];
      selectors.forEach(function(sel) {
        document.querySelectorAll(sel).forEach(function(el) {
          if (seen.has(el)) return;
          var r = el.getBoundingClientRect();
          if (r.width === 0 && r.height === 0 && el.tagName !== 'INPUT') return;
          seen.add(el);
          elements.push(el);
        });
      });
      window.__polterttyRefs = {};
      var result = elements.map(function(el, i) {
        var ref = 'e' + (i + 1);
        window.__polterttyRefs[ref] = el;
        var info = { ref: ref, tag: el.tagName.toLowerCase() };
        if (el.type) info.type = el.type;
        var text = (el.innerText || el.textContent || '').trim().slice(0, 80);
        if (text) info.text = text;
        if (el.placeholder) info.placeholder = el.placeholder;
        var role = el.getAttribute('role');
        if (role) info.role = role;
        if (el.name) info.name = el.name;
        if (el.id) info.id = el.id;
        if (el.href) info.href = el.href;
        if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT') {
          info.value = el.value;
        }
        return info;
      });
      return JSON.stringify({
        elements: result,
        url: window.location.href,
        title: document.title
      });
    })();
    """

    /// 生成通过 ref 或 selector 查找元素的 JS 前缀代码（IIFE 头部）
    private static func elementLookupJS(ref: String?, selector: String?) -> String {
        if let ref {
            let safeRef = ref.replacingOccurrences(of: "\"", with: "\\\"")
            return """
            (function() {
              var el = window.__polterttyRefs && window.__polterttyRefs["\(safeRef)"];
              if (!el) return JSON.stringify({error: "ref \(safeRef) not found, re-run browser_snapshot"});
            """
        } else if let selector {
            let safe = selector
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return """
            (function() {
              var el = document.querySelector("\(safe)");
              if (!el) return JSON.stringify({error: "selector not found: \(safe)"});
            """
        } else {
            return "(function() { return JSON.stringify({error: 'ref or selector required'}); })();"
        }
    }

    /// browser_navigate — 导航到 URL。
    /// 参数: url (required), tabId (optional), workspaceId (optional)
    private func callBrowserNavigate(arguments: [String: Any]) async throws -> String {
        guard let urlStr = arguments["url"] as? String,
              let url = URL(string: urlStr) else {
            throw RPCError(code: -32602, message: "browser_navigate: missing or invalid url")
        }
        let _: Void = try await withCheckedThrowingContinuation { cont in
            Task { @MainActor in
                guard let store = WorkspaceManager.shared.browserSurfaceStore else {
                    cont.resume(throwing: RPCError(code: -32603, message: "browser_navigate: browserStore not available"))
                    return
                }
                let wsId = Self.resolveBrowserWorkspaceId(arguments)
                guard let webView = Self.resolveBrowserTab(arguments, store: store, wsId: wsId) else {
                    cont.resume(throwing: RPCError(code: -32603, message: "browser_navigate: no active tab"))
                    return
                }
                webView.load(URLRequest(url: url))
                cont.resume(returning: ())
            }
        }
        return #"{"ok":true}"#
    }

    /// browser_snapshot — 获取页面可交互元素快照，返回带编号引用的 JSON。
    /// 参数: tabId (optional), workspaceId (optional)
    private func callBrowserSnapshot(arguments: [String: Any]) async throws -> String {
        let result: String = try await withCheckedThrowingContinuation { cont in
            Task { @MainActor in
                guard let store = WorkspaceManager.shared.browserSurfaceStore else {
                    cont.resume(throwing: RPCError(code: -32603, message: "browser_snapshot: browserStore not available"))
                    return
                }
                let wsId = Self.resolveBrowserWorkspaceId(arguments)
                guard let webView = Self.resolveBrowserTab(arguments, store: store, wsId: wsId) else {
                    cont.resume(throwing: RPCError(code: -32603, message: "browser_snapshot: no active tab"))
                    return
                }
                webView.evaluateJavaScript(Self.snapshotJS) { value, error in
                    if let error {
                        cont.resume(throwing: RPCError(code: -32603, message: "browser_snapshot: js error: \(error.localizedDescription)"))
                        return
                    }
                    guard let json = value as? String else {
                        cont.resume(throwing: RPCError(code: -32603, message: "browser_snapshot: unexpected js return type"))
                        return
                    }
                    cont.resume(returning: json)
                }
            }
        }
        return result
    }

    /// browser_click — 点击元素。
    /// 参数: ref 或 selector (至少一个), tabId (optional), workspaceId (optional)
    private func callBrowserClick(arguments: [String: Any]) async throws -> String {
        let ref = arguments["ref"] as? String
        let selector = arguments["selector"] as? String
        guard ref != nil || selector != nil else {
            throw RPCError(code: -32602, message: "browser_click: ref or selector required")
        }
        let prefix = Self.elementLookupJS(ref: ref, selector: selector)
        let js = prefix + "\n  el.click();\n  return JSON.stringify({ok: true});\n})();"
        let result: String = try await withCheckedThrowingContinuation { cont in
            Task { @MainActor in
                guard let store = WorkspaceManager.shared.browserSurfaceStore else {
                    cont.resume(throwing: RPCError(code: -32603, message: "browser_click: browserStore not available"))
                    return
                }
                let wsId = Self.resolveBrowserWorkspaceId(arguments)
                guard let webView = Self.resolveBrowserTab(arguments, store: store, wsId: wsId) else {
                    cont.resume(throwing: RPCError(code: -32603, message: "browser_click: no active tab"))
                    return
                }
                webView.evaluateJavaScript(js) { value, error in
                    if let error {
                        cont.resume(throwing: RPCError(code: -32603, message: "browser_click: js error: \(error.localizedDescription)"))
                        return
                    }
                    guard let json = value as? String else {
                        cont.resume(throwing: RPCError(code: -32603, message: "browser_click: unexpected js return type"))
                        return
                    }
                    if json.contains("\"error\"") {
                        cont.resume(throwing: RPCError(code: -32603, message: "browser_click: \(json)"))
                        return
                    }
                    cont.resume(returning: json)
                }
            }
        }
        return result
    }

    /// browser_fill — 填充输入框。兼容 React 的 native input setter + 事件触发。
    /// 参数: ref 或 selector (至少一个), value (required), tabId (optional), workspaceId (optional)
    private func callBrowserFill(arguments: [String: Any]) async throws -> String {
        let ref = arguments["ref"] as? String
        let selector = arguments["selector"] as? String
        guard ref != nil || selector != nil else {
            throw RPCError(code: -32602, message: "browser_fill: ref or selector required")
        }
        guard let value = arguments["value"] as? String else {
            throw RPCError(code: -32602, message: "browser_fill: missing value")
        }
        let safeValue = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        let prefix = Self.elementLookupJS(ref: ref, selector: selector)
        let js = prefix + """
        \n  var proto = el.tagName === 'TEXTAREA'
            ? window.HTMLTextAreaElement.prototype
            : window.HTMLInputElement.prototype;
          var desc = Object.getOwnPropertyDescriptor(proto, 'value');
          if (desc && desc.set) {
            desc.set.call(el, "\(safeValue)");
          } else {
            el.value = "\(safeValue)";
          }
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
          return JSON.stringify({ok: true});
        })();
        """
        let result: String = try await withCheckedThrowingContinuation { cont in
            Task { @MainActor in
                guard let store = WorkspaceManager.shared.browserSurfaceStore else {
                    cont.resume(throwing: RPCError(code: -32603, message: "browser_fill: browserStore not available"))
                    return
                }
                let wsId = Self.resolveBrowserWorkspaceId(arguments)
                guard let webView = Self.resolveBrowserTab(arguments, store: store, wsId: wsId) else {
                    cont.resume(throwing: RPCError(code: -32603, message: "browser_fill: no active tab"))
                    return
                }
                webView.evaluateJavaScript(js) { value, error in
                    if let error {
                        cont.resume(throwing: RPCError(code: -32603, message: "browser_fill: js error: \(error.localizedDescription)"))
                        return
                    }
                    guard let json = value as? String else {
                        cont.resume(throwing: RPCError(code: -32603, message: "browser_fill: unexpected js return type"))
                        return
                    }
                    if json.contains("\"error\"") {
                        cont.resume(throwing: RPCError(code: -32603, message: "browser_fill: \(json)"))
                        return
                    }
                    cont.resume(returning: json)
                }
            }
        }
        return result
    }

    /// 解析 tabId 参数，找到对应 WKWebView。
    /// - 传入有效 tabId：使用指定 tab
    /// - 未传入或无效：使用 active tab
    @MainActor
    private static func resolveBrowserTab(
        _ arguments: [String: Any],
        store: BrowserSurfaceStore,
        wsId: UUID
    ) -> WKWebView? {
        let mgr = store.manager(for: wsId)
        if let tabIdStr = arguments["tabId"] as? String,
           let tabId = UUID(uuidString: tabIdStr) {
            return mgr.tabs.first(where: { $0.id == tabId })?.webView
        }
        return mgr.activeTab?.webView
    }

    /// workspaceId 参数存在时直接使用，否则返回 active workspace ID。
    @MainActor
    private static func resolveBrowserWorkspaceId(_ arguments: [String: Any]) -> UUID {
        if let str = arguments["workspaceId"] as? String, let id = UUID(uuidString: str) {
            return id
        }
        return WorkspaceManager.shared.activeWorkspaceId() ?? UUID()
    }

    // MARK: - notify

    private func callNotify(arguments: [String: Any]) async throws -> String {
        guard let title = arguments["title"] as? String, !title.isEmpty else {
            throw RPCError(code: -32602, message: "notify: missing required parameter 'title'")
        }
        let body = arguments["body"] as? String

        let workspaceId: UUID? = await MainActor.run {
            if let wsIdStr = arguments["workspaceId"] as? String,
               let wsId = UUID(uuidString: wsIdStr) {
                return wsId
            }
            return WorkspaceManager.shared.activeWorkspaceId()
        }

        await MainActor.run {
            AgentNotificationStore.shared.insert(AgentNotification(
                id: UUID(),
                timestamp: Date(),
                workspaceId: workspaceId,
                surfaceId: nil,
                agentDefinitionId: "ctrl-api",
                sessionId: nil,
                type: .info,
                title: title,
                body: body,
                priority: .normal
            ))
        }
        return #"{"ok":true}"#
    }

    // MARK: - Stubs (will be replaced in Task 7/8/9)

    // MARK: - open_in_file_browser

    private func callOpenInFileBrowser(arguments: [String: Any]) async throws -> String {
        guard let rawPath = arguments["path"] as? String, !rawPath.isEmpty else {
            throw RPCError(code: -32602, message: "open_in_file_browser: missing required parameter 'path'")
        }
        let path = (rawPath as NSString).expandingTildeInPath

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                let workspaceId: UUID
                if let wsIdStr = arguments["workspaceId"] as? String,
                   let wsId = UUID(uuidString: wsIdStr) {
                    workspaceId = wsId
                } else if let active = WorkspaceManager.shared.activeWorkspaceId() {
                    workspaceId = active
                } else {
                    cont.resume(throwing: RPCError(code: -32603, message: "open_in_file_browser: no active workspace"))
                    return
                }

                // 若文件浏览器未打开，先打开它
                let yaziStore = WorkspaceManager.shared.yaziSurfaceStore
                if yaziStore?.hasSurface(for: workspaceId) == false {
                    NotificationCenter.default.post(name: .toggleFileBrowser, object: nil)
                }

                // 等一个 RunLoop tick，给 yazi surface 初始化时间
                DispatchQueue.main.async {
                    WorkspaceManager.shared.yaziSurfaceStore?.cdToDirectory(workspaceId, path: path)
                    cont.resume()
                }
            }
        }
        return #"{"ok":true}"#
    }
    // MARK: - set_agent_label

    private func callSetAgentLabel(arguments: [String: Any]) async throws -> String {
        guard let sessionId = arguments["sessionId"] as? String, !sessionId.isEmpty else {
            throw RPCError(code: -32602, message: "set_agent_label: missing required parameter 'sessionId'")
        }
        guard let label = arguments["label"] as? String else {
            throw RPCError(code: -32602, message: "set_agent_label: missing required parameter 'label'")
        }

        // 可选 state 参数校验
        let newState: AgentState?
        if let stateStr = arguments["state"] as? String {
            switch stateStr {
            case "working": newState = .working
            case "idle":    newState = .idle
            case "done":    newState = .done(exitCode: 0)
            default:
                throw RPCError(code: -32602, message: "set_agent_label: invalid state '\(stateStr)', allowed: working | idle | done")
            }
        } else {
            newState = nil
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                let agentManager = AgentService.shared.sessionManager
                guard agentManager.session(forClaudeSessionId: sessionId) != nil else {
                    cont.resume(throwing: RPCError(code: -32603, message: "set_agent_label: session not found for sessionId '\(sessionId)'"))
                    return
                }
                agentManager.updateFromClaudeSession(sessionId) { session in
                    session.customLabel = label
                    if let state = newState { session.state = state }
                }
                // 取出更新后的 surfaceId，emit SSE
                if let surfaceId = agentManager.sessions.first(where: { $0.value.claudeSessionId == sessionId })?.key {
                    agentManager.emitAgentStatus(surfaceId: surfaceId)
                }
                cont.resume()
            }
        }
        return #"{"ok":true}"#
    }
    private func callGetWorkspaceState(arguments: [String: Any]) async throws -> String { return #"{"ok":true}"# }
}
