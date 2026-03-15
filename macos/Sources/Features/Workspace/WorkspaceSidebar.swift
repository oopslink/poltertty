// macos/Sources/Features/Workspace/WorkspaceSidebar.swift
import SwiftUI

struct WorkspaceSidebar: View {
    @ObservedObject var manager = WorkspaceManager.shared
    let currentWorkspaceId: UUID?
    let onSwitch: (UUID) -> Void
    let onClose: (UUID) -> Void
    let onCreate: () -> Void
    let onCreateTemporary: () -> Void
    let onConvert: (WorkspaceModel) -> Void

    @Binding var isCollapsed: Bool
    @State private var isCreating = false
    @State private var editingWorkspace: WorkspaceModel?
    @Namespace private var sidebarAnimation

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
        .sheet(item: $editingWorkspace) { workspace in
            WorkspaceCreateForm(
                onSubmit: { name, rootDir, color, description in
                    var updated = workspace
                    updated.name = name
                    updated.rootDir = rootDir
                    updated.colorHex = color
                    updated.description = description
                    updated.icon = String(name.prefix(2).uppercased())
                    manager.update(updated)
                    editingWorkspace = nil
                },
                onCancel: { editingWorkspace = nil },
                editing: workspace
            )
        }
    }

    // MARK: - Collapsed View

    private var collapsedContent: some View {
        VStack(spacing: 0) {
            // Toggle button (expand)
            Button(action: {
                isCollapsed = false
                UserDefaults.standard.set(false, forKey: "poltertty.sidebarCollapsed")
            }) {
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
                    ForEach(manager.formalWorkspaces) { workspace in
                        CollapsedWorkspaceIcon(
                            workspace: workspace,
                            isActive: workspace.id == currentWorkspaceId,
                            isOpen: manager.windowForWorkspace(workspace.id) != nil,
                            onTap: { onSwitch(workspace.id) },
                            onClose: { onClose(workspace.id) },
                            onDelete: { manager.delete(id: workspace.id) },
                            onEdit: { editingWorkspace = workspace }
                        )
                    }

                    if manager.hasTemporaryWorkspaces {
                        Divider().padding(.horizontal, 8).padding(.vertical, 4)

                        ForEach(manager.temporaryWorkspaces) { workspace in
                            CollapsedWorkspaceIcon(
                                workspace: workspace,
                                isActive: workspace.id == currentWorkspaceId,
                                isOpen: manager.windowForWorkspace(workspace.id) != nil,
                                onTap: { onSwitch(workspace.id) },
                                onClose: { onClose(workspace.id) },
                                onDelete: { manager.delete(id: workspace.id) },
                                onEdit: { editingWorkspace = workspace }
                            )
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            Spacer()

            Divider()

            // Add button: single click = new workspace, double click = new temporary
            Image(systemName: "plus")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(6)
                .onTapGesture(count: 2) { onCreateTemporary() }
                .onTapGesture(count: 1) { isCreating = true }
                .help("Click: New Workspace\nDouble-click: New Temporary")
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
                Button(action: {
                    isCollapsed = true
                    UserDefaults.standard.set(true, forKey: "poltertty.sidebarCollapsed")
                }) {
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
                    // Formal workspaces
                    ForEach(manager.formalWorkspaces) { workspace in
                        ExpandedWorkspaceItem(
                            workspace: workspace,
                            isActive: workspace.id == currentWorkspaceId,
                            isOpen: manager.windowForWorkspace(workspace.id) != nil,
                            animationNamespace: sidebarAnimation,
                            onTap: { onSwitch(workspace.id) },
                            onClose: { onClose(workspace.id) },
                            onDelete: { manager.delete(id: workspace.id) },
                            onConvert: { onConvert(workspace) },
                            onEdit: { editingWorkspace = workspace }
                        )
                    }

                    // Temporary section
                    if manager.hasTemporaryWorkspaces {
                        HStack {
                            Text("Temporary")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.6))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 2)

                        ForEach(manager.temporaryWorkspaces) { workspace in
                            ExpandedWorkspaceItem(
                                workspace: workspace,
                                isActive: workspace.id == currentWorkspaceId,
                                isOpen: manager.windowForWorkspace(workspace.id) != nil,
                                animationNamespace: sidebarAnimation,
                                onTap: { onSwitch(workspace.id) },
                                onClose: { onClose(workspace.id) },
                                onDelete: { manager.delete(id: workspace.id) },
                                onConvert: { onConvert(workspace) },
                                onEdit: { editingWorkspace = workspace }
                            )
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Spacer()

            Divider()

            // Footer — side-by-side [+ New | + Temporary]
            HStack(spacing: 0) {
                Button(action: { isCreating = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 9))
                        Text("New")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                Divider().frame(height: 16)

                Button(action: onCreateTemporary) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 9))
                        Text("Temporary")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Collapsed Icon

struct CollapsedWorkspaceIcon: View {
    let workspace: WorkspaceModel
    let isActive: Bool
    let isOpen: Bool
    let onTap: () -> Void
    let onClose: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void

    @State private var isHovering = false

    private var tooltipText: String {
        var parts = [workspace.name]
        if !workspace.description.isEmpty {
            parts.append(workspace.description)
        }
        parts.append(workspace.rootDir)
        return parts.joined(separator: "\n")
    }

    /// Always show workspace color: full when active, dimmed when open but not active, grey when closed
    private var iconFill: Color {
        let baseColor = workspace.isTemporary ? (Color(hex: "#F59E0B") ?? .yellow) : workspace.color
        if isActive {
            return baseColor
        } else if isOpen {
            return baseColor.opacity(0.4)
        } else if isHovering {
            return baseColor.opacity(0.15)
        } else {
            return baseColor.opacity(0.1)
        }
    }

    private var iconTextColor: Color {
        if isActive {
            return .white
        } else if isOpen {
            return workspace.color
        } else {
            return workspace.color.opacity(0.5)
        }
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isActive ? .white.opacity(0.9) : .clear, lineWidth: 2)
                    )
                    .shadow(color: isActive ? workspace.color.opacity(0.5) : .clear, radius: 4)

                Text(workspace.icon)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(iconTextColor)
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(tooltipText)
        .contextMenu {
            Button("Edit Workspace...") { onEdit() }
            Divider()
            if isActive {
                Button("Close Workspace") { onClose() }
                Divider()
            }
            Button("Delete Workspace", role: .destructive) { onDelete() }
        }
    }
}

// MARK: - Expanded Item

struct ExpandedWorkspaceItem: View {
    let workspace: WorkspaceModel
    let isActive: Bool
    let isOpen: Bool
    let animationNamespace: Namespace.ID
    let onTap: () -> Void
    let onClose: () -> Void
    let onDelete: () -> Void
    let onConvert: () -> Void
    let onEdit: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    private var indicatorColor: Color {
        workspace.isTemporary ? (Color(hex: "#F59E0B") ?? .yellow) : workspace.color
    }

    private var activeBackground: Color {
        workspace.isTemporary
            ? (Color(hex: "#F59E0B") ?? .yellow).opacity(0.08)
            : workspace.color.opacity(0.08)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if workspace.isTemporary {
                            Text("\u{23F1}")
                                .font(.system(size: 10))
                        }
                        Text(workspace.name)
                            .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                            .foregroundColor(isActive ? .primary : .secondary)
                            .lineLimit(1)

                        if isOpen {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 5, height: 5)
                        }
                    }

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
                    ? activeBackground
                    : (isHovering ? Color.primary.opacity(0.04) : .clear)
            )
            .cornerRadius(6)
            .overlay(alignment: .leading) {
                if isActive {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(indicatorColor)
                        .frame(width: 3, height: 36)
                        .matchedGeometryEffect(id: "activeIndicator", in: animationNamespace)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .onHover { isHovering = $0 }
        .padding(.horizontal, 6)
        .contextMenu {
            Button("Edit Workspace...") { onEdit() }
            Divider()
            if workspace.isTemporary {
                Button("转为正式 Workspace") { onConvert() }
                Divider()
            }
            if isOpen {
                Button("Close Workspace") { onClose() }
                Divider()
            }
            Button("Delete Workspace", role: .destructive) { onDelete() }
        }
    }
}
