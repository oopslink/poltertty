// macos/Sources/Features/Agent/Monitor/AgentColors.swift
import SwiftUI

/// Agent Monitor 统一颜色 token。
/// 所有 Agent Monitor 相关视图必须通过此命名空间引用颜色，禁止直接写 hex 字符串。
enum AgentColors {

    // MARK: - Status Colors（状态信号色）

    /// 完成 / 存活 / 成功
    static let success   = Color(hex: "#4caf50") ?? Color.green
    /// 错误 / 失败
    static let error     = Color(hex: "#f44336") ?? Color.red
    /// 运行中 / 工作中（警示橙）
    static let active    = Color(hex: "#ff9800") ?? Color.orange
    /// 启动中（蓝）
    static let launching = Color.accentColor
    /// 空闲（黄）
    static let idle      = Color.yellow

    // MARK: - Text / Icon Colors（链接蓝）

    /// 可点击的 subagent 名称
    static let linkBlue  = Color(hex: "#569cd6") ?? Color.blue
    /// 选中态文字蓝（略浅）
    static let selectedBlue = Color(hex: "#90bfff") ?? Color.blue

    // MARK: - Badge Backgrounds（自适应，亮暗模式均适用）

    /// done 徽章背景
    static let successBadgeBg = Color.green.opacity(0.12)
    /// error 徽章背景
    static let errorBadgeBg   = Color.red.opacity(0.12)
    /// working 徽章背景（橙）
    static let activeBadgeBg  = Color.orange.opacity(0.12)
    /// launching 徽章背景
    static let launchingBadgeBg = Color.accentColor.opacity(0.12)
    /// idle 徽章背景
    static let idleBadgeBg    = Color(.separatorColor).opacity(0.4)

    // MARK: - Selection（自适应选中色）

    /// 列表行选中背景（跟随系统 accentColor，亮暗均适用）
    static let selectionBg       = Color.accentColor.opacity(0.12)
    /// 列表行选中背景（稍深，用于 sessionRow）
    static let selectionBgStrong = Color.accentColor.opacity(0.18)
    /// 选中行左侧指示条
    static let selectionIndicator = Color.accentColor

    // MARK: - Separator / Background

    static let rowStripeBg = Color(.separatorColor).opacity(0.08)
}
