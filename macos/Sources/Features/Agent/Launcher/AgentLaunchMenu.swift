// macos/Sources/Features/Agent/Launcher/AgentLaunchMenu.swift
import SwiftUI

struct AgentLaunchMenu: View {
    @ObservedObject private var registry = AgentRegistry.shared
    @State private var step: Step = .selectAgent
    @State private var selectedAgent: AgentDefinition?
    @State private var location: AgentLaunchLocation = .newTab
    @State private var permissionMode: ClaudePermissionMode = .default
    @State private var searchText = ""

    let workspaceId: UUID
    let cwd: String
    let onLaunch: (AgentDefinition, AgentLaunchLocation, ClaudePermissionMode) -> Void
    let onCancel: () -> Void

    enum Step { case selectAgent, selectLocation }

    private var filtered: [AgentDefinition] {
        guard !searchText.isEmpty else { return registry.definitions }
        return registry.definitions.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.command.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case .selectAgent:    agentSelection
            case .selectLocation: locationSelection
            }
        }
        .frame(width: 340)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 16)
    }

    // MARK: - Step 1

    private var agentSelection: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search agents...", text: $searchText).textFieldStyle(.plain)
            }
            .padding(10)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { agent in
                        AgentRow(agent: agent).contentShape(Rectangle())
                            .onTapGesture { pick(agent) }
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    private func pick(_ agent: AgentDefinition) {
        selectedAgent = agent
        permissionMode = .default
        if registry.definitions.count == 1 {
            onLaunch(agent, location, permissionMode)
        } else {
            step = .selectLocation
        }
    }

    // MARK: - Step 2

    private var locationSelection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Button { step = .selectAgent } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                Text("Launch \(selectedAgent?.name ?? "")").font(.system(size: 13, weight: .semibold))
            }
            .padding(12)
            Divider()

            // Location
            VStack(spacing: 0) {
                ForEach(AgentLaunchLocation.allCases, id: \.self) { loc in
                    HStack(spacing: 8) {
                        Image(systemName: location == loc ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 13))
                            .foregroundStyle(location == loc ? Color.accentColor : .secondary)
                        Text(loc.displayName).font(.system(size: 12))
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .onTapGesture { location = loc }
                }
            }
            .padding(.vertical, 2)

            // Permission（仅 .full agent）
            if selectedAgent?.hookCapability == .full {
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

            Divider()
            HStack {
                Button("Cancel") { onCancel() }.keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button("Launch") {
                    if let a = selectedAgent { onLaunch(a, location, permissionMode) }
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
    }

    private func permissionModeColor(_ mode: ClaudePermissionMode) -> Color {
        switch mode {
        case .default:          return .accentColor
        case .acceptEdits:      return .accentColor
        case .dontAsk:          return .accentColor
        case .plan:             return .accentColor
        case .auto:             return .orange
        case .bypassPermissions: return .red
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
