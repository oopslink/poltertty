import SwiftUI

/// 显示在 split pane 右上角的编号 badge，如 "#0"、"#a"。
/// 出现时闪烁 2 次以吸引注意。
struct PaneBadgeView: View {
    /// 单字符标签："0"…"9" 或 "a"…"z"
    let label: String

    @State private var opacity: Double = 1.0

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
            .opacity(opacity)
            .onAppear {
                // 闪烁 2 次：暗 → 亮 → 暗 → 亮
                let duration = 0.12
                withAnimation(.easeInOut(duration: duration)) {
                    opacity = 0.15
                }
                withAnimation(.easeInOut(duration: duration).delay(duration)) {
                    opacity = 1.0
                }
                withAnimation(.easeInOut(duration: duration).delay(duration * 2)) {
                    opacity = 0.15
                }
                withAnimation(.easeInOut(duration: duration).delay(duration * 3)) {
                    opacity = 1.0
                }
            }
    }
}
