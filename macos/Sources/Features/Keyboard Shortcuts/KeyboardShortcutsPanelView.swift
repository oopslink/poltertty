import SwiftUI

/// 快捷键速查浮窗，双击 Shift 触发。
struct KeyboardShortcutsPanelView: View {
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            // 半透明背景遮罩，点击关闭
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                // 标题栏
                HStack {
                    Text("快捷键速查")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ShortcutGroup(title: "面板切换", items: [
                            ShortcutItem("切换 Sidebar", "⌥⌘P"),
                            ShortcutItem("切换 File Browser", "⌥⌘F"),
                            ShortcutItem("Shell Popup", "⌥⌘J"),
                            ShortcutItem("Lazygit Popup", "⌥⌘G"),
                        ])
                        ShortcutGroup(title: "Command Palette", items: [
                            ShortcutItem("Command Palette", "⌘⇧P"),
                            ShortcutItem("快捷键速查（本面板）", "Shift × 2"),
                        ])
                        ShortcutGroup(title: "Agent", items: [
                            ShortcutItem("Launch Agent", "⌥⌘A"),
                            ShortcutItem("Agent Monitor", "⌥⌘M"),
                            ShortcutItem("Agent Dashboard", "⌥⌘D"),
                            ShortcutItem("Notification Center", "⌥⌘N"),
                            ShortcutItem("Ctrl Monitor", "⌥⌘C"),
                        ])
                        ShortcutGroup(title: "Workspace", items: [
                            ShortcutItem("上一个 Workspace", "⌘⇧["),
                            ShortcutItem("下一个 Workspace", "⌘⇧]"),
                            ShortcutItem("新建 Workspace", "⌘⇧N"),
                        ])
                        ShortcutGroup(title: "分屏 / Tab", items: [
                            ShortcutItem("向右分屏", "⌘D"),
                            ShortcutItem("向下分屏", "⌘⇧D"),
                            ShortcutItem("新建 Tab", "⌘T"),
                            ShortcutItem("关闭分屏", "⌘W"),
                            ShortcutItem("New Tab (tmux)", "⌥⌘T"),
                        ])
                    }
                    .padding(20)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .frame(width: 480, height: 520)
            .shadow(radius: 24)
        }
    }
}

// MARK: - 子组件

private struct ShortcutGroup: View {
    let title: String
    let items: [ShortcutItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.label)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(item.shortcut)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                }
            }
            .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct ShortcutItem {
    let label: String
    let shortcut: String
    init(_ label: String, _ shortcut: String) {
        self.label = label
        self.shortcut = shortcut
    }
}
