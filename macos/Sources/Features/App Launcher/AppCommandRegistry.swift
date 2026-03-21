import AppKit
import SwiftUI

/// 收集所有可用命令，供 AppLauncherView 使用。
/// 每次调用 refresh() 时重新扫描菜单（须在 @MainActor 执行）。
@MainActor
final class AppCommandRegistry: ObservableObject {
    static let shared = AppCommandRegistry()

    @Published private(set) var commands: [CommandOption] = []

    private init() {}

    /// 重新扫描所有命令来源。在 AppLauncherView.onAppear 中调用。
    func refresh() {
        var result: [CommandOption] = []
        result += scanMenuItems()
        result += polterttyActions()
        commands = result
    }

    // MARK: - macOS 菜单项扫描

    private func scanMenuItems() -> [CommandOption] {
        guard let mainMenu = NSApp.mainMenu else { return [] }
        return collectItems(from: mainMenu)
    }

    private func collectItems(from menu: NSMenu) -> [CommandOption] {
        var result: [CommandOption] = []
        for item in menu.items {
            guard !item.isSeparatorItem else { continue }
            if let submenu = item.submenu {
                result += collectItems(from: submenu)
            } else if let action = item.action, item.isEnabled {
                let symbols = keyEquivalentSymbols(for: item)
                result.append(CommandOption(
                    title: item.title,
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
                    NotificationCenter.default.post(name: .toggleWorkspaceSidebar, object: nil)
                }
            ),
            CommandOption(
                title: "切换文件浏览器",
                subtitle: "File Browser",
                leadingIcon: "folder",
                action: {
                    NotificationCenter.default.post(name: .toggleFileBrowser, object: nil)
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
}
