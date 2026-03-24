// macos/Sources/Features/Workspace/FileBrowser/DiffView.swift
import SwiftUI

struct DiffView: View {
    let rootDir: String
    let fileURL: URL
    let isStaged: Bool

    @State private var diffContent: String = ""
    @State private var isLoading: Bool = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if diffContent.isEmpty {
                Text("无变更内容")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(parsedLines.enumerated()), id: \.offset) { _, line in
                            diffLineView(line)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .task(id: "\(fileURL.path)-\(isStaged)") {
            isLoading = true
            diffContent = await GitStatusService.fetchDiff(
                rootDir: rootDir,
                fileURL: fileURL,
                staged: isStaged
            )
            isLoading = false
        }
    }

    private struct DiffLine {
        enum Kind { case added, removed, context, header, hunk }
        let kind: Kind
        let text: String
        let lineNum: String
    }

    private var parsedLines: [DiffLine] {
        var result: [DiffLine] = []
        var oldNum = 0
        var newNum = 0

        for line in diffContent.components(separatedBy: "\n") {
            if line.hasPrefix("@@") {
                // 解析 @@ -a,b +c,d @@ 格式
                let numbers = line.components(separatedBy: CharacterSet(charactersIn: "-+,@ "))
                    .compactMap { Int($0) }
                if numbers.count >= 2 {
                    oldNum = numbers[0]
                    newNum = numbers[1]
                }
                result.append(DiffLine(kind: .hunk, text: line, lineNum: ""))
            } else if line.hasPrefix("diff ") || line.hasPrefix("index ") ||
                      line.hasPrefix("--- ") || line.hasPrefix("+++ ") {
                result.append(DiffLine(kind: .header, text: line, lineNum: ""))
            } else if line.hasPrefix("+") {
                result.append(DiffLine(kind: .added, text: String(line.dropFirst()), lineNum: "\(newNum)"))
                newNum += 1
            } else if line.hasPrefix("-") {
                result.append(DiffLine(kind: .removed, text: String(line.dropFirst()), lineNum: "\(oldNum)"))
                oldNum += 1
            } else if !line.isEmpty {
                result.append(DiffLine(kind: .context, text: String(line.dropFirst()), lineNum: "\(newNum)"))
                oldNum += 1
                newNum += 1
            }
        }
        return result
    }

    @ViewBuilder
    private func diffLineView(_ line: DiffLine) -> some View {
        HStack(spacing: 0) {
            // 行号
            Text(line.lineNum)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 8)

            // 前缀符号
            Text(linePrefix(line.kind))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(lineForeground(line.kind))
                .frame(width: 12)

            // 内容
            Text(line.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(lineForeground(line.kind))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(lineBackground(line.kind))
    }

    private func linePrefix(_ kind: DiffLine.Kind) -> String {
        switch kind {
        case .added:   return "+"
        case .removed: return "-"
        case .hunk:    return "↕"
        default:       return " "
        }
    }

    private func lineForeground(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added:   return Color(hex: "#4ade80") ?? .green
        case .removed: return Color(hex: "#f87171") ?? .red
        case .hunk:    return Color(hex: "#60a5fa") ?? .blue
        case .header:  return .secondary
        case .context: return .primary.opacity(0.8)
        }
    }

    private func lineBackground(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added:   return (Color(hex: "#4ade80") ?? .green).opacity(0.08)
        case .removed: return (Color(hex: "#f87171") ?? .red).opacity(0.08)
        default:       return .clear
        }
    }
}
