// macos/Sources/Features/Workspace/BottomStatusBarView.swift

import SwiftUI
import AppKit

struct BottomStatusBarView: View {
    @ObservedObject var gitVM: GitPanelViewModel
    @EnvironmentObject var tabBarVM: TabBarViewModel
    @EnvironmentObject private var paneSelectorVM: PaneSelectorViewModel
    @State private var showAnnotationPopover: Bool = false
    let pwd: String
    let isFocused: Bool
    let surfaceId: UUID

    private var hasTmuxAttached: Bool {
        tabBarVM.tmuxStates[surfaceId] != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 6) {
                // 左：当前目录路径
                Label(abbreviatedPwd, systemImage: "folder")
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundColor(.secondary)
                Spacer()
                // 右：tmux 按钮 | agent 按钮 | 注释按钮 | git 状态
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
                if gitVM.isGitRepo {
                    Text("|")
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundColor(.secondary)
                        Text(gitVM.branch ?? "detached")
                            .foregroundColor(.primary)
                        if gitVM.changedCount > 0 {
                            Text("~\(gitVM.changedCount)")
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
