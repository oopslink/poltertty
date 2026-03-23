// macos/Sources/Features/Splits/PaneSelectorViewModel.swift
import AppKit
import Carbon
import Combine
import OSLog

extension Notification.Name {
    static let togglePaneSelector = Notification.Name("poltertty.togglePaneSelector")
}

/// 管理 pane 选择模式的状态：激活/停用、编号分配、键盘事件拦截。
@MainActor
final class PaneSelectorViewModel: ObservableObject {
    static let shared = PaneSelectorViewModel()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "PaneSelectorViewModel"
    )

    @Published var isActive: Bool = false
    /// surfaceId → 0-indexed pane 序号（0-35）
    @Published var assignments: [UUID: Int] = [:]

    private var keyMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []
    private var activeWindow: NSWindow?
    private var activeLeaves: [Ghostty.SurfaceView] = []

    private init() {
        // 监听双击 Cmd 通知
        NotificationCenter.default.publisher(for: .togglePaneSelector)
            .sink { [weak self] notification in
                guard let self else { return }
                if self.isActive {
                    self.deactivate()
                } else {
                    self.activate(for: notification.object as? NSWindow)
                }
            }
            .store(in: &cancellables)

        // 窗口失焦时自动取消
        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)
            .sink { [weak self] _ in
                guard let self, self.isActive else { return }
                self.deactivate()
            }
            .store(in: &cancellables)
    }

    // MARK: - 编号标签

    /// 将 0-indexed 序号转换为显示标签："0"…"9"，"a"…"z"，超出范围返回 "?"
    static func label(for index: Int) -> String {
        guard index >= 0 else { return "?" }
        if index <= 9 { return "\(index)" }
        guard index <= 35 else { return "?" }
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        return String(letters[index - 10])
    }

    // MARK: - 激活/停用

    private func activate(for window: NSWindow?) {
        guard !isActive else { return }

        self.activeWindow = window

        // 从 keyWindow 取当前 tab 的 TerminalController
        // native tab 模式下每个 tab 是独立 NSWindow，keyWindow 就是当前 tab
        guard let controller = window?.windowController as? TerminalController else {
            Self.logger.warning("activate: no TerminalController for window")
            return
        }

        // 枚举可见 pane（zoom 模式下只有 1 个）
        let visibleNode = controller.surfaceTree.zoomed ?? controller.surfaceTree.root
        let leaves = visibleNode?.leaves() ?? []

        guard !leaves.isEmpty else { return }

        // 建立 surfaceId → 0-indexed 编号映射
        var newAssignments: [UUID: Int] = [:]
        for (index, surface) in leaves.prefix(36).enumerated() {
            newAssignments[surface.id] = index
        }

        assignments = newAssignments
        activeLeaves = leaves
        isActive = true

        // 注册 keyDown monitor（必须保存引用以便移除）
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }

        Self.logger.debug("activated with \(leaves.count) panes")
    }

    func deactivate() {
        isActive = false
        assignments = [:]
        activeLeaves = []
        activeWindow = nil
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        Self.logger.debug("deactivated")
    }

    // MARK: - 键盘事件处理

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        // Esc → 取消（有意消费，选择模式期间不透传给终端）
        if event.keyCode == UInt16(kVK_Escape) {
            deactivate()
            return nil
        }

        guard let char = event.charactersIgnoringModifiers?.lowercased().first else {
            return event
        }

        let index: Int?
        switch char {
        case "0"..."9":
            index = Int(String(char))
        case "a"..."z":
            if let charVal = char.asciiValue, let baseVal = Character("a").asciiValue {
                index = Int(charVal - baseVal) + 10
            } else {
                return event
            }
        default:
            return event  // 其他键透传
        }

        guard let idx = index,
              let surfaceId = assignments.first(where: { $0.value == idx })?.key,
              let surface = findSurface(id: surfaceId) else {
            return event
        }

        Ghostty.moveFocus(to: surface)
        deactivate()
        return nil  // 消费事件
    }

    private func findSurface(id: UUID) -> Ghostty.SurfaceView? {
        return activeLeaves.first(where: { $0.id == id })
    }
}
