// macos/Sources/Features/Workspace/GitPanel/GitCommitsSection.swift
import SwiftUI

struct GitCommitsSection: View {
    @ObservedObject var vm: GitPanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题
            Text("COMMITS (\(vm.commits.count))")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .separatorColor).opacity(0.3))

            if vm.commits.isEmpty && !vm.isLoading {
                Text("No commits")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(8)
            } else {
                ForEach(vm.commits) { commit in
                    GitCommitRow(
                        commit: commit,
                        isExpanded: vm.expandedCommits.contains(commit.id),
                        files: vm.commitFiles[commit.id],
                        onExpand: {
                            Task { await vm.expandCommit(commit) }
                        },
                        onSelectFile: { file in
                            Task { await vm.selectCommitFile(file, oid: commit.id) }
                        }
                    )
                    Divider().padding(.leading, 8)
                }
            }
        }
    }
}
