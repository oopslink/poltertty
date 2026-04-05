// macos/Sources/Features/Workspace/WorkspaceSidebar.swift
import AppKit
import SwiftUI

struct WorkspaceSidebar: View {
    @ObservedObject var manager = WorkspaceManager.shared
    @ObservedObject var notificationStore = AgentNotificationStore.shared
    let currentWorkspaceId: UUID?
    let onSwitch: (UUID) -> Void
    let onClose: (UUID) -> Void
    let onCreate: () -> Void
    let onCreateTemporary: () -> Void
    let onConvert: (WorkspaceModel) -> Void
    let onLaunchAgent: () -> Void

    @Binding var isCollapsed: Bool
    var worktreeMonitor: GitWorktreeMonitor? = nil
    var onOpenWorktreeInTab: ((String) -> Void)? = nil
    var onOpenWorktreeInWindow: ((String) -> Void)? = nil
    var onOpenWorktreeInSplit: ((String, SplitTree<Ghostty.SurfaceView>.NewDirection) -> Void)? = nil

    @State private var isCreating = false
    @State private var editingWorkspace: WorkspaceModel?
    @State private var showDeleteAlert = false
    @State private var pendingDeleteWorkspace: WorkspaceModel?
    @Namespace private var sidebarAnimation
    @State private var showDeleteGroupAlert = false
    @State private var pendingDeleteGroup: WorkspaceGroup?
    @State private var showWorktreeCreateForm = false
    @State private var worktreeExpanded = true
    @State private var pendingDeleteWorktreePath: String?
    @State private var pendingDeleteDirtyCount: Int = 0
    @State private var showDeleteWorktreeAlert = false

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
        .alert(
            String(localized: "workspace.delete.title \(pendingDeleteWorkspace?.name ?? "")"),
            isPresented: $showDeleteAlert
        ) {
            Button(String(localized: "workspace.delete.cancel"), role: .cancel) {
                pendingDeleteWorkspace = nil
            }
            Button(String(localized: "workspace.delete.confirm"), role: .destructive) {
                if let ws = pendingDeleteWorkspace {
                    manager.delete(id: ws.id)
                }
                pendingDeleteWorkspace = nil
            }
        } message: {
            Text(String(localized: "workspace.delete.message"))
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
        .alert(
            "Delete Group \"\(pendingDeleteGroup?.name ?? "")\"?",
            isPresented: $showDeleteGroupAlert
        ) {
            Button("Cancel", role: .cancel) { pendingDeleteGroup = nil }
            Button("Delete", role: .destructive) {
                if let g = pendingDeleteGroup { manager.deleteGroup(id: g.id) }
                pendingDeleteGroup = nil
            }
        } message: {
            Text("Workspaces in this group will be moved to ungrouped.")
        }
        .alert(
            "Delete worktree \"\(pendingDeleteWorktreePath?.components(separatedBy: "/").last ?? "")\"?",
            isPresented: $showDeleteWorktreeAlert
        ) {
            Button("Cancel", role: .cancel) {
                pendingDeleteWorktreePath = nil
            }
            Button(
                pendingDeleteDirtyCount > 0 ? "Force Delete" : "Delete",
                role: .destructive
            ) {
                if let path = pendingDeleteWorktreePath, let monitor = worktreeMonitor {
                    try? monitor.removeWorktree(path: path, force: pendingDeleteDirtyCount > 0)
                }
                pendingDeleteWorktreePath = nil
            }
        } message: {
            if let path = pendingDeleteWorktreePath {
                Text(path)
                if pendingDeleteDirtyCount > 0 {
                    Text("⚠ \(pendingDeleteDirtyCount) uncommitted changes will be lost")
                }
            }
        }
        .sheet(isPresented: $showWorktreeCreateForm) {
            if let monitor = worktreeMonitor {
                WorktreeCreateForm(monitor: monitor, onDismiss: { showWorktreeCreateForm = false })
            }
        }
    }

    // MARK: - Collapsed View

