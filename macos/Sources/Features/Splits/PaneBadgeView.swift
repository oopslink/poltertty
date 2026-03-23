import SwiftUI

/// 显示在 split pane 右上角的编号 badge，如 "#0"、"#a"。
struct PaneBadgeView: View {
    /// 单字符标签："0"…"9" 或 "a"…"z"
    let label: String

    var body: some View {
        Text("#\(label)")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
    }
}
