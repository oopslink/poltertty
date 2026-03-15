// macos/Sources/Features/Workspace/WorkspaceCreateForm.swift
import SwiftUI

struct WorkspaceCreateForm: View {
    let onSubmit: (_ name: String, _ rootDir: String, _ colorHex: String, _ description: String) -> Void
    let onCancel: () -> Void
    /// When set, the form is in "edit" mode — pre-fills fields and changes title/button text
    var editing: WorkspaceModel?

    @State private var name = ""
    @State private var rootDir = "~"
    @State private var description = ""
    @State private var selectedColor = "#FF6B6B"
    @State private var errorMessage: String?
    @State private var isShaking = false
    @ObservedObject var manager = WorkspaceManager.shared

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
        .onAppear {
            if let ws = editing {
                name = ws.name
                rootDir = ws.rootDir
                description = ws.description
                selectedColor = ws.colorHex
            }
        }
    }
}
