// macos/Sources/Features/Workspace/OnboardingView.swift
import SwiftUI

struct OnboardingView: View {
    let onCreateFormal: (_ name: String, _ rootDir: String, _ colorHex: String, _ description: String) -> Void
    let onCreateTemporary: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo area
            VStack(spacing: 16) {
                Text("✦ Poltertty")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)

                Text("Create your first Workspace")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            Spacer().frame(height: 24)

            // Reuse WorkspaceCreateForm
            WorkspaceCreateForm(
                onSubmit: { name, rootDir, colorHex, description in
                    onCreateFormal(name, rootDir, colorHex, description)
                },
                onCancel: {
                    // Cancel = create temporary instead
                    onCreateTemporary()
                }
            )

            Spacer().frame(height: 12)

            // Temporary option
            Button(action: onCreateTemporary) {
                Text("Or create a temporary Workspace")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
