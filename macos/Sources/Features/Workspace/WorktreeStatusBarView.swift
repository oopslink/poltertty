import SwiftUI

struct WorktreeStatusBarView: View {
    @ObservedObject var monitor: GitWorktreeMonitor
    let onSelectWorktree: (String) -> Void

    @State private var isPopoverPresented = false

    var body: some View {
        // Don't render if not a git repo
        guard monitor.isGitRepo else {
            return AnyView(EmptyView())
        }

        // Don't render if no worktrees
        guard !monitor.worktrees.isEmpty else {
            return AnyView(EmptyView())
        }

        let currentWorktree = monitor.worktrees.first { $0.isCurrent }
        let hasMultipleWorktrees = monitor.worktrees.count > 1

        return AnyView(
            HStack(spacing: 0) {
                if hasMultipleWorktrees {
                    // Clickable button with popover
                    Button(action: {
                        isPopoverPresented.toggle()
                    }) {
                        worktreeLabel(currentWorktree)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                        WorktreeListPopover(
                            worktrees: monitor.worktrees,
                            gitRoot: monitor.gitRoot ?? "",
                            onSelect: { path in
                                isPopoverPresented = false
                                onSelectWorktree(path)
                            }
                        )
                    }
                } else {
                    // Non-interactive label
                    worktreeLabel(currentWorktree)
                }

                Spacer()
            }
            .frame(height: 22)
            .padding(.horizontal, 8)
            .background(Color(nsColor: .controlBackgroundColor))
        )
    }

    @ViewBuilder
    private func worktreeLabel(_ worktree: GitWorktree?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            if let worktree = worktree {
                Text(worktree.branch ?? "detached HEAD")
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
            } else {
                Text("unknown")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
    }
}

struct WorktreeListPopover: View {
    let worktrees: [GitWorktree]
    let gitRoot: String
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(worktrees) { worktree in
                WorktreeRow(
                    worktree: worktree,
                    gitRoot: gitRoot,
                    onSelect: onSelect
                )
            }
        }
        .frame(minWidth: 250, maxWidth: 400)
        .padding(.vertical, 4)
    }
}

struct WorktreeRow: View {
    let worktree: GitWorktree
    let gitRoot: String
    let onSelect: (String) -> Void

    var body: some View {
        Button(action: {
            if !worktree.isCurrent {
                onSelect(worktree.path)
            }
        }) {
            HStack(spacing: 8) {
                // Checkmark for current worktree
                if worktree.isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                        .frame(width: 16)
                } else {
                    Color.clear.frame(width: 16)
                }

                VStack(alignment: .leading, spacing: 2) {
                    // Path label
                    Text(pathLabel(for: worktree))
                        .font(.system(size: 12))
                        .foregroundColor(.primary)

                    // Branch name
                    if let branch = worktree.branch {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(branch)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("detached HEAD")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            worktree.isCurrent
                ? Color.clear
                : Color(nsColor: .controlBackgroundColor).opacity(0.0)
        )
        .onHover { isHovered in
            if !worktree.isCurrent && isHovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func pathLabel(for worktree: GitWorktree) -> String {
        // Main worktree shows as "."
        if worktree.isMain {
            return "."
        }

        // Compute relative path from git root
        let gitRootURL = URL(fileURLWithPath: gitRoot).standardized
        let worktreeURL = URL(fileURLWithPath: worktree.path).standardized

        if worktreeURL.path.hasPrefix(gitRootURL.path) {
            let relativePath = String(worktreeURL.path.dropFirst(gitRootURL.path.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return relativePath.isEmpty ? "." : relativePath
        }

        // Fallback to absolute path if not relative
        return worktree.path
    }
}
