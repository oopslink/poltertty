// macos/Sources/Features/Agent/Launcher/AgentIconViews.swift
import SwiftUI
import AppKit

// MARK: - 带背景徽章（Launcher / Picker 等）

/// 根据 agent.id 选择专属图标，未知 agent 降级到通用徽章。
struct AgentIconBadge: View {
    let agent: AgentDefinition
    var size: CGFloat = 28

    var body: some View {
        switch agent.id {
        case "claude-code":  ClaudeIcon(size: size)
        case "gemini-cli":   GeminiIcon(size: size)
        case "opencode":     OpenCodeIcon(size: size)
        default:             genericBadge
        }
    }

    private var genericBadge: some View {
        let color: Color = {
            guard let hex = agent.iconColor, let c = Color(hex: hex) else {
                return Color(.tertiaryLabelColor)
            }
            return c
        }()
        return ZStack {
            RoundedRectangle(cornerRadius: size * 0.214)
                .fill(color)
                .frame(width: size, height: size)
            Text(agent.icon)
                .font(.system(size: size * 0.464, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - 无背景内联图标（Status Bar / Monitor 等紧凑场景）

/// 纯图标，无圆角矩形背景，适合 Status Bar 等紧凑场景。
struct AgentInlineIcon: View {
    let agent: AgentDefinition
    var size: CGFloat = 14

    var body: some View {
        switch agent.id {
        case "claude-code":
            Image("ClaudeLogoIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        case "gemini-cli":
            Image("GeminiLogoIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        case "opencode":
            Image("OpenCodeLogoIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        default:
            let color = agent.iconColor.flatMap { Color(hex: $0) } ?? .secondary
            Text(agent.icon)
                .font(.system(size: size * 0.9))
                .foregroundColor(color)
        }
    }
}

// MARK: - Claude Code

private struct ClaudeIcon: View {
    let size: CGFloat

    var body: some View {
        Image("ClaudeLogoIcon")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

// MARK: - Gemini CLI

private struct GeminiIcon: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.214)
                .fill(Color.black)
                .frame(width: size, height: size)
            Image("GeminiLogoIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: size * 0.72, height: size * 0.72)
        }
    }
}

// MARK: - OpenCode

private struct OpenCodeIcon: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.214)
                .fill(Color(red: 0.09, green: 0.09, blue: 0.11))
                .frame(width: size, height: size)
            Image("OpenCodeLogoIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: size * 0.72, height: size * 0.72)
        }
    }
}
