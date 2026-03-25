import SwiftUI

struct TerminalTabItem: View {
    let tab: TabItem
    let accentColor: Color
    let isLastTab: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onRename: (String) -> Void
    let onCloseOthers: () -> Void
    var agentState: AgentState? = nil
    var isNextActive: Bool = false
    var isLastVisible: Bool = false

    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool
    @State private var escapeMonitor: Any? = nil

    private static let tabWidth: CGFloat = 96
    private static let closeButtonWidth: CGFloat = 16

    var body: some View {
        ZStack(alignment: .bottom) {
            // 主内容区：固定宽度
            ZStack {
                if isRenaming {
                    TextField("", text: $renameText)
                        .font(.system(size: 12))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 8)
                        .focused($renameFocused)
                        .onSubmit { commitRename() }
                        .onChange(of: renameFocused) { focused in
                            if !focused && isRenaming { commitRename() }
                        }
                        .onAppear {
                            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                                if event.keyCode == 53 {
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
                    HStack(spacing: 4) {
                        if let state = agentState {
                            AgentStateDot(state: state)
                        }
                        Text(tab.title)
                            .font(.system(size: 12))
                            .foregroundColor(tab.isActive ? .primary : .secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(tab.title)
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, Self.closeButtonWidth + 4)
                }
            }
            .frame(width: Self.tabWidth, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(tab.isActive ? Color.primary.opacity(0.1) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
            )
            .contentShape(Rectangle())
            // 双击重命名（count:2 要在 count:1 之前）
            .onTapGesture(count: 2) { startRename() }
            // 单击切换 tab（onTapGesture 不会穿透到 overlay 中的 Button）
            .onTapGesture { onSelect() }
            // x 按钮固定在 tab 右侧边缘（overlay 在 onTapGesture 之上，Button 自然拦截点击）
            .overlay(alignment: .trailing) {
                if !isLastTab && !isRenaming {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(tab.isActive ? .primary.opacity(0.6) : .secondary.opacity(0.5))
                            .frame(width: Self.closeButtonWidth, height: Self.closeButtonWidth)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)
                }
            }
            .onHover { isHovered = $0 }
            .overlay(alignment: .trailing) {
                if !tab.isActive && !isNextActive && !isLastVisible {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(width: 0.5)
                        .padding(.vertical, 6)
                }
            }
            .contextMenu {
                Button("Rename") { startRename() }
                Divider()
                Button("Close Tab") { onClose() }
                if !isLastTab {
                    Button("Close Other Tabs") { onCloseOthers() }
                }
            }
            .draggable(tab.id.uuidString)

            // 底部指示条：active = accent 色，hover 非 active = 浅色
            if tab.isActive {
                Rectangle()
                    .fill(accentColor)
                    .frame(height: 2)
                    .transition(.opacity)
            } else if isHovered {
                Rectangle()
                    .fill(Color.primary.opacity(0.15))
                    .frame(height: 2)
                    .transition(.opacity)
            }
        }
        .frame(width: Self.tabWidth)
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
