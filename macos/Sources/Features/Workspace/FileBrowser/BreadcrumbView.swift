// macos/Sources/Features/Workspace/FileBrowser/BreadcrumbView.swift
import SwiftUI

struct BreadcrumbView: View {
    let segments: [FileBrowserViewModel.BreadcrumbSegment]
    let onTap: (FileBrowserViewModel.BreadcrumbSegment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    Button(action: { onTap(segment) }) {
                        Text(segment.name)
                            .font(.system(size: 10))
                            .foregroundColor(index == segments.count - 1 ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(height: 22)
    }
}
