// macos/Sources/Features/Workspace/WorktreeListView.swift
import SwiftUI

struct WorktreeListView: View {
    @ObservedObject var monitor: GitWorktreeMonitor
    let onOpenInTab: (String) -> Void
    let onOpenInWindow: (String) -> Void
    let onDelete: (String, Bool) -> Void  // path, force
    let onShowCreateForm: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(monitor.worktrees) { worktree in
                WorktreeRow(
                    worktree: worktree,
                    onOpenInTab: onOpenInTab,
                    onOpenInWindow: onOpenInWindow,
                    onDelete: onDelete
                )
            }

            // + Add Worktree button
            Button(action: onShowCreateForm) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 9))
                    Text(String(localized: "Add Worktree"))
                        .font(.system(size: 10))
                }
                .foregroundColor(.secondary.opacity(0.6))
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 16)
    }
}

// MARK: - Worktree Row

private struct WorktreeRow: View {
    let worktree: GitWorktree
    let onOpenInTab: (String) -> Void
    let onOpenInWindow: (String) -> Void
    let onDelete: (String, Bool) -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10))
                .foregroundColor(worktree.isCurrent ? .accentColor : .secondary)
            Text(worktree.branch ?? "detached")
                .font(.system(size: 11, weight: worktree.isCurrent ? .medium : .regular))
                .foregroundColor(worktree.isCurrent ? .primary : .secondary)
                .lineLimit(1)
            Spacer()
            if worktree.isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(worktree.isCurrent
                    ? Color.accentColor.opacity(0.05)
                    : (isHovering ? Color.primary.opacity(0.04) : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpenInWindow(worktree.path) }
        .onTapGesture { onOpenInTab(worktree.path) }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(String(localized: "Open in New Tab")) { onOpenInTab(worktree.path) }
            Button(String(localized: "Open in New Window")) { onOpenInWindow(worktree.path) }
            if !worktree.isMain && !worktree.isCurrent {
                Divider()
                Button(String(localized: "Delete Worktree"), role: .destructive) {
                    onDelete(worktree.path, false)
                }
            }
        }
    }
}
