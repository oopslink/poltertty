// macos/Sources/Features/Splits/PaneOverlayCardView.swift

import SwiftUI

/// 概览模式下显示在 pane 中央的浮动信息卡片。
struct PaneOverlayCardView: View {
    let info: PaneSelectorViewModel.PaneOverlayInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            firstLine
            secondLine
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
        .fixedSize()
    }

    // MARK: - 第一行：编号 + 注释

    private var firstLine: some View {
        HStack(spacing: 6) {
            Text("#\(PaneSelectorViewModel.label(for: info.index))")
                .foregroundStyle(Color.accentColor)
                .fontWeight(.bold)
            if let annotation = info.annotation {
                Text(truncatedAnnotation(annotation))
                    .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - 第二行：shell · 进程 · 时长 · pwd (branch)

    private var secondLine: some View {
        Text(secondLineText)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var secondLineText: String {
        var segments: [String] = []
        segments.append(info.shellName)
        if let fg = info.foregroundProcess {
            segments.append(fg)
        }
        if info.duration > 0 {
            segments.append(PaneSelectorViewModel.formatDuration(info.duration))
        }
        segments.append(pwdWithGit)
        return segments.joined(separator: " · ")
    }

    private var pwdWithGit: String {
        let abbreviated = info.pwd.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        if let branch = info.gitBranch {
            let dirty = info.gitDirty ? "*" : ""
            return "\(abbreviated) (\(branch)\(dirty))"
        }
        return abbreviated
    }

    private func truncatedAnnotation(_ text: String) -> String {
        if text.count > 30 {
            return String(text.prefix(30)) + "…"
        }
        return text
    }
}
