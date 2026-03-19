// macos/Sources/Features/Agent/Launcher/AgentLauncher.swift
import Foundation
import GhosttyKit

/// Agent 启动位置
enum AgentLaunchLocation: CaseIterable, Equatable, Hashable {
    case currentPane
    case newTab
    case splitRight
    case splitBottom

    var displayName: String {
        switch self {
        case .currentPane: return "Current Pane"
        case .newTab:      return "New Tab"
        case .splitRight:  return "Split Right"
        case .splitBottom: return "Split Bottom"
        }
    }
}

/// Claude Code 权限模式（仅对 hookCapability == .full 的 agent 有效）
enum ClaudePermissionMode: CaseIterable {
    case `default`      // 标准模式，遇到危险操作弹确认
    case allowBypass    // 允许 Claude 自行申请跳过确认
    case skipAll        // 跳过所有权限确认（--dangerously-skip-permissions）

    var displayName: String {
        switch self {
        case .default:     return "Default"
        case .allowBypass: return "Allow Bypass"
        case .skipAll:     return "Skip All"
        }
    }

    /// 注入到 claude 命令的 flag，nil 表示不需要额外 flag
    var flag: String? {
        switch self {
        case .default:     return nil
        case .allowBypass: return "--permission-mode allow-bypass-permissions"
        case .skipAll:     return "--dangerously-skip-permissions"
        }
    }
}

/// 负责在指定位置启动 Agent 的控制器
@MainActor
final class AgentLauncher {
    private weak var terminalController: TerminalController?

    init(terminalController: TerminalController) {
        self.terminalController = terminalController
    }

    func launch(
        definition: AgentDefinition,
        location: AgentLaunchLocation,
        permissionMode: ClaudePermissionMode,
        workspaceId: UUID,
        cwd: String
    ) {
        guard let tc = terminalController else { return }

        // 1. 获取目标 surface
        let surfaceView: Ghostty.SurfaceView?
        switch location {
        case .currentPane:
            surfaceView = tc.focusedSurface

        case .newTab:
            tc.addNewTab()
            surfaceView = tc.tabBarViewModel.activeSurface

        case .splitRight:
            guard let focused = tc.focusedSurface else { return }
            surfaceView = tc.newSplit(at: focused, direction: .right)

        case .splitBottom:
            guard let focused = tc.focusedSurface else { return }
            surfaceView = tc.newSplit(at: focused, direction: .down)
        }

        guard let targetSurface = surfaceView else { return }

        // 2. 注册 AgentSession
        let expandedCwd = (cwd as NSString).expandingTildeInPath
        let normalizedCwd = URL(fileURLWithPath: expandedCwd).resolvingSymlinksInPath().path
        let session = AgentSession(
            id: UUID(),
            surfaceId: targetSurface.id,
            definition: definition,
            workspaceId: workspaceId,
            cwd: normalizedCwd
        )
        AgentService.shared.sessionManager.register(session)

        // 3. 注入 hooks（仅 .full capability）
        if definition.hookCapability == .full {
            AgentService.shared.injectHooks(for: normalizedCwd)
        }

        // 4. 写入启动命令
        let command = buildLaunchCommand(
            definition: definition,
            cwd: normalizedCwd,
            permissionMode: definition.hookCapability == .full ? permissionMode : .default
        )
        guard let surfaceModel = targetSurface.surfaceModel else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            surfaceModel.sendText(command)
        }
    }

    // MARK: - Private

    private func buildLaunchCommand(
        definition: AgentDefinition,
        cwd: String,
        permissionMode: ClaudePermissionMode
    ) -> String {
        let escapedCwd = Ghostty.Shell.escape(cwd)
        let flagPart = permissionMode.flag.map { " \($0)" } ?? ""
        return "cd \(escapedCwd) && \(definition.command)\(flagPart)\n"
    }
}
