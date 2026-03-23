// macos/Sources/Features/Workspace/WorktreeListView.swift
import AppKit
import SwiftUI

struct WorktreeListView: View {
    @ObservedObject var monitor: GitWorktreeMonitor
    let onOpenInTab: (String) -> Void
    let onOpenInWindow: (String) -> Void
    let onDelete: (String, Bool) -> Void  // path, force
    let onShowCreateForm: () -> Void

    @State private var addButtonHovering = false

    var body: some View {
        VStack(spacing: 1) {
            ForEach(monitor.worktrees) { worktree in
                WorktreeRow(
                    worktree: worktree,
                    monitor: monitor,
                    onOpenInTab: onOpenInTab,
                    onOpenInWindow: onOpenInWindow,
                    onDelete: onDelete
                )
            }

            // + Add Worktree button
            Button(action: onShowCreateForm) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 9))
                    Text(String(localized: "Add Worktree"))
                        .font(.system(size: 10))
                }
                .foregroundColor(addButtonHovering ? .secondary : .secondary.opacity(0.55))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(addButtonHovering ? Color.primary.opacity(0.05) : .clear)
                )
            }
            .buttonStyle(.plain)
            .onHover { addButtonHovering = $0 }
        }
        .padding(.leading, 16)
    }
}

// MARK: - Worktree Row

private struct WorktreeRow: View {
    let worktree: GitWorktree
    let monitor: GitWorktreeMonitor
    let onOpenInTab: (String) -> Void
    let onOpenInWindow: (String) -> Void
    let onDelete: (String, Bool) -> Void

    @State private var isHovering = false
    @State private var dirtyCount: Int = 0
    @State private var dirtyLoaded = false

    private var iconColor: Color {
        if !worktree.exists { return .secondary.opacity(0.3) }
        return worktree.isCurrent ? .accentColor : .secondary
    }

    private var textColor: Color {
        if !worktree.exists { return .secondary.opacity(0.3) }
        return worktree.isCurrent ? .primary : .secondary
    }

    var body: some View {
        HStack(spacing: 6) {
            // 主 worktree 用 house 图标，linked worktree 用分支图标
            Image(systemName: worktree.isMain ? "house" : "arrow.triangle.branch")
                .font(.system(size: worktree.isMain ? 9 : 10))
                .foregroundColor(iconColor)
                .frame(width: 12)

            Text(worktree.branch ?? "detached")
                .font(.system(size: 11, weight: worktree.isCurrent ? .medium : .regular))
                .foregroundColor(textColor)
                .strikethrough(!worktree.exists, color: .secondary.opacity(0.4))
                .lineLimit(1)

            Spacer()

            // 状态指示
            HStack(spacing: 4) {
                // 未提交文件数 badge
                if worktree.exists && dirtyLoaded && dirtyCount > 0 {
                    Text("\(dirtyCount)")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.85))
                        .cornerRadius(3)
                }

                if !worktree.exists {
                    Text("missing")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.4))
                } else if worktree.isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(worktree.isCurrent && worktree.exists
                    ? Color.accentColor.opacity(0.07)
                    : (isHovering && worktree.exists ? Color.primary.opacity(0.04) : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if worktree.exists { onOpenInTab(worktree.path) }
        }
        .onTapGesture {}  // 单击不响应，防止事件传递到空白区域处理器
        .onHover { isHovering = $0 }
        .contextMenu {
            if worktree.exists {
                Button(String(localized: "Open in New Tab")) { onOpenInTab(worktree.path) }
                Button(String(localized: "Open in New Window")) { onOpenInWindow(worktree.path) }
                Divider()
                Button(String(localized: "Reveal in Finder")) {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.path)
                }
                Button(String(localized: "Copy Path")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(worktree.path, forType: .string)
                }
            }
            if !worktree.isMain && !worktree.isCurrent {
                Divider()
                Button(String(localized: "Delete Worktree"), role: .destructive) {
                    onDelete(worktree.path, false)
                }
            }
        }
        .task(id: worktree.path) {
            guard worktree.exists else { dirtyCount = 0; dirtyLoaded = true; return }
            let count = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .background).async {
                    continuation.resume(returning: monitor.dirtyFileCount(at: worktree.path))
                }
            }
            dirtyCount = count
            dirtyLoaded = true
        }
    }
}
