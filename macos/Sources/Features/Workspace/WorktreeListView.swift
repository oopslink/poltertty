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
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10))
                .foregroundColor(iconColor)
            Text(worktree.branch ?? "detached")
                .font(.system(size: 11, weight: worktree.isCurrent ? .medium : .regular))
                .foregroundColor(textColor)
                .strikethrough(!worktree.exists, color: .secondary.opacity(0.4))
                .lineLimit(1)
            Spacer()
            if !worktree.exists {
                Text("missing")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary.opacity(0.4))
            } else if worktree.isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(worktree.isCurrent && worktree.exists
                    ? Color.accentColor.opacity(0.05)
                    : (isHovering && worktree.exists ? Color.primary.opacity(0.04) : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if worktree.exists { onOpenInTab(worktree.path) }
        }
        .onTapGesture(count: 2) {}  // prevent double-tap from passing through to blank area handler
        .onHover { isHovering = $0 }
        .contextMenu {
            if worktree.exists {
                Button(String(localized: "Open in New Tab")) { onOpenInTab(worktree.path) }
                Button(String(localized: "Open in New Window")) { onOpenInWindow(worktree.path) }
            }
            if !worktree.isMain && !worktree.isCurrent {
                Divider()
                Button(String(localized: "Delete Worktree"), role: .destructive) {
                    onDelete(worktree.path, false)
                }
            }
        }
    }
}
