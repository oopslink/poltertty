// macos/Sources/Features/Workspace/WorkspaceSidebar.swift
import SwiftUI

struct WorkspaceSidebar: View {
    @ObservedObject var manager = WorkspaceManager.shared
    let currentWorkspaceId: UUID?
    let onSwitch: (UUID) -> Void
    let onCreate: () -> Void

    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("WORKSPACES")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(1)
                Spacer()
                Button(action: { isCreating = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create new workspace")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Workspace list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(manager.workspaces) { workspace in
                        WorkspaceSidebarItem(
                            workspace: workspace,
                            isActive: workspace.id == currentWorkspaceId,
                            onTap: { onSwitch(workspace.id) },
                            onDelete: { manager.delete(id: workspace.id) }
                        )
                    }
                }
                .padding(.vertical, 4)
            }

            Spacer()

            Divider()

            // Footer
            Button(action: { isCreating = true }) {
                HStack {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                    Text("New Workspace")
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if isCreating {
                WorkspaceCreateForm(
                    onSubmit: { name, rootDir, color in
                        manager.create(name: name, rootDir: rootDir, colorHex: color)
                        isCreating = false
                        onCreate()
                    },
                    onCancel: { isCreating = false }
                )
            }
        }
        .frame(minWidth: 160)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
}

// MARK: - Sidebar Item

struct WorkspaceSidebarItem: View {
    let workspace: WorkspaceModel
    let isActive: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isActive ? workspace.color : .clear)
                    .overlay(
                        Circle().stroke(workspace.color, lineWidth: isActive ? 0 : 1.5)
                    )
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(workspace.name)
                        .font(.system(size: 12, weight: isActive ? .medium : .regular))
                        .foregroundColor(isActive ? .primary : .secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isActive
                    ? workspace.color.opacity(0.08)
                    : (isHovering ? Color.primary.opacity(0.04) : .clear)
            )
            .overlay(
                Rectangle()
                    .fill(isActive ? workspace.color : .clear)
                    .frame(width: 3),
                alignment: .leading
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Delete Workspace", role: .destructive) { onDelete() }
        }
        .accessibilityLabel("Workspace: \(workspace.name), \(isActive ? "active" : "inactive")")
        .accessibilityHint(isActive ? "Current workspace" : "Double tap to switch")
    }
}
