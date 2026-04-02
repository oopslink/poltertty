// macos/Sources/Features/Splits/PaneOverlayCardView.swift

import SwiftUI

/// 概览模式下显示在 pane 中央的浮动信息卡片。
struct PaneOverlayCardView: View {
    let info: PaneSelectorViewModel.PaneOverlayInfo

    var body: some View {
        VStack(spacing: 7) {
            if let annotation = info.annotation {
                // annotation 是主角
                Text(annotation.count > 20 ? String(annotation.prefix(20)) + "…" : annotation)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 28, height: 1)

                keyBadge(size: 30, fontSize: 16)
            } else {
                // 无 annotation：key badge 放大顶替主角
                keyBadge(size: 44, fontSize: 22)
            }

            subInfoView
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.7), radius: 24, y: 4)
        .fixedSize()
    }

    // MARK: - Key badge

    private func keyBadge(size: CGFloat, fontSize: CGFloat) -> some View {
        let cornerRadius = size * 0.23
        return Text(PaneSelectorViewModel.label(for: info.index))
            .font(.system(size: fontSize, weight: .black, design: .monospaced))
            .foregroundStyle(Color.accentColor)
            .frame(width: size, height: size)
            .background(
                Color.accentColor.opacity(0.15),
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1.5)
            )
    }

    // MARK: - 辅助信息

    private var subInfoView: some View {
        Text(subInfo)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var subInfo: String {
        var parts: [String] = []
        if let fg = info.foregroundProcess {
            parts.append(fg)
        } else {
            parts.append(info.shellName)
        }
        let pwd = info.pwd.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        parts.append(pwd)
        if info.duration >= 60 {
            parts.append(PaneSelectorViewModel.formatDuration(info.duration))
        }
        return parts.joined(separator: " · ")
    }
}
