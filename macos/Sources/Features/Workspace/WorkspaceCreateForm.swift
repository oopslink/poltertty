// macos/Sources/Features/Workspace/WorkspaceCreateForm.swift
import SwiftUI

struct WorkspaceCreateForm: View {
    let onSubmit: (_ name: String, _ rootDir: String, _ colorHex: String, _ description: String) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var rootDir = "~"
    @State private var description = ""
    @State private var selectedColor = "#FF6B6B"

    private let presetColors = [
        "#FF6B6B", "#4ECDC4", "#FFD93D", "#6BCB77",
        "#7AA2F7", "#BB9AF7", "#FF9A8B", "#A8A8A8"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text("New Workspace")
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
                    TextField("My Project", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
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
                        ForEach(presetColors, id: \.self) { color in
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
                Button("Create") {
                    guard !name.isEmpty else { return }
                    onSubmit(name, rootDir, selectedColor, description)
                }
                .keyboardShortcut(.return)
                .disabled(name.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .frame(width: 400)
    }
}
