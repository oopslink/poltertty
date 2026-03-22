// macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift
import Foundation
import AppKit
import OSLog

/// MCP tool 实现。
/// prepareResult() 在 background queue 调用，只做纯数据处理，不访问 @MainActor 属性。
/// execute() 标注 @MainActor，执行所有 UI 副作用。
final class CtrlToolHandler {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "CtrlToolHandler"
    )

    // C2: RPCError 声明为 Sendable
    struct RPCError: Sendable {
        let code: Int
        let message: String
    }

    /// port 由 CtrlServer 在初始化时以值拷贝形式传入，
    /// 避免在 background 线程访问 @MainActor 的 AgentService 属性
    private let port: UInt16
    // C1: version 和 instanceId 在 init 时读取并缓存，避免 background 线程访问 Bundle
    private let version: String
    private let instanceId: String

    init(port: UInt16) {
        self.port = port
        self.version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        self.instanceId = Bundle.main.bundleIdentifier ?? "unknown"
    }

    // MARK: - prepareResult（background queue 安全）

    func prepareResult(tool: String, arguments: [String: Any]) -> (String?, RPCError?) {
        switch tool {
        case "ping":    return (pingResult(), nil)
        case "new_tab":
            // C4: new_tab 响应改用 JSONSerialization，保持一致性
            let obj: [String: Any] = ["status": "accepted"]
            let text = (try? JSONSerialization.data(withJSONObject: obj))
                .flatMap { String(data: $0, encoding: .utf8) } ?? #"{"status":"accepted"}"#
            return (text, nil)
        default:        return (nil, RPCError(code: -32601, message: "Unknown tool: \(tool)"))
        }
    }

    // MARK: - execute（@MainActor）

    @MainActor
    func execute(tool: String, arguments: [String: Any]) {
        switch tool {
        case "new_tab": executeNewTab(arguments: arguments)
        default: break
        }
    }

    // MARK: - ping

    private func pingResult() -> String {
        // C1: 使用 init 时缓存的 version 和 instanceId
        let obj: [String: Any] = [
            "instanceId": instanceId,
            "version": version,
            "port": Int(port)
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let str = String(data: data, encoding: .utf8) else {
            Self.logger.error("pingResult: JSON serialization failed")
            return #"{"error":"serialization failed"}"#
        }
        return str
    }

    // MARK: - new_tab

    @MainActor
    private func executeNewTab(arguments: [String: Any]) {
        let tc: TerminalController?

        if let wsIdStr = arguments["workspaceId"] as? String {
            guard let wsId = UUID(uuidString: wsIdStr) else {
                Self.logger.warning("new_tab: invalid workspaceId UUID: \(wsIdStr)")
                return
            }
            let window = WorkspaceManager.shared.windowForWorkspace(wsId)
            tc = (window as? TerminalWindow)?.terminalController
        } else {
            // C3: 修正 keyWindow fallback——即使 keyWindow 非 nil 但不是 TerminalWindow，
            // 也继续遍历找第一个 TerminalWindow
            let target = (NSApp.keyWindow as? TerminalWindow)
                ?? NSApp.windows.first(where: { $0 is TerminalWindow }) as? TerminalWindow
            tc = target?.terminalController
        }

        guard let tc else {
            Self.logger.warning("new_tab: no TerminalController found")
            return
        }

        tc.addNewTab()
        Self.logger.info("new_tab: executed successfully")
    }
}
