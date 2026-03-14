// macos/Sources/Features/Workspace/WorkspaceSidebar.swift
import SwiftUI

struct WorkspaceSidebar: View {
    @ObservedObject var manager = WorkspaceManager.shared
    let currentWorkspaceId: UUID?
    let onSwitch: (UUID) -> Void
    let onCreate: () -> Void

    @Binding var isCollapsed: Bool
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 0) {
            if isCollapsed {
                collapsedContent
            } else {
                expandedContent
            }
        }
        .frame(minWidth: isCollapsed ? 48 : 180)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .sheet(isPresented: $isCreating) {
            WorkspaceCreateForm(
                onSubmit: { name, rootDir, color, description in
                    manager.create(name: name, rootDir: rootDir, colorHex: color, description: description)
                    isCreating = false
                    onCreate()
                },
                onCancel: { isCreating = false }
            )
        }
    }

    // MARK: - Collapsed View

    private var collapsedContent: some View {
        VStack(spacing: 0) {
            // Toggle button
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isCollapsed = false } }) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)

            Divider()

            // Workspace icons
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(manager.workspaces) { workspace in
                        CollapsedWorkspaceIcon(
                            workspace: workspace,
                            isActive: workspace.id == currentWorkspaceId,
                            onTap: { onSwitch(workspace.id) },
                            onDelete: { manager.delete(id: workspace.id) }
                        )
                    }
                }
                .padding(.vertical, 6)
            }

            Spacer()

            Divider()

            // Add button
            Button(action: { isCreating = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Expanded View

    private var expandedContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("WORKSPACES")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(1)
                Spacer()
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isCollapsed = true } }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                Button(action: { isCreating = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Workspace list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(manager.workspaces) { workspace in
                        ExpandedWorkspaceItem(
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
        }
    }
}

// MARK: - Collapsed Icon

struct CollapsedWorkspaceIcon: View {
    let workspace: WorkspaceModel
    let isActive: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? workspace.color.opacity(0.2) : (isHovering ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isActive ? workspace.color : .clear, lineWidth: 1.5)
                    )

                Text(workspace.icon)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(isActive ? workspace.color : .secondary)
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(workspace.name)
        .contextMenu {
            Button("Delete Workspace", role: .destructive) { onDelete() }
        }
    }
}

// MARK: - Expanded Item

struct ExpandedWorkspaceItem: View {
    let workspace: WorkspaceModel
    let isActive: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Color indicator
                RoundedRectangle(cornerRadius: 4)
                    .fill(workspace.color)
                    .frame(width: 4, height: 36)
                    .opacity(isActive ? 1 : 0.3)

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.name)
                        .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                        .foregroundColor(isActive ? .primary : .secondary)
                        .lineLimit(1)

                    if !workspace.description.isEmpty {
                        Text(workspace.description)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.8))
                            .lineLimit(1)
                    }

                    Text(workspace.rootDir)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isActive
                    ? workspace.color.opacity(0.08)
                    : (isHovering ? Color.primary.opacity(0.04) : .clear)
            )
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .padding(.horizontal, 6)
        .contextMenu {
            Button("Delete Workspace", role: .destructive) { onDelete() }
        }
    }
}
