// macos/Sources/Features/Agent/Launcher/AgentIconViews.swift
import SwiftUI
import AppKit

// MARK: - 公共入口

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

// MARK: - Claude Code（从 Claude.app 提取真实图标）

private struct ClaudeIcon: View {
    let size: CGFloat

    private static let appIcon: NSImage? = {
        let candidates = [
            "/Applications/Claude.app",
            (("~/Applications/Claude.app") as NSString).expandingTildeInPath,
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return nil
    }()

    var body: some View {
        if let icon = Self.appIcon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.214))
        } else {
            // 未安装 Claude.app 时的降级方案
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.214)
                    .fill(Color(hex: "#CC785C") ?? .orange)
                    .frame(width: size, height: size)
                Text("◆")
                    .font(.system(size: size * 0.464, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Gemini CLI（品牌四角星）

private struct GeminiIcon: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.214)
                .fill(Color.black)
                .frame(width: size, height: size)
            GeminiStarShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.26, green: 0.52, blue: 0.96),  // #4285F4 蓝
                            Color(red: 0.55, green: 0.36, blue: 0.96),  // #8C5CF6 紫
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.679, height: size * 0.679)
        }
    }
}

/// Gemini 标志性四角星：腰部极细、顶点尖锐，模拟品牌形状。
private struct GeminiStarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX, cy = rect.midY
        let r = min(rect.width, rect.height) / 2
        let narrow = r * 0.08   // 腰部半宽

        var path = Path()
        let top    = CGPoint(x: cx,          y: cy - r)
        let right  = CGPoint(x: cx + r,      y: cy)
        let bottom = CGPoint(x: cx,          y: cy + r)
        let left   = CGPoint(x: cx - r,      y: cy)
        let trIn   = CGPoint(x: cx + narrow, y: cy - narrow)
        let brIn   = CGPoint(x: cx + narrow, y: cy + narrow)
        let blIn   = CGPoint(x: cx - narrow, y: cy + narrow)
        let tlIn   = CGPoint(x: cx - narrow, y: cy - narrow)

        path.move(to: top)
        path.addLine(to: trIn)
        path.addLine(to: right)
        path.addLine(to: brIn)
        path.addLine(to: bottom)
        path.addLine(to: blIn)
        path.addLine(to: left)
        path.addLine(to: tlIn)
        path.closeSubpath()
        return path
    }
}

// MARK: - OpenCode（代码括号）

private struct OpenCodeIcon: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.214)
                .fill(Color(red: 0.09, green: 0.09, blue: 0.11))
                .frame(width: size, height: size)
            Image(systemName: "curlybraces")
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.47, green: 0.84, blue: 0.55),  // 绿
                            Color(red: 0.35, green: 0.72, blue: 0.96),  // 蓝
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
}
