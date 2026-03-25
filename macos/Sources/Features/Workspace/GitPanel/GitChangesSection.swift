// macos/Sources/Features/Workspace/GitPanel/GitChangesSection.swift
import SwiftUI

struct GitChangesSection: View {
    @ObservedObject var vm: GitPanelViewModel
    @State private var stagedExpanded = true
    @State private var unstagedExpanded = true
    @State private var discardConfirm: GitChange?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("CHANGES", count: vm.changedCount)

            // Staged
            DisclosureGroup(isExpanded: $stagedExpanded) {
                ForEach(vm.stagedFiles) { change in
                    changeRow(change, isStaged: true)
                }
            } label: {
                Text("Staged (\(vm.stagedFiles.count))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
            }

            Divider().padding(.leading, 8)

            // Unstaged
            DisclosureGroup(isExpanded: $unstagedExpanded) {
                ForEach(vm.unstagedFiles) { change in
                    changeRow(change, isStaged: false)
                }
            } label: {
                Text("Unstaged (\(vm.unstagedFiles.count))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
            }
        }
        .alert("Discard Changes?", isPresented: .init(
            get: { discardConfirm != nil },
            set: { if !$0 { discardConfirm = nil } }
        )) {
            Button("Cancel", role: .cancel) { discardConfirm = nil }
            Button("Discard", role: .destructive) {
                if let c = discardConfirm {
                    Task { await vm.discard(c) }
                    discardConfirm = nil
                }
            }
        } message: {
            Text("This will permanently discard changes to \(discardConfirm?.path ?? "").")
        }
    }

    @ViewBuilder
    private func changeRow(_ change: GitChange, isStaged: Bool) -> some View {
        HStack(spacing: 4) {
            // delta 颜色标记
            Text(change.delta.symbol)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: change.delta.colorHex) ?? .secondary)
                .frame(width: 14)

            Text(URL(fileURLWithPath: change.path).lastPathComponent)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if isStaged {
                Button(action: { Task { await vm.unstage(change) } }) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Unstage")
            } else {
                Button(action: { Task { await vm.stage(change) } }) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Stage")

                Button(action: { discardConfirm = change }) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Discard Changes")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await vm.selectWorkingFile(change) }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        Text("\(title) (\(count))")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .separatorColor).opacity(0.3))
    }
}