    private var collapsedContent: some View {
        VStack(spacing: 0) {
            // Toggle button (expand) + Agent button
            VStack(spacing: 6) {
                SidebarToggleButton(symbol: "chevron.right") {
                    isCollapsed = false
                    UserDefaults.standard.set(false, forKey: "poltertty.sidebarCollapsed")
                }

                Button(action: onLaunchAgent) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.38, green: 0.45, blue: 0.95),
                                             Color(red: 0.65, green: 0.32, blue: 0.95)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 32, height: 32)
                            .shadow(color: Color(red: 0.5, green: 0.38, blue: 0.95).opacity(0.55),
                                    radius: 6, x: 0, y: 2)
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .help("Launch Agent")

            }
            .padding(.vertical, 8)

            Divider()

            // Workspace icons + blank area (double-click blank to create temporary)
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        // 未分组 workspace
                        ForEach(manager.workspacesInGroup(nil)) { workspace in
                            CollapsedWorkspaceIcon(
                                workspace: workspace,
                                isActive: workspace.id == currentWorkspaceId,
                                isOpen: manager.windowForWorkspace(workspace.id) != nil,
                                unreadCount: notificationStore.unreadCount(for: workspace.id),
                                onTap: { onSwitch(workspace.id) },
                                onClose: { onClose(workspace.id) },
                                onDelete: { pendingDeleteWorkspace = workspace; showDeleteAlert = true },
                                onEdit: { editingWorkspace = workspace },
                                availableGroups: manager.groups,
                                onMoveToGroup: { groupId in
                                    manager.moveWorkspace(id: workspace.id, toGroup: groupId, insertAfter: nil)
                                },
                                onNewGroup: { showCreateGroupAlert(movingWorkspace: workspace) },
                                worktreeMonitor: workspace.id == currentWorkspaceId ? worktreeMonitor : nil,
                                onOpenWorktreeInTab: workspace.id == currentWorkspaceId ? onOpenWorktreeInTab : nil,
                                onOpenWorktreeInWindow: workspace.id == currentWorkspaceId ? onOpenWorktreeInWindow : nil,
                                onOpenWorktreeInSplit: workspace.id == currentWorkspaceId ? onOpenWorktreeInSplit : nil,
                                onDeleteWorktree: workspace.id == currentWorkspaceId ? { path in
                                    if let monitor = worktreeMonitor {
                                        confirmDeleteWorktree(path: path, monitor: monitor)
                                    }
                                } : nil
                            )
                        }

