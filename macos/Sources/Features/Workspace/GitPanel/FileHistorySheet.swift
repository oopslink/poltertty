// macos/Sources/Features/Workspace/GitPanel/FileHistorySheet.swift
import SwiftUI

struct FileHistorySheet: View {
    @StateObject private var vm: FileHistoryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showRestoreAlert = false
    @State private var restoreError: String?

    init(path: String, repo: GitRepository) {
        _vm = StateObject(wrappedValue: FileHistoryViewModel(path: path, repo: repo))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("History: \(URL(fileURLWithPath: vm.filePath).lastPathComponent)")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    // 左侧：commit 列表
                    List(vm.commits, selection: Binding(
                        get: { vm.selectedCommit?.id },
                        set: { id in
                            if let c = vm.commits.first(where: { $0.id == id }) {
                                Task { await vm.selectCommit(c) }
                            }
                        }
                    )) { commit in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(commit.message)
                                .font(.system(size: 11))
                                .lineLimit(1)
                            HStack {
                                Text(commit.shortId)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(commit.date.relativeShortAgo)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        .tag(commit.id)
                    }
                    .frame(minWidth: 220, maxWidth: 300)

                    // 右侧：diff
                    DiffView(diff: vm.selectedDiff, title: nil)
                        .frame(minWidth: 300)
                }
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Restore to Selected Commit") {
                    showRestoreAlert = true
                }
                .disabled(vm.selectedCommit == nil)
                Button("Close") { dismiss() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 600, minHeight: 400)
        .task { await vm.load() }
        .alert("Restore File?", isPresented: $showRestoreAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) {
                Task {
                    do {
                        try await vm.restoreToSelected()
                        dismiss()
                    } catch {
                        restoreError = error.localizedDescription
                    }
                }
            }
        } message: {
            if let c = vm.selectedCommit {
                Text("Restore \(URL(fileURLWithPath: vm.filePath).lastPathComponent) to commit \(c.shortId)?")
            }
        }
        .alert("Restore Failed", isPresented: .init(
            get: { restoreError != nil },
            set: { if !$0 { restoreError = nil } }
        )) {
            Button("OK", role: .cancel) { restoreError = nil }
        } message: {
            Text(restoreError ?? "")
        }
    }

}
