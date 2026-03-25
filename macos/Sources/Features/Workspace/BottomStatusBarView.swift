// macos/Sources/Features/Workspace/BottomStatusBarView.swift

import SwiftUI
import AppKit

struct BottomStatusBarView: View {
    @ObservedObject var monitor: GitStatusMonitor
    @EnvironmentObject var tabBarVM: TabBarViewModel
    @ObservedObject private var ctrlAPIStore = CtrlAPIStore.shared
    @EnvironmentObject private var paneSelectorVM: PaneSelectorViewModel
    @State private var showAnnotationPopover: Bool = false
    let pwd: String
    let isFocused: Bool
    let surfaceId: UUID

    private var hasTmuxAttached: Bool {
        tabBarVM.tmuxStates[surfaceId] != nil
    }

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
                // 右：tmux 按钮 | agent 按钮 | ctrl api 按钮 | git 状态
                if !hasTmuxAttached {
                    Button(action: {
                        NotificationCenter.default.post(
                            name: .showTmuxSessionPicker,
                            object: nil,
                            userInfo: ["attachInCurrentPane": true]
                        )
                    }) {
                        Image("TmuxIcon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                    .help("Attach tmux session")
                }
                AgentButtonView(surfaceId: surfaceId)
                Button(action: { showAnnotationPopover = true }) {
                    Image(systemName: "tag")
                        .font(.system(size: 11))
                        .foregroundStyle(
                            paneSelectorVM.annotations[surfaceId] != nil ? Color.accentColor : Color.secondary
                        )
                }
                .buttonStyle(.plain)
                .help("设置 pane 注释")
                .popover(isPresented: $showAnnotationPopover) {
                    AnnotationPopoverView(surfaceId: surfaceId)
                        .environmentObject(paneSelectorVM)
                }
                Button(action: { ctrlAPIStore.isMonitorVisible.toggle() }) {
                    Image(systemName: "network")
                        .font(.system(size: 11))
                        .foregroundStyle(ctrlAPIStore.isMonitorVisible ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Ctrl API Monitor")
                if status.isGitRepo {
                    Text("|")
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundColor(status.isLinkedWorktree ? Color(hex: "#cba6f7") ?? .purple : .secondary)
                        if status.isLinkedWorktree {
                            Text(String(localized: "worktree"))
                                .font(.system(size: 9))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill((Color(hex: "#cba6f7") ?? .purple).opacity(0.15))
                                )
                                .foregroundColor(Color(hex: "#cba6f7") ?? .purple)
                        }
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