                        // 各个分组
                        ForEach(manager.groups) { group in
                            Divider().padding(.horizontal, 8).padding(.vertical, 2)

                            if group.isCollapsedIcon {
                                CollapsedGroupIcon(
                                    group: group,
                                    onToggle: { manager.toggleGroupCollapsedIcon(id: group.id) },
                                    onRename: { showRenameGroupAlert(group: group) },
                                    onDelete: { confirmDeleteGroup(group: group) }
                                )
                            } else {
                                VStack(spacing: 4) {
                                    Button(action: { manager.toggleGroupCollapsedIcon(id: group.id) }) {
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundColor(.secondary)
                                            .frame(width: 32, height: 16)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Collapse \(group.name)")

                                    ForEach(manager.workspacesInGroup(group.id)) { workspace in
                                        CollapsedWorkspaceIcon(
                                            workspace: workspace,
                                            isActive: workspace.id == currentWorkspaceId,
                                            isOpen: manager.windowForWorkspace(workspace.id) != nil,
                                            unreadCount: notificationStore.unreadCount(for: workspace.id),
                                            onTap: { onSwitch(workspace.id) },
                                            onClose: { onClose(workspace.id) },
                                            onDelete: { pendingDeleteWorkspace = workspace; showDeleteAlert = true },
                                            onEdit: { editingWorkspace = workspace },
                                            availableGroups: manager.groups,
                                            onMoveToGroup: { groupId in
                                                manager.moveWorkspace(id: workspace.id, toGroup: groupId, insertAfter: nil)
                                            },
                                            onNewGroup: { showCreateGroupAlert(movingWorkspace: workspace) },
                                            worktreeMonitor: workspace.id == currentWorkspaceId ? worktreeMonitor : nil,
                                            onOpenWorktreeInTab: workspace.id == currentWorkspaceId ? onOpenWorktreeInTab : nil,
                                            onOpenWorktreeInWindow: workspace.id == currentWorkspaceId ? onOpenWorktreeInWindow : nil,
                                            onOpenWorktreeInSplit: workspace.id == currentWorkspaceId ? onOpenWorktreeInSplit : nil,
                                            onDeleteWorktree: workspace.id == currentWorkspaceId ? { path in
                                                if let monitor = worktreeMonitor {
                                                    confirmDeleteWorktree(path: path, monitor: monitor)
                                                }
                                            } : nil
                                        )
                                    }
                                }
                            }
                        }

                        // Temporary（不参与分组）
                        if manager.hasTemporaryWorkspaces {
                            Divider().padding(.horizontal, 8).padding(.vertical, 4)
                            ForEach(manager.temporaryWorkspaces) { workspace in
                                CollapsedWorkspaceIcon(
                                    workspace: workspace,
                                    isActive: workspace.id == currentWorkspaceId,
                                    isOpen: manager.windowForWorkspace(workspace.id) != nil,
                                    unreadCount: notificationStore.unreadCount(for: workspace.id),
                                    onTap: { onSwitch(workspace.id) },
                                    onClose: { onClose(workspace.id) },
                                    onDelete: { pendingDeleteWorkspace = workspace; showDeleteAlert = true },
                                    onEdit: { editingWorkspace = workspace },
                                    // No availableGroups/onMoveToGroup/onNewGroup for Temporary
                                    worktreeMonitor: workspace.id == currentWorkspaceId ? worktreeMonitor : nil,
                                    onOpenWorktreeInTab: workspace.id == currentWorkspaceId ? onOpenWorktreeInTab : nil,
                                    onOpenWorktreeInWindow: workspace.id == currentWorkspaceId ? onOpenWorktreeInWindow : nil,
                                    onOpenWorktreeInSplit: workspace.id == currentWorkspaceId ? onOpenWorktreeInSplit : nil,
                                    onDeleteWorktree: workspace.id == currentWorkspaceId ? { path in
                                        if let monitor = worktreeMonitor {
                                            confirmDeleteWorktree(path: path, monitor: monitor)
                                        }
                                    } : nil
                                )
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onCreateTemporary() }

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

    // MARK: - Expanded View — Ungrouped Section

    private var ungroupedSection: some View {
        let items = manager.workspacesInGroup(nil)
        return VStack(spacing: 2) {
            ForEach(items) { workspace in
                ExpandedWorkspaceItem(
                    workspace: workspace,
                    isActive: workspace.id == currentWorkspaceId,
                    isOpen: manager.windowForWorkspace(workspace.id) != nil,
                    unreadCount: notificationStore.unreadCount(for: workspace.id),
                    animationNamespace: sidebarAnimation,
                    onTap: { onSwitch(workspace.id) },
                    onClose: { onClose(workspace.id) },
                    onDelete: { pendingDeleteWorkspace = workspace; showDeleteAlert = true },
                    onConvert: { onConvert(workspace) },
                    onEdit: { editingWorkspace = workspace },
                    onMoveToGroup: { groupId in
                        manager.moveWorkspace(id: workspace.id, toGroup: groupId, insertAfter: nil)
                    },
                    onNewGroup: { showCreateGroupAlert(movingWorkspace: workspace) },
                    availableGroups: manager.groups,
                    onShowCreateForm: workspace.id == currentWorkspaceId ? { showWorktreeCreateForm = true } : nil
                )
                if workspace.id == currentWorkspaceId,
                   let monitor = worktreeMonitor,
                   monitor.isGitRepo {
                    VStack(spacing: 0) {
                        Button(action: { worktreeExpanded.toggle() }) {
                            HStack(spacing: 4) {
                                Image(systemName: worktreeExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 10)
                                Text(monitor.worktrees.count == 1
                                     ? "1 worktree"
                                     : "\(monitor.worktrees.count) worktrees")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(3)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 14)
                        .padding(.trailing, 6)
                        .padding(.vertical, 2)

                        if worktreeExpanded {
                            WorktreeListView(
                                monitor: monitor,
                                onOpenInTab: { path in onOpenWorktreeInTab?(path) },
                                onOpenInWindow: { path in onOpenWorktreeInWindow?(path) },
                                onDelete: { path, _ in confirmDeleteWorktree(path: path, monitor: monitor) },
                                onOpenInSplit: onOpenWorktreeInSplit
                            )
                        }
                    }
                    .overlay(alignment: .leading) {
                        if worktreeExpanded {
                            Rectangle()
                                .fill(workspace.color.opacity(0.6))
                                .frame(width: 2)
                        }
                    }
                    .padding(.leading, 20)
                }
            }
        }
        .dropDestination(for: WorkspaceDragItem.self) { items, _ in
            guard let item = items.first else { return false }
            self.manager.moveWorkspace(id: item.workspaceId, toGroup: nil, insertAfter: nil)
            return true
        }
    }

    private var expandedContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("WORKSPACES")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(1)
                Spacer()
                Button(action: onLaunchAgent) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 0.45, green: 0.55, blue: 1.0),
                                         Color(red: 0.75, green: 0.40, blue: 1.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .buttonStyle(.plain)
                .help("Launch Agent")
                Button(action: { isCreating = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                SidebarToggleButton(symbol: "chevron.left") {
                    isCollapsed = true
                    UserDefaults.standard.set(true, forKey: "poltertty.sidebarCollapsed")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Workspace list + blank area (double-click blank to create temporary)
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        // 未分组 workspace
                        ungroupedSection

                        // 各个分组
                        ForEach(manager.groups) { group in
                            GroupHeaderRow(
                                group: group,
                                onToggle: { manager.toggleGroupExpanded(id: group.id) },
                                onRename: { showRenameGroupAlert(group: group) },
                                onDelete: { confirmDeleteGroup(group: group) }
                            )
                            .padding(.top, 4)

                            if group.isExpanded {
                                ForEach(manager.workspacesInGroup(group.id)) { workspace in
                                    ExpandedWorkspaceItem(
                                        workspace: workspace,
                                        isActive: workspace.id == currentWorkspaceId,
                                        isOpen: manager.windowForWorkspace(workspace.id) != nil,
                                        unreadCount: notificationStore.unreadCount(for: workspace.id),
                                        animationNamespace: sidebarAnimation,
                                        onTap: { onSwitch(workspace.id) },
                                        onClose: { onClose(workspace.id) },
                                        onDelete: { pendingDeleteWorkspace = workspace; showDeleteAlert = true },
                                        onConvert: { onConvert(workspace) },
                                        onEdit: { editingWorkspace = workspace },
                                        onMoveToGroup: { groupId in
                                            manager.moveWorkspace(id: workspace.id, toGroup: groupId, insertAfter: nil)
                                        },
                                        onNewGroup: { showCreateGroupAlert(movingWorkspace: workspace) },
                                        availableGroups: manager.groups,
                                        onShowCreateForm: workspace.id == currentWorkspaceId ? { showWorktreeCreateForm = true } : nil
                                    )
                                    .padding(.leading, 8)
                                    if workspace.id == currentWorkspaceId,
                                       let monitor = worktreeMonitor,
                                       monitor.isGitRepo {
                                        VStack(spacing: 0) {
                                            Button(action: { worktreeExpanded.toggle() }) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: worktreeExpanded ? "chevron.down" : "chevron.right")
                                                        .font(.system(size: 8, weight: .semibold))
                                                        .foregroundColor(.secondary)
                                                        .frame(width: 10)
                                                    Text(monitor.worktrees.count == 1
                                                         ? "1 worktree"
                                                         : "\(monitor.worktrees.count) worktrees")
                                                        .font(.system(size: 9))
                                                        .foregroundColor(.secondary)
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 1)
                                                        .background(Color.secondary.opacity(0.1))
                                                        .cornerRadius(3)
                                                    Spacer()
                                                }
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.leading, 14)
                                            .padding(.trailing, 6)
                                            .padding(.vertical, 2)

                                            if worktreeExpanded {
                                                WorktreeListView(
                                                    monitor: monitor,
                                                    onOpenInTab: { path in onOpenWorktreeInTab?(path) },
                                                    onOpenInWindow: { path in onOpenWorktreeInWindow?(path) },
                                                    onDelete: { path, _ in confirmDeleteWorktree(path: path, monitor: monitor) },
                                                    onOpenInSplit: onOpenWorktreeInSplit
                                                )
                                            }
                                        }
                                        .overlay(alignment: .leading) {
                                            if worktreeExpanded {
                                                Rectangle()
                                                    .fill(workspace.color.opacity(0.6))
                                                    .frame(width: 2)
                                            }
                                        }
                                        .padding(.leading, 20)
                                    }
                                }
                            }
                        }

                        // Temporary section（保持原有逻辑不变）
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
                                    unreadCount: notificationStore.unreadCount(for: workspace.id),
                                    animationNamespace: sidebarAnimation,
                                    onTap: { onSwitch(workspace.id) },
                                    onClose: { onClose(workspace.id) },
                                    onDelete: { pendingDeleteWorkspace = workspace; showDeleteAlert = true },
                                    onConvert: { onConvert(workspace) },
                                    onEdit: { editingWorkspace = workspace }
                                    // No onMoveToGroup/onNewGroup for Temporary workspaces
                                )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onCreateTemporary() }
            .contextMenu {
                Button("New Group…") { showCreateGroupAlert() }
                Divider()
                Button("New Workspace…") { isCreating = true }
                Button("New Temporary") { onCreateTemporary() }
            }

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

