import SwiftUI

struct TerminalTabItem: View {
    let tab: TabItem
    let accentColor: Color
    let isLastTab: Bool        // 最后一个 tab 时不显示关闭按钮
    let onSelect: () -> Void
    let onClose: () -> Void
    let onRename: (String) -> Void
    let onCloseOthers: () -> Void

    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 4) {
                if isRenaming {
                    TextField("", text: $renameText)
                        .font(.system(size: 12))
                        .textFieldStyle(.plain)
                        .frame(minWidth: 40, maxWidth: 120)
                        .focused($renameFocused)
                        .onSubmit { commitRename() }
                        .backport.onKeyPress(.escape) { _ in
                            cancelRename()
                            return .handled
                        }
                } else {
                    Text(tab.title)
                        .font(.system(size: 12))
                        .foregroundColor(tab.isActive ? .primary : .secondary)
                        .lineLimit(1)
                        // 正确的双击 + 单击共存模式
                        .gesture(
                            TapGesture(count: 2).onEnded { startRename() }
                        )
                        .simultaneousGesture(
                            TapGesture(count: 1).onEnded { onSelect() }
                        )
                }

                if isHovered && !isRenaming && !isLastTab {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 14, height: 14)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Color.clear)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .contextMenu {
                Button("重命名") { startRename() }
                Divider()
                Button("关闭标签页") { onClose() }
                if !isLastTab {
                    Button("关闭其他标签页") { onCloseOthers() }
                }
            }
            .draggable(tab.id.uuidString)

            // 底部 2px 指示条（选中时显示）
            if tab.isActive {
                Rectangle()
                    .fill(accentColor)
                    .frame(height: 2)
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 60)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: tab.isActive)
    }

    private func startRename() {
        renameText = tab.title
        isRenaming = true
        renameFocused = true
    }

    private func commitRename() {
        isRenaming = false
        renameFocused = false
        onRename(renameText)
    }

    private func cancelRename() {
        isRenaming = false
        renameFocused = false
        // 不调用 onRename，保持原标题
    }
}
