// macos/Sources/Features/Workspace/GitPanel/GitCommitsSection.swift
import SwiftUI

struct GitCommitsSection: View {
    @ObservedObject var vm: GitPanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)

                Text("COMMITS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)

                if !vm.commits.isEmpty {
                    Text("\(vm.commits.count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(3)
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .separatorColor).opacity(0.2))

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
                        selectedFileId: vm.selectedCommitFileId,
                        onExpand: {
                            Task { await vm.expandCommit(commit) }
                        },
                        onSelectFile: { file in
                            Task { await vm.selectCommitFile(file, oid: commit.id) }
                        }
                    )
                }
            }
        }
    }
}
