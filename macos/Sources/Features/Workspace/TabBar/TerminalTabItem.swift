import SwiftUI

struct TerminalTabItem: View {
    let tab: TabItem
    let accentColor: Color
    let isLastTab: Bool        // 最后一个 tab 时不显示关闭按钮
    let onSelect: () -> Void
    let onClose: () -> Void
    let onRename: (String) -> Void
    let onCloseOthers: () -> Void
    var agentState: AgentState? = nil

    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool
    @State private var escapeMonitor: Any? = nil

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
                        .onAppear {
                            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                                if event.keyCode == 53 { // Escape key
                                    cancelRename()
                                    return nil
                                }
                                return event
                            }
                        }
                        .onDisappear {
                            if let monitor = escapeMonitor {
                                NSEvent.removeMonitor(monitor)
                                escapeMonitor = nil
                            }
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
                    if let state = agentState {
                        AgentStateDot(state: state)
                    }
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
        .animation(.easeInOut(duration: 0.1), value: isRenaming)
    }

    private func startRename() {
        renameText = tab.title
        isRenaming = true
        renameFocused = true
    }

    private func commitRename() {
        isRenaming = false
        renameFocused = false
        onRename(renameText.trimmingCharacters(in: .whitespaces))
    }

    private func cancelRename() {
        isRenaming = false
        renameFocused = false
        // 不调用 onRename，保持原标题
    }
}

struct AgentStateDot: View {
    let state: AgentState
    @State private var pulse = false

    var color: Color {
        switch state {
        case .launching: return .blue
        case .working:   return .green
        case .idle:      return .yellow
        case .error:     return .red
        case .done:      return .secondary
        }
    }

    var isWorking: Bool {
        if case .working = state { return true }
        return false
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(isWorking ? (pulse ? 1.0 : 0.35) : 1.0)
            .animation(
                isWorking
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: pulse
            )
            .onAppear { pulse = true }
    }
}
