// macos/Sources/Features/Workspace/GitPanel/GitCommitRow.swift
import SwiftUI

struct GitCommitRow: View {
    let commit: GitCommit
    let isExpanded: Bool
    let files: [GitCommitFile]?
    let onExpand: () -> Void
    let onSelectFile: (GitCommitFile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Commit 头部行
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .frame(width: 12)

                Text(commit.shortId)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)

                Text(commit.message)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Text(relativeDate(commit.date))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture { onExpand() }

            // 展开后的文件列表
            if isExpanded, let files = files {
                ForEach(files) { file in
                    HStack(spacing: 4) {
                        Spacer().frame(width: 20)
                        Text(file.delta.symbol)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: file.delta.colorHex) ?? .secondary)
                            .frame(width: 14)
                        Text(URL(fileURLWithPath: file.path).lastPathComponent)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelectFile(file) }
                }
            } else if isExpanded {
                // 加载中
                HStack {
                    Spacer().frame(width: 20)
                    ProgressView().scaleEffect(0.6)
                    Text("Loading...")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}
