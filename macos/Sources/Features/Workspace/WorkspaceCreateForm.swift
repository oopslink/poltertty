// macos/Sources/Features/Workspace/WorkspaceCreateForm.swift
import SwiftUI

enum WorkspaceCreateSource: String, CaseIterable, Identifiable {
    case empty
    case snapshot
    case git

    var id: String { rawValue }

    var label: String {
        switch self {
        case .empty: return "Empty"
        case .snapshot: return "From Snapshot"
        case .git: return "From Git"
        }
    }
}

/// `GitCloner` 是引用类型且非 ObservableObject，用一个轻量持有者把它绑到 SwiftUI 生命周期。
final class GitClonerHolder: ObservableObject {
    let inner = GitCloner()
}

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
    @State private var source: WorkspaceCreateSource = .empty
    @State private var snapshotWorkspaceId: UUID? = nil
    @State private var snapshotEntryId: UUID? = nil

    // Git mode state
    @State private var gitURL: String = ""
    @State private var gitParentDir: String = "~"
    @State private var gitBranch: String = ""
    @State private var gitShallow: Bool = false
    @State private var nameWasManuallyEdited: Bool = false
    @State private var internallySettingName: Bool = false
    @State private var isCloning: Bool = false
    @State private var cloneProgress: String = ""
    @StateObject private var clonerHolder = GitClonerHolder()

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

    private var submitButtonTitle: String {
        if editing != nil { return "Save" }
        if isCloning { return "Cloning…" }
        return "Create"
    }

    private var submitDisabled: Bool {
        if name.isEmpty { return true }
        if isCloning { return true }
        if source == .git && gitURL.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text(editing != nil ? "Edit Workspace" : "New Workspace")
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 20)
                .padding(.bottom, 16)

            // Source picker (new workspace only)
            if editing == nil {
                Picker("", selection: $source) {
                    ForEach(WorkspaceCreateSource.allCases) { src in
                        Text(src.label).tag(src)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isCloning)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }

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
                    .disabled(isCloning)
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
                        .disabled(isCloning)
                }

                // Root directory (empty / snapshot modes)
                if source != .git {
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
                }

                // Git mode fields
                if source == .git {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Git URL")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        TextField("https://github.com/user/repo.git", text: $gitURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                            .disabled(isCloning)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Parent Directory")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        HStack(spacing: 6) {
                            TextField("~/projects", text: $gitParentDir)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13))
                                .disabled(isCloning)
                            Button("Browse...") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.allowsMultipleSelection = false
                                if panel.runModal() == .OK, let url = panel.url {
                                    gitParentDir = url.path
                                }
                            }
                            .font(.system(size: 12))
                            .disabled(isCloning)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Branch (optional)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        TextField("default branch", text: $gitBranch)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                            .disabled(isCloning)
                    }

                    Toggle("Shallow clone (--depth 1)", isOn: $gitShallow)
                        .font(.system(size: 12, weight: .medium))
                        .disabled(isCloning)
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

                // Snapshot source picker (new workspace only, snapshot mode)
                if editing == nil && source == .snapshot {
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
            .padding(.horizontal, 24)

            Spacer().frame(height: 20)

            // Clone progress (git mode while running)
            if isCloning {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.6)
                    Text(cloneProgress.isEmpty ? "Cloning…" : cloneProgress)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }

            Divider()

            // Buttons
            HStack {
                Button(isCloning ? "Cancel Clone" : "Cancel") {
                    if isCloning {
                        clonerHolder.inner.cancel()
                    } else {
                        onCancel()
                    }
                }
                .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button(submitButtonTitle) {
                    handleSubmit()
                }
                .keyboardShortcut(.return)
                .disabled(submitDisabled)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .frame(width: 400)
        .onChange(of: name) { _ in
            errorMessage = nil
            // 通过 gitURL 联动设置 name 时，跳过「用户手动编辑」标记
            if internallySettingName {
                internallySettingName = false
            } else if source == .git {
                nameWasManuallyEdited = true
            }
        }
        .onChange(of: gitURL) { newURL in
            guard source == .git, !nameWasManuallyEdited else { return }
            if let repoName = GitCloner.extractRepoName(from: newURL) {
                internallySettingName = true
                name = repoName
            }
        }
        .onChange(of: source) { _ in
            nameWasManuallyEdited = false
        }
        .onChange(of: snapshotWorkspaceId) { wsId in
            // 选择来源 Workspace 后实时预填 Root Directory
            guard source == .snapshot, rootDir == "~" || rootDir.isEmpty,
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
                source = .snapshot
                snapshotWorkspaceId = wsId
            }
        }
        .onDisappear {
            if isCloning {
                clonerHolder.inner.cancel()
            }
        }
    }

    // MARK: - Submit handlers

    private func showError(_ message: String) {
        errorMessage = message
        withAnimation(.linear(duration: 0.4)) { isShaking = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { isShaking = false }
    }

    private func handleSubmit() {
        let existingNames = manager.workspaces
            .filter { $0.id != editing?.id }
            .map { $0.name }
        if let error = WorkspaceNameValidator.validate(name, existingNames: existingNames) {
            showError(error)
            return
        }
        errorMessage = nil

        switch source {
        case .empty:
            onSubmit(name, rootDir, selectedColor, description)
        case .snapshot:
            var effectiveRoot = rootDir
            if let wsId = snapshotWorkspaceId,
               let sourceWorkspace = WorkspaceManager.shared.workspace(for: wsId),
               effectiveRoot == "~" || effectiveRoot.isEmpty {
                effectiveRoot = sourceWorkspace.rootDir
            }
            onSubmit(name, effectiveRoot, selectedColor, description)
        case .git:
            startClone()
        }
    }

    private func startClone() {
        let parent = (gitParentDir as NSString).expandingTildeInPath
        let trimmedBranch = gitBranch.trimmingCharacters(in: .whitespaces)
        let opts = GitCloner.Options(
            url: gitURL.trimmingCharacters(in: .whitespacesAndNewlines),
            parentDir: parent,
            branch: trimmedBranch.isEmpty ? nil : trimmedBranch,
            shallow: gitShallow
        )
        isCloning = true
        cloneProgress = ""
        errorMessage = nil

        clonerHolder.inner.start(
            options: opts,
            onProgress: { line in
                cloneProgress = line
            },
            onComplete: { result in
                isCloning = false
                switch result {
                case .success(let path):
                    onSubmit(name, path, selectedColor, description)
                case .failure(let err):
                    showError(err.errorDescription ?? "Clone failed")
                }
            }
        )
    }
}
