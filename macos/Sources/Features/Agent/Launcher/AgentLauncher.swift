// macos/Sources/Features/Agent/Launcher/AgentLauncher.swift
import Foundation
import GhosttyKit

/// Agent 启动位置
enum AgentLaunchLocation: CaseIterable, Equatable, Hashable {
    /// 在当前活跃 pane 启动
    case currentPane
    /// 新建 tab 后启动
    case newTab
    /// 向右 split 后启动
    case splitRight
    /// 向下 split 后启动
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

/// 负责在指定位置启动 Agent 的控制器
@MainActor
final class AgentLauncher {
    private weak var terminalController: TerminalController?

    init(terminalController: TerminalController) {
        self.terminalController = terminalController
    }

    /// 在指定位置启动 Agent
    ///
    /// 步骤：
    /// 1. 根据 location 确定目标 SurfaceView（currentPane / 新 tab / split）
    /// 2. 向 AgentSessionManager 注册 AgentSession
    /// 3. 如果 hookCapability == .full，注入 hooks
    /// 4. 向 PTY 写入启动命令
    func launch(
        definition: AgentDefinition,
        location: AgentLaunchLocation,
        respawnMode: RespawnMode,
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
            surfaceView = tc.newSplit(
                at: focused,
                direction: .right
            )

        case .splitBottom:
            guard let focused = tc.focusedSurface else { return }
            surfaceView = tc.newSplit(
                at: focused,
                direction: .down
            )
        }

        guard let targetSurface = surfaceView else { return }

        // 2. 注册 AgentSession（解析 symlink，保证与 Claude Code hook payload 的 cwd 一致）
        // macOS 上 /Users 是 /private/Users 的符号链接，Claude Code 在 hook 中报告的是解析后的路径
        let expandedCwd = (cwd as NSString).expandingTildeInPath
        let normalizedCwd = URL(fileURLWithPath: expandedCwd).resolvingSymlinksInPath().path
        let session = AgentSession(
            id: UUID(),
            surfaceId: targetSurface.id,
            definition: definition,
            workspaceId: workspaceId,
            cwd: normalizedCwd,
            respawnMode: respawnMode
        )
        AgentService.shared.sessionManager.register(session)

        // 3. 注入 hooks（仅 .full capability）
        if definition.hookCapability == .full {
            AgentService.shared.injectHooks(for: normalizedCwd)
        }

        // 4. 写入启动命令（cd + 命令），使用异步延迟确保 surface 已就绪
        let command = buildLaunchCommand(definition: definition, cwd: normalizedCwd)
        guard let surfaceModel = targetSurface.surfaceModel else { return }
        // 对于新 tab/split，surface 初始化需要一个 run-loop 才能完全就绪
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            surfaceModel.sendText(command)
        }
    }

    // MARK: - Private Helpers

    private func buildLaunchCommand(definition: AgentDefinition, cwd: String) -> String {
        let escapedCwd = Ghostty.Shell.escape(cwd)
        return "cd \(escapedCwd) && \(definition.command)\n"
    }
}
