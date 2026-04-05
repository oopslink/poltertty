// macos/Sources/Features/Workspace/Browser/BrowserRestoreBanner.swift
import SwiftUI

/// 首次打开 Browser Panel 时，若有上次会话快照，显示此 banner 询问是否恢复。
struct BrowserRestoreBanner: View {
    let tabCount: Int
    let onRestore: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11))
                .foregroundStyle(Color.green.opacity(0.8))

            Text("Restore \(tabCount) tab\(tabCount == 1 ? "" : "s") from last session?")
                .font(.system(size: 11))
                .foregroundStyle(.primary)

            Spacer()

            Button("Restore") {
                onRestore()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Color.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.green.opacity(0.1))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.green.opacity(0.4), lineWidth: 0.5)
            )

            Button("Dismiss") {
                onDismiss()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.05))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Color.green.opacity(0.2)),
            alignment: .bottom
        )
    }
}
