import AppKit
import Combine
import GhosttyKit
import SwiftUI

/// 收集所有可用命令，供 AppLauncherView 使用。
/// 每次调用 refresh() 时重新扫描菜单（须在 @MainActor 执行）。
@MainActor
final class AppCommandRegistry: ObservableObject {
    static let shared = AppCommandRegistry()

    @Published private(set) var commands: [CommandOption] = []

    private init() {}

    /// 重新扫描所有命令来源。在 AppLauncherView.onAppear 中调用。
    /// - Parameters:
    ///   - surface: 当前聚焦的终端 surface，用于注入 terminal 命令
    ///   - performAction: 执行 Ghostty 动作的回调，接受 action 字符串和目标 surface
    ///   - ghosttyConfig: Ghostty 配置，用于读取 command-palette-entry
    func refresh(
        surface: Ghostty.SurfaceView? = nil,
        performAction: ((String, Ghostty.SurfaceView) -> Void)? = nil,
        ghosttyConfig: Ghostty.Config? = nil
    ) {
        var result: [CommandOption] = []
        result += scanMenuItems()
        result += polterttyActions()
        if let surface, let performAction, let config = ghosttyConfig {
            result += terminalCommands(surface: surface, performAction: performAction, config: config)
        }
        commands = result
    }

    // MARK: - macOS 菜单项扫描

    private func scanMenuItems() -> [CommandOption] {
        guard let mainMenu = NSApp.mainMenu else { return [] }
        return collectItems(from: mainMenu, path: [])
    }

    private func collectItems(from menu: NSMenu, path: [String]) -> [CommandOption] {
        var result: [CommandOption] = []
        for item in menu.items {
            guard !item.isSeparatorItem, !item.title.isEmpty else { continue }
            if let submenu = item.submenu {
                result += collectItems(from: submenu, path: path + [item.title])
            } else if let action = item.action, item.isEnabled {
                let symbols = keyEquivalentSymbols(for: item)
                let subtitle = path.isEmpty ? nil : path.joined(separator: " › ")
                result.append(CommandOption(
                    title: item.title,
                    subtitle: subtitle,
                    symbols: symbols.isEmpty ? nil : symbols,
                    leadingIcon: "menubar.rectangle",
                    action: {
                        NSApp.sendAction(action, to: item.target, from: item)
                    }
                ))
            }
        }
        return result
    }

    /// 将 NSMenuItem 的 keyEquivalent + modifiers 转换为符号字符串数组
    private func keyEquivalentSymbols(for item: NSMenuItem) -> [String] {
        guard !item.keyEquivalent.isEmpty else { return [] }
        var symbols: [String] = []
        let mods = item.keyEquivalentModifierMask
        if mods.contains(.command) { symbols.append("⌘") }
        if mods.contains(.shift) { symbols.append("⇧") }
        if mods.contains(.option) { symbols.append("⌥") }
        if mods.contains(.control) { symbols.append("⌃") }
        symbols.append(item.keyEquivalent.uppercased())
        return symbols
    }

    // MARK: - Poltertty 本地 actions

    private func polterttyActions() -> [CommandOption] {
        [
            CommandOption(
                title: "切换侧边栏",
                subtitle: "Workspace Sidebar",
                leadingIcon: "sidebar.left",
                action: {
                    guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
                    NotificationCenter.default.post(name: .toggleWorkspaceSidebar, object: window)
                }
            ),
            CommandOption(
                title: "切换文件浏览器",
                subtitle: "File Browser",
                leadingIcon: "folder",
                action: {
                    guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
                    NotificationCenter.default.post(name: .toggleFileBrowser, object: window)
                }
            ),
            CommandOption(
                title: "切换 Workspace",
                subtitle: "Quick Switcher",
                leadingIcon: "square.stack",
                action: {
                    NotificationCenter.default.post(name: .toggleWorkspaceQuickSwitcher, object: nil)
                }
            ),
            CommandOption(
                title: "打开 Agent Monitor",
                subtitle: "Agent Monitor",
                leadingIcon: "cpu",
                action: {
                    NotificationCenter.default.post(name: .toggleAgentMonitor, object: nil)
                }
            ),
            CommandOption(
                title: "tmux Session 选择",
                subtitle: "Tmux Session Picker",
                leadingIcon: "terminal",
                action: {
                    NotificationCenter.default.post(name: .showTmuxSessionPicker, object: nil)
                }
            ),
        ]
    }

    // MARK: - Terminal 命令（跳转 + Ghostty config 动作）

    /// 生成终端相关命令：jump to surface + command-palette-entry 动作。
    private func terminalCommands(
        surface: Ghostty.SurfaceView,
        performAction: @escaping (String, Ghostty.SurfaceView) -> Void,
        config: Ghostty.Config
    ) -> [CommandOption] {
        var result: [CommandOption] = []

        // 跳转到其他终端 surface
        let jumpOptions: [CommandOption] = TerminalController.all.flatMap { controller -> [CommandOption] in
            guard let window = controller.window else { return [] }
            let color = (window as? TerminalWindow)?.tabColor
            let displayColor = color != TerminalTabColor.none ? color : nil

            return controller.surfaceTree.map { s in
                let terminalTitle = s.title.isEmpty ? window.title : s.title
                let displayTitle: String
                if let override = controller.titleOverride, !override.isEmpty {
                    displayTitle = override
                } else if !terminalTitle.isEmpty {
                    displayTitle = terminalTitle
                } else {
                    displayTitle = "Untitled"
                }
                let pwd = s.pwd?.abbreviatedPath
                let subtitle: String? = if let pwd, !displayTitle.contains(pwd) { pwd } else { nil }

                return CommandOption(
                    title: "Focus: \(displayTitle)",
                    subtitle: subtitle,
                    leadingIcon: "rectangle.on.rectangle",
                    leadingColor: displayColor?.displayColor.map { Color($0) },
                    sortKey: AnySortKey(ObjectIdentifier(s))
                ) {
                    NotificationCenter.default.post(
                        name: Ghostty.Notification.ghosttyPresentTerminal,
                        object: s
                    )
                }
            }
        }
        result += jumpOptions

        // Ghostty config command-palette-entry 命令
        let terminalOptions: [CommandOption] = config.commandPaletteEntries
            .filter(\.isSupported)
            .map { entry in
                let symbols = config.keyboardShortcut(for: entry.action)?.keyList
                return CommandOption(
                    title: entry.title,
                    description: entry.description.isEmpty ? nil : entry.description,
                    symbols: symbols,
                    leadingIcon: "terminal"
                ) {
                    performAction(entry.action, surface)
                }
            }
        result += terminalOptions

        return result
    }
}