    private func showRenameGroupAlert(group: WorkspaceGroup) {
        let alert = NSAlert()
        alert.messageText = "Rename Group"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = group.name
        alert.accessoryView = field
        guard let window = NSApp.keyWindow else { return }
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let newName = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard !newName.isEmpty else { return }
            manager.renameGroup(id: group.id, name: newName)
        }
    }

    private func showCreateGroupAlert(movingWorkspace workspace: WorkspaceModel? = nil) {
        let alert = NSAlert()
        alert.messageText = "New Group"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Group name"
        alert.accessoryView = field
        guard let window = NSApp.keyWindow else { return }
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            let group = manager.createGroup(name: name)
            if let ws = workspace {
                manager.moveWorkspace(id: ws.id, toGroup: group.id, insertAfter: nil)
            }
        }
    }

    private func confirmDeleteGroup(group: WorkspaceGroup) {
        pendingDeleteGroup = group
        showDeleteGroupAlert = true
    }

    private func confirmDeleteWorktree(path: String, monitor: GitWorktreeMonitor) {
        pendingDeleteWorktreePath = path
        DispatchQueue.global().async {
            let count = monitor.dirtyFileCount(at: path)
            DispatchQueue.main.async {
                pendingDeleteDirtyCount = count
                showDeleteWorktreeAlert = true
            }
        }
    }
}

