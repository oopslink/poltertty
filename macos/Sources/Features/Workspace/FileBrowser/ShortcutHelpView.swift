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
        ShortcutSection(title: "导航", items: [
            ShortcutItem(keys: "↑ / ↓", description: "上下选择"),
            ShortcutItem(keys: "Return", description: "展开/折叠目录"),
        ]),
        ShortcutSection(title: "文件操作", items: [
            ShortcutItem(keys: "n", description: "新建文件"),
            ShortcutItem(keys: "N", description: "新建目录"),
            ShortcutItem(keys: "r", description: "重命名"),
            ShortcutItem(keys: "⌘⌫", description: "删除"),
            ShortcutItem(keys: "o", description: "在 Finder 中显示"),
            ShortcutItem(keys: "t", description: "在终端打开"),
        ]),
        ShortcutSection(title: "搜索与视图", items: [
            ShortcutItem(keys: "⌘F", description: "过滤文件"),
            ShortcutItem(keys: ".", description: "切换隐藏文件"),
            ShortcutItem(keys: "Space", description: "切换预览面板"),
            ShortcutItem(keys: "⌘⇧C", description: "复制路径"),
            ShortcutItem(keys: "⌘A", description: "全选"),
        ]),
        ShortcutSection(title: "帮助", items: [
            ShortcutItem(keys: "?", description: "显示/隐藏此面板"),
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
                    Text("快捷键")
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
