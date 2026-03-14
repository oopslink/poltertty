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
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Text("New Workspace")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 12)

            // Name
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .padding(.horizontal, 12)

            // Description
            TextField("Description (optional)", text: $description)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .padding(.horizontal, 12)

            // Root directory
            HStack {
                TextField("Root Directory", text: $rootDir)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                Button("...") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        rootDir = url.path
                    }
                }
                .font(.system(size: 10))
            }
            .padding(.horizontal, 12)

            // Color picker
            HStack(spacing: 6) {
                ForEach(presetColors, id: \.self) { color in
                    Circle()
                        .fill(Color(hex: color) ?? .gray)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle().stroke(.white, lineWidth: selectedColor == color ? 2 : 0)
                        )
                        .onTapGesture { selectedColor = color }
                }
            }
            .padding(.horizontal, 12)

            // Buttons
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .font(.system(size: 11))
                Button("Create") {
                    guard !name.isEmpty else { return }
                    onSubmit(name, rootDir, selectedColor, description)
                }
                .font(.system(size: 11))
                .keyboardShortcut(.return)
                .disabled(name.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