// MARK: - Collapsed Icon

struct CollapsedWorkspaceIcon: View {
    let workspace: WorkspaceModel
    let isActive: Bool
    let isOpen: Bool
    var unreadCount: Int = 0
    let onTap: () -> Void
    let onClose: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void
    var availableGroups: [WorkspaceGroup] = []
    var onMoveToGroup: ((UUID?) -> Void)? = nil
    var onNewGroup: (() -> Void)? = nil
    var worktreeMonitor: GitWorktreeMonitor? = nil
    var onOpenWorktreeInTab: ((String) -> Void)? = nil
    var onOpenWorktreeInWindow: ((String) -> Void)? = nil
    var onOpenWorktreeInSplit: ((String, SplitTree<Ghostty.SurfaceView>.NewDirection) -> Void)? = nil
    var onDeleteWorktree: ((String) -> Void)? = nil
    var metadata: WorkspaceMetadata = WorkspaceMetadata()

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
        VStack(spacing: 3) {
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
                .overlay(alignment: .topTrailing) {
                    if unreadCount > 0 {
                        Text("\(min(unreadCount, 99))")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.red))
                            .offset(x: 4, y: -4)
                    }
                }
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help(tooltipText)
            .contextMenu {
            if let monitor = worktreeMonitor, monitor.worktrees.count > 1 {
                Menu("Worktrees") {
                    ForEach(monitor.worktrees) { wt in
                        Menu(wt.branch ?? "detached") {
                            Button(String(localized: "Open in New Tab")) { onOpenWorktreeInTab?(wt.path) }
                            Button(String(localized: "Open in New Window")) { onOpenWorktreeInWindow?(wt.path) }
                            if onOpenWorktreeInSplit != nil {
                                Menu(String(localized: "Open in New Pane")) {
                                    Button(String(localized: "To the Right")) { onOpenWorktreeInSplit?(wt.path, .right) }
                                    Button(String(localized: "To the Left"))  { onOpenWorktreeInSplit?(wt.path, .left) }
                                    Button(String(localized: "Below"))        { onOpenWorktreeInSplit?(wt.path, .down) }
                                    Button(String(localized: "Above"))        { onOpenWorktreeInSplit?(wt.path, .up) }
                                }
                            }
                            if !wt.isMain && !wt.isCurrent {
                                Divider()
                                Button(String(localized: "Delete Worktree"), role: .destructive) {
                                    onDeleteWorktree?(wt.path)
                                }
                            }
                        }
                    }
                }
                Divider()
            }
            Button("Edit Workspace...") { onEdit() }
            Menu("Move to Group") {
                if workspace.groupId != nil {
                    Button("Ungrouped") { onMoveToGroup?(nil) }
                    Divider()
                }
                ForEach(availableGroups) { group in
                    if group.id != workspace.groupId {
                        Button(group.name) { onMoveToGroup?(group.id) }
                    }
                }
                Divider()
                Button("New Group…") { onNewGroup?() }
            }
            Divider()
            if isActive {
                Button("Close Workspace") { onClose() }
                Divider()
            }
            Button("Delete Workspace", role: .destructive) { onDelete() }
        }
        .onTapGesture(count: 2) {}  // prevent double-tap from passing through to blank area handler

            CollapsedMetadataDots(metadata: metadata)
        }
    }
}

