// macos/Sources/Features/Workspace/FileBrowser/FilterChipsView.swift
import SwiftUI

struct FilterChipsView: View {
    @ObservedObject var viewModel: FileBrowserViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // 扩展名 Chips
                ForEach(viewModel.availableExtensions, id: \.ext) { item in
                    FilterChip(
                        label: ".\(item.ext)",
                        count: item.count,
                        isActive: viewModel.activeExtensions.contains(item.ext),
                        color: .accentColor
                    ) {
                        viewModel.toggleExtensionFilter(item.ext)
                    }
                }

                if !viewModel.availableExtensions.isEmpty && !gitStatusItems.isEmpty {
                    Divider().frame(height: 16)
                }

                // Git 状态 Chips
                ForEach(gitStatusItems, id: \.status.rawValue) { item in
                    FilterChip(
                        label: item.label,
                        count: nil,
                        isActive: viewModel.activeGitStatuses.contains(item.status),
                        color: Color(hex: item.status.colorHex) ?? .secondary
                    ) {
                        viewModel.toggleGitStatusFilter(item.status)
                    }
                }

                // 清除全部按钮
                if viewModel.hasActiveFilters {
                    Button(action: { viewModel.clearAllFilters() }) {
                        Text("清除")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .frame(height: 28)
    }

    private struct GitStatusItem {
        let status: GitStatus
        let label: String
    }

    private var gitStatusItems: [GitStatusItem] {
        guard !viewModel.gitStatuses.isEmpty else { return [] }
        return [
            GitStatusItem(status: .modified, label: "已修改"),
            GitStatusItem(status: .untracked, label: "未追踪"),
            GitStatusItem(status: .added, label: "已添加"),
            GitStatusItem(status: .deleted, label: "已删除"),
        ]
    }
}

private struct FilterChip: View {
    let label: String
    let count: Int?
    let isActive: Bool
    let color: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 10))
                if let count {
                    Text("×\(count)")
                        .font(.system(size: 9))
                        .opacity(0.7)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(isActive ? color.opacity(0.2) : Color.primary.opacity(0.07))
            .foregroundColor(isActive ? color : .secondary)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isActive ? color.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
