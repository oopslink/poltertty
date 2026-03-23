// macos/Sources/Features/Agent/CtrlServer/PaneInfo.swift
import Foundation

/// MCP list_panes 工具返回的 pane 信息
struct PaneInfo {
    let id: UUID
    let tabId: UUID
    let workspaceId: UUID
    let isActive: Bool
    let title: String?
}
