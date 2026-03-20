// macos/Sources/Features/Workspace/WorkspaceQuickSwitcher.swift
import SwiftUI

struct WorkspaceQuickSwitcher: View {
    @ObservedObject var manager = WorkspaceManager.shared
    let currentWorkspaceId: UUID?
    let onSelect: (UUID) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0

    private var filtered: [WorkspaceModel] {
        if query.isEmpty { return manager.workspaces }
        return manager.workspaces.filter { ws in
            let gName = manager.groups.first(where: { $0.id == ws.groupId })?.name ?? ""
            return ws.name.localizedCaseInsensitiveContains(query) ||
                   ws.tags.contains { $0.localizedCaseInsensitiveContains(query) } ||
                   gName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Switch Workspace...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .onSubmit { confirmSelection() }
            }
            .padding(12)

            Divider()

            // Results
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, workspace in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(workspace.id == currentWorkspaceId ? workspace.color : .clear)
                                .overlay(
                                    Circle().stroke(workspace.color, lineWidth: workspace.id == currentWorkspaceId ? 0 : 1.5)
                                )
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(workspace.name)
                                    .font(.system(size: 13, weight: workspace.id == currentWorkspaceId ? .semibold : .regular))
                                Text(workspace.rootDir)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                if let groupId = workspace.groupId,
                                   let groupName = manager.groups.first(where: { $0.id == groupId })?.name {
                                    Text(groupName)
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary.opacity(0.6))
                                        .lineLimit(1)
                                }
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(index == selectedIndex ? Color.accentColor.opacity(0.15) : .clear)
                        .cornerRadius(4)
                        .onTapGesture {
                            onSelect(workspace.id)
                            onDismiss()
                        }
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 400)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.3), radius: 20)
        .backport.onKeyPress(.upArrow) { _ in moveSelection(-1); return .handled }
        .backport.onKeyPress(.downArrow) { _ in moveSelection(1); return .handled }
        .backport.onKeyPress(.escape) { _ in onDismiss(); return .handled }
        .onChange(of: query) { _ in selectedIndex = 0 }
    }

    private func moveSelection(_ delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func confirmSelection() {
        guard !filtered.isEmpty, selectedIndex < filtered.count else { return }
        onSelect(filtered[selectedIndex].id)
        onDismiss()
    }
}