// MARK: - Expanded Item

struct ExpandedWorkspaceItem: View {
    let workspace: WorkspaceModel
    let isActive: Bool
    let isOpen: Bool
    var unreadCount: Int = 0
    let animationNamespace: Namespace.ID
    let onTap: () -> Void
    let onClose: () -> Void
    let onDelete: () -> Void
    let onConvert: () -> Void
    let onEdit: () -> Void
    var onMoveToGroup: ((UUID?) -> Void)? = nil   // nil groupId = 移入未分组
    var onNewGroup: (() -> Void)? = nil
    var availableGroups: [WorkspaceGroup] = []
    var onShowCreateForm: (() -> Void)? = nil
    var metadata: WorkspaceMetadata = WorkspaceMetadata()
    var onOpenPort: ((Int) -> Void)? = nil

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

                    if unreadCount > 0 {
                        Text("\(unreadCount)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.red))
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

                if !metadata.listeningPorts.isEmpty || metadata.prStatus != nil || metadata.agentState != .none {
                    WorkspaceMetadataBadgeRow(metadata: metadata, onOpenPort: onOpenPort)
                }
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
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .onHover { isHovering = $0 }
        .padding(.horizontal, 6)
        .draggable(WorkspaceDragItem(workspaceId: workspace.id))
        .contextMenu {
            if let onShowCreateForm {
                Button("Add Worktree…") { onShowCreateForm() }
                Divider()
            }
            Button("Edit Workspace...") { onEdit() }
            Menu("Move to Group") {
                if workspace.groupId != nil {
                    Button("Ungrouped") { onMoveToGroup?(nil) }
                    Divider()
                }
                ForEach(availableGroups) { group in
                    if group.id != workspace.groupId {
                        Button(group.name) { onMoveToGroup?(group.id) }
                    }
                }
                Divider()
                Button("New Group…") { onNewGroup?() }
            }
            Divider()
            if workspace.isTemporary {
                Button("Convert to Workspace") { onConvert() }
                Divider()
            }
            if isOpen {
                Button("Close Workspace") { onClose() }
                Divider()
            }
            Button("Delete Workspace", role: .destructive) { onDelete() }
        }
        .onTapGesture(count: 2) {}  // prevent double-tap from passing through to blank area handler
    }

}

// MARK: - Collapsed Metadata Dots

private struct CollapsedMetadataDots: View {
    let metadata: WorkspaceMetadata
    @State private var pulseOpacity: Double = 1.0

