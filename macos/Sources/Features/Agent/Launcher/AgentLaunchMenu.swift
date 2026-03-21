// macos/Sources/Features/Agent/Launcher/AgentLaunchMenu.swift
import SwiftUI

struct AgentLaunchMenu: View {
    @ObservedObject private var registry = AgentRegistry.shared
    @State private var location: AgentLaunchLocation = .newTab
    @State private var permissionMode: ClaudePermissionMode = .default
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

    /// 是否存在支持 hooks 的 agent（用于决定是否显示 Permission 选项）
    private var hasFullHookAgents: Bool {
        registry.definitions.contains { $0.hookCapability == .full }
    }

    var body: some View {
        VStack(spacing: 0) {
            controlsHeader
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

    // MARK: - Controls Header

    private var controlsHeader: some View {
        VStack(spacing: 0) {
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

            if hasFullHookAgents {
                Divider()
                HStack {
                    Text("Permission").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $permissionMode) {
                        ForEach(ClaudePermissionMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.system(size: 11))
                    .foregroundStyle(permissionModeColor(permissionMode))
                    .fixedSize()
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
            }
        }
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
                    AgentRow(agent: agent).contentShape(Rectangle())
                        .onTapGesture { launch(agent) }
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

    // MARK: - Actions

    private func launch(_ agent: AgentDefinition) {
        let effectivePermission = agent.hookCapability == .full ? permissionMode : .default
        onLaunch(agent, location, effectivePermission)
    }

    private func permissionModeColor(_ mode: ClaudePermissionMode) -> Color {
        switch mode {
        case .auto:             return .orange
        case .bypassPermissions: return .red
        default:                return .accentColor
        }
    }
}

private struct AgentRow: View {
    let agent: AgentDefinition
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            AgentIconBadge(agent: agent)
            VStack(alignment: .leading, spacing: 1) {
                Text(agent.name).font(.system(size: 13))
                Text(agent.command).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            hookBadge
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(hovered ? Color(.selectedContentBackgroundColor).opacity(0.3) : .clear)
        .onHover { hovered = $0 }
    }

    @ViewBuilder private var hookBadge: some View {
        switch agent.hookCapability {
        case .full:
            Text("hooks").font(.system(size: 10)).padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.green.opacity(0.15)).foregroundStyle(.green)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        case .commandOnly:
            Text("cmd").font(.system(size: 10)).padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.yellow.opacity(0.15)).foregroundStyle(.yellow)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        case .none:
            EmptyView()
        }
    }
}
