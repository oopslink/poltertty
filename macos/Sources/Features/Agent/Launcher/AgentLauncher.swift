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
enum ClaudePermissionMode: String, CaseIterable {
    case `default`          // 标准模式，遇到危险操作弹确认
    case acceptEdits        // 自动接受文件编辑，其余仍弹确认
    case dontAsk            // 不询问权限，但不完全绕过
    case plan               // 规划模式，只分析不执行
    case auto               // 自动模式
    case bypassPermissions  // 跳过所有权限确认

    var displayName: String {
        switch self {
        case .default:          return "Default"
        case .acceptEdits:      return "Accept Edits"
        case .dontAsk:          return "Don't Ask"
        case .plan:             return "Plan"
        case .auto:             return "Auto"
        case .bypassPermissions: return "Bypass"
        }
    }

    /// 注入到 claude 命令的 flag，nil 表示不需要额外 flag
    var flag: String? {
        switch self {
        case .default: return nil
        default:       return "--permission-mode \(rawValue)"
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
            // currentPane 需要主动把焦点送回 terminal，因为打开 launch 菜单会把焦点移走
            if location == .currentPane {
                tc.focusSurface(targetSurface)
            }
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
