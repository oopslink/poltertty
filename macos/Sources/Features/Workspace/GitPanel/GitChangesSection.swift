// macos/Sources/Features/Workspace/GitPanel/GitChangesSection.swift
import SwiftUI

struct GitChangesSection: View {
    @ObservedObject var vm: GitPanelViewModel
    @State private var stagedExpanded = true
    @State private var unstagedExpanded = true
    @State private var discardConfirm: GitChange?
    @State private var hoveredChangeId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Staged
            if !vm.stagedFiles.isEmpty {
                subsectionHeader(
                    title: "Staged",
                    count: vm.stagedFiles.count,
                    isExpanded: $stagedExpanded,
                    accentColor: .green
                )

                if stagedExpanded {
                    ForEach(vm.stagedFiles) { change in
                        changeRow(change, isStaged: true)
                    }
                }
            }

            // Unstaged
            if !vm.unstagedFiles.isEmpty {
                if !vm.stagedFiles.isEmpty {
                    Divider().padding(.horizontal, 8).padding(.vertical, 2)
                }

                subsectionHeader(
                    title: "Unstaged",
                    count: vm.unstagedFiles.count,
                    isExpanded: $unstagedExpanded,
                    accentColor: .orange
                )

                if unstagedExpanded {
                    ForEach(vm.unstagedFiles) { change in
                        changeRow(change, isStaged: false)
                    }
                }
            }

            // Empty state
            if vm.stagedFiles.isEmpty && vm.unstagedFiles.isEmpty && !vm.isLoading {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.green.opacity(0.7))
                    Text("Working tree clean")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
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

    // MARK: - Subsection Header

    private func subsectionHeader(
        title: String,
        count: Int,
        isExpanded: Binding<Bool>,
        accentColor: Color
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 10)

                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)

                Text("\(count)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(accentColor.opacity(0.9))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(accentColor.opacity(0.12))
                    .cornerRadius(3)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Change Row

    @ViewBuilder
    private func changeRow(_ change: GitChange, isStaged: Bool) -> some View {
        let isHovered = hoveredChangeId == change.id
        let fileName = URL(fileURLWithPath: change.path).lastPathComponent

        HStack(spacing: 4) {
            Text(change.delta.symbol)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: change.delta.colorHex) ?? .secondary)
                .frame(width: 14)

            Text(fileName)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if isStaged {
                Button(action: { Task { await vm.unstage(change) } }) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 11))
                        .foregroundColor(isHovered ? .secondary : .secondary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .help("Unstage — 从下次提交中移除")
                .accessibilityLabel("Unstage \(fileName)")
            } else {
                Button(action: { Task { await vm.stage(change) } }) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 11))
                        .foregroundColor(isHovered ? Color.green.opacity(0.85) : .secondary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .help("Stage — 添加到下次提交")
                .accessibilityLabel("Stage \(fileName)")

                Button(action: { discardConfirm = change }) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11))
                        .foregroundColor(isHovered ? Color.orange.opacity(0.85) : .secondary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .help("Discard Changes — 不可撤销")
                .accessibilityLabel("Discard changes to \(fileName)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .cornerRadius(3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(change.delta.symbol) \(fileName)")
        .onHover { hovering in
            hoveredChangeId = hovering ? change.id : nil
        }
        .onTapGesture {
            Task { await vm.selectWorkingFile(change) }
        }
    }
}
