// macos/Sources/Features/Workspace/WorkspaceCreateForm.swift
import SwiftUI

struct WorkspaceCreateForm: View {
    let onSubmit: (_ name: String, _ rootDir: String, _ colorHex: String, _ description: String) -> Void
    let onCancel: () -> Void
    /// When set, the form is in "edit" mode — pre-fills fields and changes title/button text
    var editing: WorkspaceModel?
    /// 从快照管理面板点击「从此创建」时传入，自动开启「从已有快照创建」并预选来源
    var preselectedSourceWorkspaceId: UUID? = nil

    @State private var name = ""
    @State private var rootDir = "~"
    @State private var description = ""
    @State private var selectedColor = "#FF6B6B"
    @State private var errorMessage: String?
    @State private var isShaking = false
    @State private var createFromSnapshot = false
    @State private var snapshotWorkspaceId: UUID? = nil
    @State private var snapshotEntryId: UUID? = nil
    @ObservedObject var manager = WorkspaceManager.shared

    private var availableWorkspaces: [WorkspaceModel] {
        WorkspaceManager.shared.workspaces.filter { !$0.isTemporary }
    }

    private func snapshotEntries(for workspaceId: UUID) -> [SnapshotEntry] {
        let store = SnapshotStore(
            workspaceId: workspaceId,
            storageRootURL: URL(fileURLWithPath: PolterttyConfig.shared.workspaceDir)
        )
        return store.loadAll().sorted { $0.savedAt > $1.savedAt }
    }

    static let presetColors = [
        "#FF6B6B", "#4ECDC4", "#FFD93D", "#6BCB77",
        "#7AA2F7", "#BB9AF7", "#FF9A8B", "#A8A8A8"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text(editing != nil ? "Edit Workspace" : "New Workspace")
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 20)
                .padding(.bottom, 16)

            // Form fields
            VStack(alignment: .leading, spacing: 12) {
                // Name
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField("My Project", text: Binding(
                        get: { name },
                        set: { name = WorkspaceNameValidator.filterInput($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(errorMessage != nil ? Color.red : Color.clear, lineWidth: 1.5)
                    )
                    .modifier(ShakeEffect(shakes: isShaking ? 6 : 0))
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    }
                }

                // Description
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField("Optional description", text: $description)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                }

                // Root directory
                VStack(alignment: .leading, spacing: 4) {
                    Text("Root Directory")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        TextField("~/projects/my-project", text: $rootDir)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                        Button("Browse...") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let url = panel.url {
                                rootDir = url.path
                            }
                        }
                        .font(.system(size: 12))
                    }
                }

                // Color
                VStack(alignment: .leading, spacing: 4) {
                    Text("Color")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        ForEach(Self.presetColors, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color) ?? .gray)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle().stroke(.white, lineWidth: selectedColor == color ? 2.5 : 0)
                                )
                                .shadow(color: selectedColor == color ? (Color(hex: color) ?? .gray).opacity(0.5) : .clear, radius: 3)
                                .onTapGesture { selectedColor = color }
                        }
                    }
                }

                // Create from snapshot (new workspace only)
                if editing == nil {
                    Divider()
                        .padding(.vertical, 4)

                    Toggle("Create from snapshot", isOn: $createFromSnapshot)
                        .font(.system(size: 12, weight: .medium))

                    if createFromSnapshot {
                        if availableWorkspaces.isEmpty {
                            Text("No snapshots available")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        } else {
                            Picker("Source Workspace", selection: $snapshotWorkspaceId) {
                                Text("Select…").tag(UUID?.none)
                                ForEach(availableWorkspaces) { ws in
                                    Text(ws.name).tag(Optional(ws.id))
                                }
                            }
                            .font(.system(size: 13))

                            if let wsId = snapshotWorkspaceId {
                                let entries = snapshotEntries(for: wsId)
                                if entries.isEmpty {
                                    Text("No snapshots for this workspace")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                } else {
                                    Picker("Snapshot", selection: $snapshotEntryId) {
                                        Text("Select…").tag(UUID?.none)
                                        ForEach(entries) { entry in
                                            Text(entry.savedAt.formatted(.relative(presentation: .named)))
                                                .tag(Optional(entry.id))
                                        }
                                    }
                                    .font(.system(size: 13))
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 20)

            Divider()

            // Buttons
            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button(editing != nil ? "Save" : "Create") {
                    // When editing, exclude the current name from uniqueness check
                    let existingNames = manager.workspaces
                        .filter { $0.id != editing?.id }
                        .map { $0.name }
                    if let error = WorkspaceNameValidator.validate(name, existingNames: existingNames) {
                        errorMessage = error
                        withAnimation(.linear(duration: 0.4)) { isShaking = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { isShaking = false }
                        return
                    }
                    errorMessage = nil
                    // 选中「从快照创建」时，从来源 Workspace 复制 rootDir
                    if createFromSnapshot,
                       let wsId = snapshotWorkspaceId,
                       let sourceWorkspace = WorkspaceManager.shared.workspace(for: wsId),
                       rootDir == "~" || rootDir.isEmpty {
                        rootDir = sourceWorkspace.rootDir
                    }
                    onSubmit(name, rootDir, selectedColor, description)
                }
                .keyboardShortcut(.return)
                .disabled(name.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .frame(width: 400)
        .onChange(of: name) { _ in
            errorMessage = nil
        }
        .onChange(of: snapshotWorkspaceId) { wsId in
            // 选择来源 Workspace 后实时预填 Root Directory
            guard createFromSnapshot, rootDir == "~" || rootDir.isEmpty,
                  let wsId,
                  let sourceWorkspace = WorkspaceManager.shared.workspace(for: wsId)
            else { return }
            rootDir = sourceWorkspace.rootDir
        }
        .onAppear {
            if let ws = editing {
                name = ws.name
                rootDir = ws.rootDir
                description = ws.description
                selectedColor = ws.colorHex
            } else if let wsId = preselectedSourceWorkspaceId {
                // 从快照管理面板的「从此创建」触发：自动开启并预选来源 Workspace
                createFromSnapshot = true
                snapshotWorkspaceId = wsId
            }
        }
    }
}
