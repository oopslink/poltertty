// macos/Sources/Features/Workspace/WorktreeCreateForm.swift
import SwiftUI

struct WorktreeCreateForm: View {
    @ObservedObject var monitor: GitWorktreeMonitor
    let onDismiss: () -> Void

    @State private var branchName = ""
    @State private var path = ""
    @State private var createNewBranch = true
    @State private var selectedExistingBranch: String?
    @State private var baseBranch: String?
    @State private var availableBranches: [String] = []
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    private var currentBranch: String? {
        monitor.worktrees.first(where: { $0.isCurrent })?.branch
    }

    private var autoPath: String {
        let name = createNewBranch ? branchName : (selectedExistingBranch ?? "")
        return ".worktrees/" + name.replacingOccurrences(of: "/", with: "-")
    }

    private var effectivePath: String {
        path.isEmpty ? autoPath : path
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(String(localized: "Add Worktree"))
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 20)
                .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 12) {
                // Create new branch toggle
                Toggle(isOn: $createNewBranch) {
                    Text("Create new branch")
                        .font(.system(size: 12, weight: .medium))
                }
                .toggleStyle(.checkbox)

                // Branch name / picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Branch")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    if createNewBranch {
                        TextField("feature/my-feature", text: $branchName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                    } else {
                        Picker("", selection: $selectedExistingBranch) {
                            Text("Select a branch").tag(nil as String?)
                            ForEach(availableBranches, id: \.self) { branch in
                                Text(branch).tag(branch as String?)
                            }
                        }
                        .labelsHidden()
                    }
                }

                // Path
                VStack(alignment: .leading, spacing: 4) {
                    Text("Path")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField(autoPath, text: $path)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                    Text("Relative to repo root. Leave empty for default.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.6))
                }

                // Base branch (only for new branches)
                if createNewBranch {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Base branch")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Picker("", selection: $baseBranch) {
                            Text(currentBranch ?? "HEAD").tag(nil as String?)
                            ForEach(availableBranches, id: \.self) { branch in
                                Text(branch).tag(branch as String?)
                            }
                        }
                        .labelsHidden()
                    }
                }

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 20)

            // Buttons
            HStack {
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSubmitDisabled)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 380)
        .onAppear {
            availableBranches = monitor.listBranches()
            baseBranch = nil
        }
    }

    private var isSubmitDisabled: Bool {
        if isSubmitting { return true }
        if createNewBranch { return branchName.trimmingCharacters(in: .whitespaces).isEmpty }
        return selectedExistingBranch == nil
    }

    private func submit() {
        errorMessage = nil
        isSubmitting = true

        let branch = createNewBranch ? branchName : (selectedExistingBranch ?? "")
        let targetPath = effectivePath

        // Path validation
        if let gitRoot = monitor.worktrees.first?.path {
            let absPath = targetPath.hasPrefix("/")
                ? targetPath
                : URL(fileURLWithPath: gitRoot).appendingPathComponent(targetPath).path
            if FileManager.default.fileExists(atPath: absPath) {
                errorMessage = String(localized: "Directory already exists")
                isSubmitting = false
                return
            }
        }

        DispatchQueue.global().async {
            do {
                try monitor.addWorktree(
                    branch: branch,
                    path: targetPath,
                    baseBranch: baseBranch,
                    createNew: createNewBranch
                )
                DispatchQueue.main.async {
                    isSubmitting = false
                    onDismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }
}
