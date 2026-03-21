// macos/Sources/Features/Agent/Launcher/AgentLaunchMenu.swift
import SwiftUI

struct AgentLaunchMenu: View {
    @ObservedObject private var registry = AgentRegistry.shared
    @State private var location: AgentLaunchLocation = .newTab
    /// 每个 agent 独立的 permission mode（仅 .full hook agent 使用）
    @State private var permissionModes: [String: ClaudePermissionMode] = [:]
    @State private var searchText = ""

    let workspaceId: UUID
    let cwd: String
    let onLaunch: (AgentDefinition, AgentLaunchLocation, ClaudePermissionMode) -> Void
    let onCancel: () -> Void

    private var filtered: [AgentDefinition] {
        guard !searchText.isEmpty else { return registry.definitions }
        return registry.definitions.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.command.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            locationHeader
            Divider()
            searchBar
            Divider()
            agentList
            Divider()
            cancelRow
        }
        .frame(width: 340)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 16)
    }

    // MARK: - Location Header

    private var locationHeader: some View {
        HStack {
            Text("Location").font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: $location) {
                ForEach(AgentLaunchLocation.allCases, id: \.self) { loc in
                    Text(loc.displayName).tag(loc)
                }
            }
            .pickerStyle(.menu)
            .font(.system(size: 11))
            .fixedSize()
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search agents...", text: $searchText).textFieldStyle(.plain)
        }
        .padding(10)
    }

    // MARK: - Agent List

    private var agentList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filtered) { agent in
                    AgentRow(
                        agent: agent,
                        permissionMode: permissionBinding(for: agent),
                        onLaunch: { launch(agent) }
                    )
                }
            }
        }
        .frame(maxHeight: 220)
    }

    // MARK: - Cancel Row

    private var cancelRow: some View {
        HStack {
            Button("Cancel") { onCancel() }
                .keyboardShortcut(.escape, modifiers: [])
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func permissionBinding(for agent: AgentDefinition) -> Binding<ClaudePermissionMode> {
        Binding(
            get: { permissionModes[agent.id] ?? .default },
            set: { permissionModes[agent.id] = $0 }
        )
    }

    private func launch(_ agent: AgentDefinition) {
        let permission: ClaudePermissionMode = agent.hookCapability == .full
            ? (permissionModes[agent.id] ?? .default)
            : .default
        onLaunch(agent, location, permission)
    }
}

// MARK: - AgentRow

private struct AgentRow: View {
    let agent: AgentDefinition
    @Binding var permissionMode: ClaudePermissionMode
    let onLaunch: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 0) {
            // 可点击的启动区域
            Button(action: onLaunch) {
                HStack(spacing: 10) {
                    AgentIconBadge(agent: agent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(agent.name).font(.system(size: 13))
                        Text(agent.command).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if agent.hookCapability != .full {
                        hookBadge
                    }
                }
                .padding(.leading, 12).padding(.trailing, agent.hookCapability == .full ? 6 : 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            // Permission 下拉框（仅 .full hook agent）
            if agent.hookCapability == .full {
                Picker("", selection: $permissionMode) {
                    ForEach(ClaudePermissionMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .font(.system(size: 10))
                .foregroundStyle(permissionModeColor(permissionMode))
                .fixedSize()
                .padding(.trailing, 12)
            }
        }
        .background(hovered ? Color(.selectedContentBackgroundColor).opacity(0.3) : .clear)
        .onHover { hovered = $0 }
    }

    @ViewBuilder private var hookBadge: some View {
        switch agent.hookCapability {
        case .commandOnly:
            Text("cmd").font(.system(size: 10)).padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.yellow.opacity(0.15)).foregroundStyle(.yellow)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        default:
            EmptyView()
        }
    }

    private func permissionModeColor(_ mode: ClaudePermissionMode) -> Color {
        switch mode {
        case .auto:              return .orange
        case .bypassPermissions: return .red
        default:                 return .secondary
        }
    }
}
