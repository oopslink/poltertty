// macos/Sources/Features/Workspace/BottomStatusBarView.swift

import SwiftUI
import AppKit

struct BottomStatusBarView: View {
    @ObservedObject var monitor: GitStatusMonitor
    let pwd: String
    let isFocused: Bool
    let surfaceId: UUID

    var body: some View {
        let status = monitor.status
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 6) {
                // 左：当前目录路径
                Label(abbreviatedPwd, systemImage: "folder")
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundColor(.secondary)
                Spacer()
                // 右：agent 按钮 | git 状态
                AgentButtonView(surfaceId: surfaceId)
                if status.isGitRepo {
                    Text("|")
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundColor(.secondary)
                        Text(status.branch ?? "detached")
                            .foregroundColor(.primary)
                        if status.added > 0 {
                            Text("+\(status.added)")
                                .foregroundColor(.green)
                        }
                        if status.modified > 0 {
                            Text("~\(status.modified)")
                                .foregroundColor(.yellow)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        }
        .font(.system(size: 11))
        .opacity(isFocused ? 1.0 : 0.45)
    }

    private var abbreviatedPwd: String {
        pwd.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