    private var hasPort: Bool { !metadata.listeningPorts.isEmpty }
    private var portTooltip: String {
        metadata.listeningPorts.prefix(3).map { ":\($0)" }.joined(separator: " ")
    }

    var body: some View {
        HStack(spacing: 4) {
            // 左点：端口（蓝）
            Circle()
                .fill(hasPort ? Color(red: 0.58, green: 0.77, blue: 0.99) : Color.clear)
                .frame(width: 5, height: 5)
                .help(hasPort ? portTooltip : "")

            // 中点：Agent（黄闪=working，灰=idle，透明=none）
            agentDot

            // 右点：PR（绿=open，灰=draft，透明=none）
            prDot
        }
        .frame(height: 8)
        .onAppear {
            if metadata.agentState == .working { pulseOpacity = 0.2 }
        }
    }

    private var agentDot: some View {
        let color: Color
        switch metadata.agentState {
        case .working: color = Color(red: 0.99, green: 0.82, blue: 0.30)
        case .idle:    color = Color(nsColor: .tertiaryLabelColor)
        case .none:    color = .clear
        }
        return Circle()
            .fill(color)
            .frame(width: 5, height: 5)
            .opacity(metadata.agentState == .working ? pulseOpacity : 1.0)
            .animation(
                metadata.agentState == .working
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: pulseOpacity
            )
            .help(metadata.agentState == .none ? "" : (metadata.agentState == .working ? "Agent Working" : "Agent Idle"))
    }

    private var prDot: some View {
        let color: Color
        let tooltip: String
        switch metadata.prStatus {
        case .open:    color = Color(red: 0.53, green: 0.94, blue: 0.67); tooltip = "PR Open"
        case .draft:   color = Color(nsColor: .tertiaryLabelColor); tooltip = "PR Draft"
        case .merged:  color = Color(red: 0.77, green: 0.71, blue: 0.99); tooltip = "PR Merged"
        case .none:    color = .clear; tooltip = ""
        }
        return Circle()
            .fill(color)
            .frame(width: 5, height: 5)
            .help(tooltip)
    }
}

// MARK: - Metadata Badge Row

private struct WorkspaceMetadataBadgeRow: View {
    let metadata: WorkspaceMetadata
    var onOpenPort: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 3) {
            // 端口徽标（最多 3 个 + "+N"）
            let ports = metadata.listeningPorts
            let displayPorts = Array(ports.prefix(3))
            let overflow = ports.count - displayPorts.count
            ForEach(displayPorts, id: \.self) { port in
                Button(action: { onOpenPort?(port) }) {
                    Text(":\(port)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.58, green: 0.77, blue: 0.99))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(red: 0.23, green: 0.51, blue: 0.95).opacity(0.18))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(Color(red: 0.23, green: 0.51, blue: 0.95).opacity(0.25), lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(.plain)
                .help("在 Browser Panel 打开 http://localhost:\(port)")
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // PR 状态徽标
            if let pr = metadata.prStatus {
                PRBadgeView(status: pr)
            }

            // Agent 状态徽标
            if metadata.agentState != .none {
                AgentStateBadgeView(state: metadata.agentState)
            }
        }
    }
}

private struct PRBadgeView: View {
    let status: PRStatus

    private var textColor: Color {
        switch status {
        case .open:   return Color(red: 0.53, green: 0.94, blue: 0.67)
        case .draft:  return Color(nsColor: .tertiaryLabelColor)
        case .merged: return Color(red: 0.77, green: 0.71, blue: 0.99)
        }
    }
    private var bgColor: Color {
        switch status {
        case .open:   return Color(red: 0.13, green: 0.77, blue: 0.37).opacity(0.14)
        case .draft:  return Color.primary.opacity(0.07)
        case .merged: return Color(red: 0.55, green: 0.36, blue: 0.97).opacity(0.14)
        }
    }
    private var borderColor: Color {
        switch status {
        case .open:   return Color(red: 0.13, green: 0.77, blue: 0.37).opacity(0.22)
        case .draft:  return Color.primary.opacity(0.12)
        case .merged: return Color(red: 0.55, green: 0.36, blue: 0.97).opacity(0.22)
        }
    }

    var body: some View {
        Text(status.displayText)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(bgColor)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(borderColor, lineWidth: 0.5))
            )
    }
}

