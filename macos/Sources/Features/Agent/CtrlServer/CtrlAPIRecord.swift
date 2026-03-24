// macos/Sources/Features/Agent/CtrlServer/CtrlAPIRecord.swift
import Foundation

/// 单次 CtrlServer API 调用的完整记录，供监控面板展示
struct CtrlAPIRecord: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let method: String         // "POST", "GET", "DELETE"
    let path: String           // "/mcp", "/hook", "/hooks/prepare-session", "/health"
    let toolName: String?      // tools/call 时的工具名（ping/new_tab 等），其余为 nil
    let requestBody: String?   // 截断至 4096 字节
    let responseBody: String?  // 截断至 4096 字节
    let statusCode: Int
    let durationMs: Double
    let error: String?         // JSON-RPC error.message，否则为 nil
    let workspaceId: UUID?
    let surfaceId: UUID?
}

/// CtrlServer 内部使用的请求上下文，不可变值类型
struct RequestContext: Sendable {
    let method: String
    let path: String
    let startTime: Date
    let requestBody: Data?
    let toolName: String?
    let workspaceId: UUID?
    let surfaceId: UUID?
}
