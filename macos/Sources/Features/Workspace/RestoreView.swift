// macos/Sources/Features/Workspace/RestoreView.swift
import SwiftUI

struct RestoreView: View {
    let workspaces: [WorkspaceModel]
    let onRestore: ([UUID]) -> Void
    let onCreateNew: () -> Void

    @State private var selected: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Text("📂 恢复 Workspaces")
                    .font(.system(size: 20, weight: .bold))
            }

            Spacer().frame(height: 24)

            // Workspace list
            VStack(spacing: 0) {
                ForEach(workspaces) { workspace in
                    Button(action: { toggleSelection(workspace.id) }) {
                        HStack(spacing: 12) {
                            Image(systemName: selected.contains(workspace.id) ? "checkmark.square.fill" : "square")
                                .font(.system(size: 16))
                                .foregroundColor(selected.contains(workspace.id) ? .accentColor : .secondary)

                            Text(workspace.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)

                            Spacer()

                            Text(relativeTime(workspace.lastActiveAt))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            selected.contains(workspace.id)
                                ? Color.accentColor.opacity(0.06)
                                : Color.clear
                        )
                    }
                    .buttonStyle(.plain)

                    if workspace.id != workspaces.last?.id {
                        Divider().padding(.horizontal, 16)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(10)
            .frame(width: 400)

            Spacer().frame(height: 24)

            // Main restore button
            Button(action: {
                onRestore(Array(selected))
            }) {
                Text("恢复选中的 (\(selected.count))")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(selected.isEmpty ? Color.gray : Color.accentColor)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(selected.isEmpty)

            Spacer().frame(height: 12)

            // Quick actions
            HStack(spacing: 16) {
                Button("只恢复最近一个") {
                    if let first = workspaces.first {
                        onRestore([first.id])
                    }
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .buttonStyle(.plain)

                Text("|").foregroundColor(.secondary.opacity(0.3))

                Button("全部恢复") {
                    onRestore(workspaces.map { $0.id })
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
            }

            Spacer().frame(height: 20)

            // New workspace option
            Button(action: onCreateNew) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                    Text("新建 Workspace")
                        .font(.system(size: 12))
                }
                .foregroundColor(selected.isEmpty ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { preselectRecent() }
    }

    private func toggleSelection(_ id: UUID) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    private func preselectRecent() {
        let recent = workspaces.prefix(2)
        selected = Set(recent.map { $0.id })
    }

    private static let timeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private func relativeTime(_ date: Date) -> String {
        Self.timeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
