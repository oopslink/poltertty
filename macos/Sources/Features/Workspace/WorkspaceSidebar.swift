// macos/Sources/Features/Workspace/WorkspaceSidebar.swift
import AppKit
import SwiftUI

struct WorkspaceSidebar: View {
    @ObservedObject var manager = WorkspaceManager.shared
    let currentWorkspaceId: UUID?
    let onSwitch: (UUID) -> Void
    let onClose: (UUID) -> Void
    let onCreate: () -> Void
    let onCreateTemporary: () -> Void
    let onConvert: (WorkspaceModel) -> Void
    let onLaunchAgent: () -> Void

    @Binding var isCollapsed: Bool
    @State private var isCreating = false
    @State private var editingWorkspace: WorkspaceModel?
    @State private var showDeleteAlert = false
    @State private var pendingDeleteWorkspace: WorkspaceModel?
    @Namespace private var sidebarAnimation
    @State private var showDeleteGroupAlert = false
    @State private var pendingDeleteGroup: WorkspaceGroup?

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
                        ForEach(manager.formalWorkspaces) { workspace in
                            CollapsedWorkspaceIcon(
                                workspace: workspace,
                                isActive: workspace.id == currentWorkspaceId,
                                isOpen: manager.windowForWorkspace(workspace.id) != nil,
                                onTap: { onSwitch(workspace.id) },
                                onClose: { onClose(workspace.id) },
                                onDelete: { pendingDeleteWorkspace = workspace; showDeleteAlert = true },
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
                                    onDelete: { pendingDeleteWorkspace = workspace; showDeleteAlert = true },
                                    onEdit: { editingWorkspace = workspace }
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

    private func ungroupedDropHandler(providers: [NSItemProvider]) -> Bool {
        if let provider = providers.first {
            _ = provider.loadDataRepresentation(
                forTypeIdentifier: WorkspaceModel.dragType.rawValue
            ) { data, _ in
                guard let data = data,
                      let uuidStr = String(data: data, encoding: .utf8),
                      let wsId = UUID(uuidString: uuidStr) else { return }
                DispatchQueue.main.async {
                    WorkspaceManager.shared.moveWorkspace(id: wsId, toGroup: nil, insertAfter: nil)
                }
            }
        }
        return true
    }

    private var ungroupedSection: some View {
        let items = manager.workspacesInGroup(nil)
        return VStack(spacing: 2) {
            ForEach(items) { workspace in
                ExpandedWorkspaceItem(
                    workspace: workspace,
                    isActive: workspace.id == currentWorkspaceId,
                    isOpen: manager.windowForWorkspace(workspace.id) != nil,
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
                    availableGroups: manager.groups
                )
            }
        }
        .onDrop(of: [WorkspaceModel.utType], isTargeted: nil, perform: ungroupedDropHandler)
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
                SidebarToggleButton(symbol: "chevron.left") {
                    isCollapsed = true
                    UserDefaults.standard.set(true, forKey: "poltertty.sidebarCollapsed")
                }
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
                                        availableGroups: manager.groups
                                    )
                                    .padding(.leading, 8)
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
        .onTapGesture(count: 2) {}  // prevent double-tap from passing through to blank area handler
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
    var onMoveToGroup: ((UUID?) -> Void)? = nil   // nil groupId = 移入未分组
    var onNewGroup: (() -> Void)? = nil
    var availableGroups: [WorkspaceGroup] = []

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
        .onDrag {
            let provider = NSItemProvider()
            provider.registerDataRepresentation(
                forTypeIdentifier: WorkspaceModel.dragType.rawValue,
                visibility: .all
            ) { completion in
                completion(self.workspace.id.uuidString.data(using: .utf8), nil)
                return nil
            }
            return provider
        }
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .onHover { isHovering = $0 }
        .padding(.horizontal, 6)
        .contextMenu {
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
                Button("转为正式 Workspace") { onConvert() }
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

// MARK: - Group Header Row

private struct GroupHeaderRow: View {
    let group: WorkspaceGroup
    let onToggle: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    private func workspaceDropHandler(providers: [NSItemProvider]) -> Bool {
        if let provider = providers.first {
            _ = provider.loadDataRepresentation(
                forTypeIdentifier: WorkspaceModel.dragType.rawValue
            ) { data, _ in
                guard let data = data,
                      let uuidStr = String(data: data, encoding: .utf8),
                      let wsId = UUID(uuidString: uuidStr) else { return }
                DispatchQueue.main.async {
                    WorkspaceManager.shared.moveWorkspace(id: wsId, toGroup: self.group.id, insertAfter: nil)
                    if !self.group.isExpanded {
                        WorkspaceManager.shared.toggleGroupExpanded(id: self.group.id)
                    }
                }
            }
        }
        return true
    }

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
        .onDrag {
            let provider = NSItemProvider()
            provider.registerDataRepresentation(
                forTypeIdentifier: WorkspaceGroup.dragType.rawValue,
                visibility: .all
            ) { completion in
                completion(self.group.id.uuidString.data(using: .utf8), nil)
                return nil
            }
            return provider
        }
        .onDrop(of: [WorkspaceModel.utType], isTargeted: nil, perform: workspaceDropHandler)
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
