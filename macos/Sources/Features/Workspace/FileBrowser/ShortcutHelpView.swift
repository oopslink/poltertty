// macos/Sources/Features/Workspace/FileBrowser/ShortcutHelpView.swift
import SwiftUI

struct ShortcutHelpView: View {
    var onDismiss: () -> Void

    private struct ShortcutItem: Identifiable {
        let id = UUID()
        let keys: String
        let description: String
    }

    private struct ShortcutSection: Identifiable {
        let id = UUID()
        let title: String
        let items: [ShortcutItem]
    }

    private let sections: [ShortcutSection] = [
        ShortcutSection(title: "Navigation", items: [
            ShortcutItem(keys: "↑ / ↓", description: "Select Up/Down"),
            ShortcutItem(keys: "Return", description: "Expand/Collapse Directory"),
        ]),
        ShortcutSection(title: "File Operations", items: [
            ShortcutItem(keys: "n", description: "New File"),
            ShortcutItem(keys: "N", description: "New Directory"),
            ShortcutItem(keys: "r", description: "Rename"),
            ShortcutItem(keys: "⌘⌫", description: "Delete"),
            ShortcutItem(keys: "o", description: "Show in Finder"),
            ShortcutItem(keys: "t", description: "Open in Terminal"),
        ]),
        ShortcutSection(title: "Search & View", items: [
            ShortcutItem(keys: "⌘F", description: "Filter Files"),
            ShortcutItem(keys: ".", description: "Toggle Hidden Files"),
            ShortcutItem(keys: "Space", description: "Toggle Preview"),
            ShortcutItem(keys: "⌘⇧C", description: "Copy Path"),
            ShortcutItem(keys: "⌘A", description: "Select All"),
        ]),
        ShortcutSection(title: "Help", items: [
            ShortcutItem(keys: "?", description: "Show/Hide This Panel"),
        ]),
    ]

    var body: some View {
        ZStack {
            // 点击背景关闭
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            // 面板
            VStack(alignment: .leading, spacing: 0) {
                // 标题栏
                HStack {
                    Text("Keyboard Shortcuts")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                Divider()

                // 快捷键列表
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(section.title)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 16)

                                ForEach(section.items) { item in
                                    HStack(spacing: 0) {
                                        Text(item.keys)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.primary)
                                            .frame(width: 80, alignment: .leading)
                                        Text(item.description)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
            .frame(width: 280)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 8)
        }
    }
}