private struct AgentStateBadgeView: View {
    let state: WorkspaceAgentState
    @State private var pulseOpacity: Double = 1.0

    private var dotColor: Color {
        state == .working ? Color(red: 0.99, green: 0.82, blue: 0.30) : Color(nsColor: .tertiaryLabelColor)
    }
    private var textColor: Color {
        state == .working ? Color(red: 0.99, green: 0.85, blue: 0.42) : Color(nsColor: .secondaryLabelColor)
    }
    private var bgColor: Color {
        state == .working
            ? Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.14)
            : Color.primary.opacity(0.07)
    }
    private var borderColor: Color {
        state == .working
            ? Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.22)
            : Color.primary.opacity(0.12)
    }
    private var label: String { state == .working ? "Working" : "Idle" }

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(dotColor)
                .frame(width: 5, height: 5)
                .opacity(state == .working ? pulseOpacity : 1.0)
                .animation(
                    state == .working
                        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                        : .default,
                    value: pulseOpacity
                )
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(textColor)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(bgColor)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(borderColor, lineWidth: 0.5))
        )
        .onAppear {
            if state == .working { pulseOpacity = 0.25 }
        }
    }
}

// MARK: - Group Header Row

private struct GroupHeaderRow: View {
    let group: WorkspaceGroup
    let onToggle: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: group.isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 12)

            Text(group.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            Spacer()

            if isHovering {
                // 使用 SwiftUI Menu 作为 ··· 按钮，直接连接闭包，无 retain 问题
                Menu {
                    Button("Rename Group…") { onRename() }
                    Divider()
                    Button("Delete Group", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Rename Group…") { onRename() }
            Divider()
            Button("Delete Group", role: .destructive) { onDelete() }
        }
        .background(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
        .cornerRadius(4)
        .dropDestination(for: WorkspaceDragItem.self) { items, _ in
            guard let item = items.first else { return false }
            WorkspaceManager.shared.moveWorkspace(id: item.workspaceId, toGroup: group.id, insertAfter: nil)
            if !group.isExpanded {
                WorkspaceManager.shared.toggleGroupExpanded(id: group.id)
            }
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }
}

// MARK: - Collapsed Group Icon

struct CollapsedGroupIcon: View {
    let group: WorkspaceGroup
    let onToggle: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(isHovering ? 0.25 : 0.15))
                    .frame(width: 32, height: 32)

                Text(group.abbreviation)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(group.name)
        .contextMenu {
            Button("Rename Group…") { onRename() }
            Divider()
            Button("Delete Group", role: .destructive) { onDelete() }
        }
        .onTapGesture(count: 2) {}  // 阻止双击透传
    }
}

// MARK: - Sidebar Header Button (带 hover 背景的通用图标按钮)

private struct SidebarHeaderButton: View {
    let symbol: String
    let action: () -> Void
    var isActive: Bool = false
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(
                    isActive
                        ? Color.accentColor
                        : (isHovering ? Color.primary : Color.secondary)
                )
                .frame(width: 24, height: 24)
                .background(
                    isActive
                        ? Color.accentColor.opacity(0.15)
                        : (isHovering ? Color.primary.opacity(0.1) : Color.clear)
                )
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .animation(.easeInOut(duration: 0.15), value: isHovering)
                .animation(.easeInOut(duration: 0.15), value: isActive)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Sidebar Toggle Button (< / >)

private struct SidebarToggleButton: View {
    let symbol: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHovering ? Color.primary : Color.secondary)
                .frame(width: 24, height: 24)
                .background(isHovering ? Color.primary.opacity(0.1) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
