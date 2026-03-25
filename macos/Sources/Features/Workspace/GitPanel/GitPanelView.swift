// macos/Sources/Features/Workspace/GitPanel/GitPanelView.swift
import SwiftUI

struct GitPanelView: View {
    @ObservedObject var vm: GitPanelViewModel

    var body: some View {
        if !vm.isGitRepo {
            VStack(spacing: 0) {
                Spacer()
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
                Text("Not a git repository")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                if !vm.lastAttemptedDir.isEmpty {
                    Text(vm.lastAttemptedDir.replacingOccurrences(
                        of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HSplitView {
                // 左：Changes + Commits 列表
                VStack(spacing: 0) {
                    // 头部：分支 + 刷新
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(vm.branch ?? "detached")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button(action: { Task { await vm.refresh() } }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .help("Refresh")
                        // Commit button (v2, disabled)
                        Button(action: {}) {
                            Label("Commit", systemImage: "plus.circle")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .disabled(true)
                        .help("Commit (coming soon)")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .windowBackgroundColor))

                    Divider()

                    // Error 提示
                    if let err = vm.error {
                        Text(err)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }

                    ScrollView {
                        VStack(spacing: 0) {
                            GitChangesSection(vm: vm)
                            Divider()
                            GitCommitsSection(vm: vm)
                        }
                    }
                }
                .frame(minWidth: 200, maxWidth: 320)

                // 右：Diff 面板
                DiffView(diff: vm.selectedDiff, title: diffTitle)
                    .frame(minWidth: 300)
            }
        }
    }

    private var diffTitle: String? {
        guard let diff = vm.selectedDiff else { return nil }
        return diff.path
    }
}
