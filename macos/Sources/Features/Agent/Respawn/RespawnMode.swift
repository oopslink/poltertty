// macos/Sources/Features/Agent/Respawn/RespawnMode.swift
import Foundation

struct RespawnConfig {
    let idleThresholdSeconds: TimeInterval?  // nil = 不自动 respawn
    let maxRuntimeMinutes: Int?              // nil = 无限制
    let compactThreshold: Float?            // context 使用率触发 /compact
    let clearThreshold: Float?              // compact 后仍超阈值触发 /clear（overnight 专用）
}

extension RespawnMode {
    var config: RespawnConfig {
        switch self {
        case .soloWork:  return RespawnConfig(idleThresholdSeconds: 3,   maxRuntimeMinutes: 60,  compactThreshold: 0.55, clearThreshold: nil)
        case .teamLead:  return RespawnConfig(idleThresholdSeconds: 90,  maxRuntimeMinutes: 480, compactThreshold: 0.55, clearThreshold: nil)
        case .overnight: return RespawnConfig(idleThresholdSeconds: 10,  maxRuntimeMinutes: nil, compactThreshold: 0.55, clearThreshold: 0.70)
        case .manual:    return RespawnConfig(idleThresholdSeconds: nil,  maxRuntimeMinutes: nil, compactThreshold: nil,  clearThreshold: nil)
        }
    }
}
