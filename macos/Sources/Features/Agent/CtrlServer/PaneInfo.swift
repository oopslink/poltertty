// macos/Sources/Features/Agent/CtrlServer/PaneInfo.swift
import Foundation

/// MCP list_panes 工具返回的 pane 信息
struct PaneInfo {
    let id: UUID
    let tabId: UUID
    let workspaceId: UUID
    let isActive: Bool
    /// Tab 在 tab bar 中的位置（0-based）
    let tabIndex: Int
    /// Pane 在本 tab 的 split tree 中的遍历顺序（0-based，深度优先叶节点顺序）
    let paneIndex: Int
    let title: String?
    let annotation: String?
}
