// macos/Sources/Features/Workspace/GitPanel/GitCommitRow.swift
import SwiftUI

struct GitCommitRow: View {
    let commit: GitCommit
    let isExpanded: Bool
    let files: [GitCommitFile]?
    var selectedFileId: String? = nil
    let onExpand: () -> Void
    let onSelectFile: (GitCommitFile) -> Void

    @State private var isHovered = false
    @State private var hoveredFileId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Commit header
            HStack(spacing: 5) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)

                Text(commit.shortId)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.accentColor.opacity(0.8))

                Text(commit.message)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Text(commit.date.relativeShort)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Commit \(commit.shortId): \(commit.message)")
            .accessibilityHint(isExpanded ? "Collapse" : "Expand to see changed files")
            .onHover { hovering in isHovered = hovering }
            .onTapGesture { onExpand() }

            // Expanded file list
            if isExpanded, let files = files {
                VStack(spacing: 0) {
                    ForEach(files) { file in
                        let isSelected = selectedFileId == file.id
                        let fileHovered = hoveredFileId == file.id

                        HStack(spacing: 0) {
                            // 选中指示条（左侧 accent 色竖条）
                            Rectangle()
                                .fill(isSelected ? Color.accentColor : Color.clear)
                                .frame(width: 2)
                            HStack(spacing: 4) {
                                Text(file.delta.symbol)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color(hex: file.delta.colorHex) ?? .secondary)
                                    .frame(width: 14)
                                Text(URL(fileURLWithPath: file.path).lastPathComponent)
                                    .font(.system(size: 11))
                                    .fontWeight(isSelected ? .medium : .regular)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary.opacity(fileHovered || isSelected ? 0.8 : 0.4))
                            }
                            .padding(.leading, 20)
                            .padding(.trailing, 8)
                        }
                        .padding(.vertical, 3)
                        .background(
                            isSelected
                                ? Color.accentColor.opacity(0.12)
                                : (fileHovered ? Color.primary.opacity(0.05) : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .cornerRadius(3)
                        .onHover { hovering in
                            hoveredFileId = hovering ? file.id : nil
                        }
                        .onTapGesture { onSelectFile(file) }
                    }
                }
                .padding(.bottom, 2)
            } else if isExpanded {
                HStack {
                    Spacer().frame(width: 18)
                    ProgressView().scaleEffect(0.6)
                    Text("Loading...")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            Divider().padding(.horizontal, 8)
        }
    }
}
