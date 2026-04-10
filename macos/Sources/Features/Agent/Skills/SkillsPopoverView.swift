// macos/Sources/Features/Agent/Skills/SkillsPopoverView.swift
import SwiftUI

struct SkillsPopoverView: View {
    @ObservedObject private var manager = SkillManager.shared
    @State private var refreshTick = UUID()
    @State private var skillToUninstall: SkillDefinition?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ForEach(manager.availableSkills) { skill in
                SkillRow(
                    skill: skill,
                    manager: manager,
                    refreshTick: $refreshTick,
                    onUninstall: { skillToUninstall = skill },
                    onError: { errorMessage = $0 }
                )
                if skill.id != manager.availableSkills.last?.id {
                    Divider()
                }
            }
            if let errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
        .frame(width: 340)
        .onAppear { refreshTick = UUID() }
        .alert(
            "Uninstall Skill",
            isPresented: Binding(
                get: { skillToUninstall != nil },
                set: { if !$0 { skillToUninstall = nil } }
            )
        ) {
            Button("Uninstall", role: .destructive) {
                guard let skill = skillToUninstall else { return }
                Task {
                    do {
                        try await manager.uninstall(skill)
                        refreshTick = UUID()
                        errorMessage = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let skill = skillToUninstall {
                Text("Remove \"\(skill.displayName)\" skill? Claude Code agents will no longer have access to this capability.")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "puzzlepiece.extension")
                .foregroundStyle(.secondary)
            Text("Claude Code Skills")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

// MARK: - Skill Row

private struct SkillRow: View {
    let skill: SkillDefinition
    let manager: SkillManager
    @Binding var refreshTick: UUID
    var onUninstall: () -> Void
    var onError: (String) -> Void
    @State private var isLoading = false

    private var installed: Bool { manager.isInstalled(skill) }
    private var needsUpdate: Bool { manager.hasUpdate(skill) }

    var body: some View {
        HStack(spacing: 12) {
            statusDot
            info
            Spacer()
            actionButton
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .id(refreshTick)
    }

    private var statusDot: some View {
        Circle()
            .fill(installed ? Color.green : Color.secondary.opacity(0.3))
            .frame(width: 8, height: 8)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(skill.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if needsUpdate {
                    Text("Update available")
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
            Text(skill.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if isLoading {
            ProgressView().controlSize(.small)
        } else if installed && needsUpdate {
            Button("Update") { performInstall() }
                .buttonStyle(.bordered).controlSize(.small)
        } else if installed {
            Button("Uninstall") { onUninstall() }
                .buttonStyle(.bordered).controlSize(.small)
        } else {
            Button("Install") { performInstall() }
                .buttonStyle(.borderedProminent).controlSize(.small)
        }
    }

    private func performInstall() {
        isLoading = true
        Task {
            do {
                try await manager.install(skill)
                refreshTick = UUID()
                errorMessage(nil)
            } catch {
                errorMessage(error.localizedDescription)
            }
            isLoading = false
        }
    }

    private func errorMessage(_ msg: String?) {
        if let msg { onError(msg) }
    }
}
