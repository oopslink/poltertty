// macos/Sources/Features/Workspace/FileBrowser/DiffView.swift
import SwiftUI

struct DiffView: View {
    let diff: GitFileDiff?
    let title: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let t = title {
                Text(t)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .windowBackgroundColor))
                Divider()
            }
            if let diff = diff {
                if diff.patches.isEmpty {
                    Text("No changes")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(diff.patches) { patch in
                                patchView(patch)
                            }
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            } else {
                Text("Select a file to view diff")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func patchView(_ patch: GitPatch) -> some View {
        // Hunk header
        Text(patch.header)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(Color(hex: "#60a5fa") ?? .blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((Color(hex: "#60a5fa") ?? .blue).opacity(0.06))

        ForEach(patch.lines) { line in
            diffLineView(line)
        }
    }

    @ViewBuilder
    private func diffLineView(_ line: GitDiffLine) -> some View {
        HStack(spacing: 0) {
            // 旧行号
            Text(line.oldLineNo.map { "\($0)" } ?? "")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.5))
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 4)
            // 新行号
            Text(line.newLineNo.map { "\($0)" } ?? "")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.5))
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 6)
            // 前缀符号
            Text(linePrefix(for: line.origin))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(lineForeground(for: line.origin))
                .frame(width: 12)
            // 内容
            Text(line.content)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(lineForeground(for: line.origin))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(lineBackground(for: line.origin))
    }

    private func linePrefix(for origin: GitDiffLine.Origin) -> String {
        switch origin {
        case .added:   return "+"
        case .removed: return "-"
        case .context: return " "
        }
    }

    private func lineForeground(for origin: GitDiffLine.Origin) -> Color {
        switch origin {
        case .added:   return Color(hex: "#4ade80") ?? .green
        case .removed: return Color(hex: "#f87171") ?? .red
        case .context: return .primary.opacity(0.8)
        }
    }

    private func lineBackground(for origin: GitDiffLine.Origin) -> Color {
        switch origin {
        case .added:   return (Color(hex: "#4ade80") ?? .green).opacity(0.08)
        case .removed: return (Color(hex: "#f87171") ?? .red).opacity(0.08)
        case .context: return .clear
        }
    }
}
