// macos/Sources/Features/Agent/Launcher/AgentLaunchMenu.swift
import SwiftUI

/// 键盘导航区域
private enum NavSection {
    case search, location, agentList
}

struct AgentLaunchMenu: View {
    @ObservedObject private var registry = AgentRegistry.shared
    @State private var location: AgentLaunchLocation = .newTab
    /// 每个 agent 独立的 permission mode（仅 .full hook agent 使用）
    @State private var permissionModes: [String: ClaudePermissionMode] = [:]
    @State private var searchText = ""

    /// 当前键盘导航区域
    @State private var navSection: NavSection = .search
    /// agent 列表中当前高亮行（nil 表示无选中）
    @State private var selectedIndex: Int? = nil
    @FocusState private var searchFocused: Bool

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
        }
        .frame(width: 340)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 16)
        .backport.onKeyPress(.tab) { _ in handleTab(); return .handled }
        .backport.onKeyPress(.downArrow) { _ in handleDown(); return .handled }
        .backport.onKeyPress(.upArrow) { _ in handleUp(); return .handled }
        .backport.onKeyPress(.leftArrow) { _ in handleLeft() }
        .backport.onKeyPress(.rightArrow) { _ in handleRight() }
        .backport.onKeyPress(.return) { _ in handleReturn(); return .handled }
        .backport.onKeyPress(.escape) { _ in onCancel(); return .handled }
        .onAppear { searchFocused = true }
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
        // 当 location 区域被键盘聚焦时，高亮显示
        .background(navSection == .location ? Color.accentColor.opacity(0.08) : .clear)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    navSection == .location ? Color.accentColor.opacity(0.4) : .clear,
                    lineWidth: 1
                )
                .padding(.horizontal, 6).padding(.vertical, 3)
        )
        .animation(.easeInOut(duration: 0.1), value: navSection)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search agents...", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onChange(of: searchText) { _ in
                    // 搜索内容变化时重置列表选中
                    selectedIndex = nil
                    if navSection == .agentList { navSection = .search }
                }
        }
        .padding(10)
    }

    // MARK: - Agent List

    private var agentList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered.indices, id: \.self) { index in
                        AgentRow(
                            agent: filtered[index],
                            permissionMode: permissionBinding(for: filtered[index]),
                            isSelected: selectedIndex == index,
                            onLaunch: { launch(filtered[index]) }
                        )
                        .id(index)
                    }
                }
            }
            .frame(maxHeight: 220)
            .onChange(of: selectedIndex) { idx in
                if let idx { proxy.scrollTo(idx, anchor: .center) }
            }
        }
    }

    // MARK: - 键盘导航处理

    private func handleTab() {
        switch navSection {
        case .search:
            navSection = .location
        case .location:
            if !filtered.isEmpty {
                navSection = .agentList
                if selectedIndex == nil { selectedIndex = 0 }
            } else {
                navSection = .search
            }
        case .agentList:
            navSection = .search
            selectedIndex = nil
        }
    }

    private func handleDown() {
        switch navSection {
        case .search:
            if !filtered.isEmpty {
                navSection = .agentList
                selectedIndex = 0
            }
        case .location:
            cycleLocation(forward: true)
        case .agentList:
            if let idx = selectedIndex, idx < filtered.count - 1 {
                selectedIndex = idx + 1
            }
        }
    }

    private func handleUp() {
        switch navSection {
        case .search:
            break
        case .location:
            cycleLocation(forward: false)
        case .agentList:
            if let idx = selectedIndex {
                if idx > 0 {
                    selectedIndex = idx - 1
                } else {
                    // 回到搜索区域
                    navSection = .search
                    selectedIndex = nil
                }
            }
        }
    }

    private func handleReturn() {
        guard navSection == .agentList, let idx = selectedIndex, idx < filtered.count else { return }
        launch(filtered[idx])
    }

    private func handleLeft() -> BackportKeyPressResult {
        guard navSection == .agentList,
              let idx = selectedIndex, idx < filtered.count,
              filtered[idx].hookCapability == .full
        else { return .ignored }
        cyclePermission(for: filtered[idx], forward: false)
        return .handled
    }

    private func handleRight() -> BackportKeyPressResult {
        guard navSection == .agentList,
              let idx = selectedIndex, idx < filtered.count,
              filtered[idx].hookCapability == .full
        else { return .ignored }
        cyclePermission(for: filtered[idx], forward: true)
        return .handled
    }

    private func cyclePermission(for agent: AgentDefinition, forward: Bool) {
        let all = ClaudePermissionMode.allCases
        let current = permissionModes[agent.id] ?? .default
        guard let i = all.firstIndex(of: current) else { return }
        let next = forward ? (i + 1) % all.count : (i - 1 + all.count) % all.count
        permissionModes[agent.id] = all[next]
    }

    private func cycleLocation(forward: Bool) {
        let all = AgentLaunchLocation.allCases
        guard let current = all.firstIndex(of: location) else { return }
        let next = forward
            ? (current + 1) % all.count
            : (current - 1 + all.count) % all.count
        location = all[next]
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
    let isSelected: Bool
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
                HStack(spacing: 2) {
                    // 键盘模式时显示 ← → 提示
                    if isSelected {
                        Text("←")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    Picker("", selection: $permissionMode) {
                        ForEach(ClaudePermissionMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.system(size: 10))
                    .foregroundStyle(permissionModeColor(permissionMode))
                    .fixedSize()
                    if isSelected {
                        Text("→")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.trailing, 12)
            }
        }
        .background(
            isSelected
                ? Color(.selectedContentBackgroundColor).opacity(0.5)
                : (hovered ? Color(.selectedContentBackgroundColor).opacity(0.3) : .clear)
        )
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
