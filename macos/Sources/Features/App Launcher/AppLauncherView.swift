// macos/Sources/Features/App Launcher/AppLauncherView.swift
import SwiftUI

extension Notification.Name {
    /// App Launcher 触发通知。由 ShiftDoubleTapDetector post（object: NSApp.keyWindow）。
    static let toggleAppLauncher = Notification.Name("poltertty.toggleAppLauncher")
}

struct AppLauncherView: View {
    @Binding var isPresented: Bool
    var backgroundColor: Color = Color(nsColor: .windowBackgroundColor)

    @StateObject private var registry = AppCommandRegistry.shared
    @State private var query = ""
    @State private var selectedIndex: UInt?
    @State private var hoveredOptionID: UUID?
    @FocusState private var isTextFieldFocused: Bool

    var filteredOptions: [CommandOption] {
        EditDistanceFilter.rank(query, in: registry.commands)
    }

    var selectedOption: CommandOption? {
        guard let selectedIndex else { return nil }
        let opts = filteredOptions
        guard !opts.isEmpty else { return nil }
        return selectedIndex < opts.count ? opts[Int(selectedIndex)] : opts.last
    }

    var body: some View {
        let scheme: ColorScheme = if OSColor(backgroundColor).isLightColor {
            .light
        } else {
            .dark
        }

        // 全屏遮罩
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Launcher 面板（居中偏上）
            VStack {
                launcherPanel(scheme: scheme)
                    .frame(maxWidth: 500)
                    .padding(.top, 80)

                Spacer()
            }
        }
        .environment(\.colorScheme, scheme)
        .task {
            isTextFieldFocused = true
        }
        .onChange(of: isPresented) { newValue in
            isTextFieldFocused = newValue
            if !newValue { query = "" }
        }
    }

    @ViewBuilder
    private func launcherPanel(scheme: ColorScheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 输入框
            inputField

            // 结果列表
            if !filteredOptions.isEmpty {
                Divider()
                CommandTable(
                    options: filteredOptions,
                    selectedIndex: $selectedIndex,
                    hoveredOptionID: $hoveredOptionID
                ) { option in
                    dismiss()
                    option.action()
                }
            }
        }
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(backgroundColor).blendMode(.color)
            }
            .compositingGroup()
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .tertiaryLabelColor).opacity(0.75))
        )
        .shadow(radius: 32, x: 0, y: 12)
        .padding(.horizontal)
        .onAppear {
            Task { @MainActor in
                registry.refresh()
            }
        }
        .onChange(of: query) { newValue in
            if !newValue.isEmpty {
                if selectedIndex == nil { selectedIndex = 0 }
            } else {
                if selectedIndex == 0 { selectedIndex = nil }
            }
        }
    }

    private var inputField: some View {
        ZStack {
            // 键盘导航按钮（隐藏）
            Group {
                Button { moveSelection(-1) } label: { Color.clear }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.upArrow, modifiers: [])
                Button { moveSelection(1) } label: { Color.clear }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.downArrow, modifiers: [])
                Button { moveSelection(-1) } label: { Color.clear }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.init("p"), modifiers: [.control])
                Button { moveSelection(1) } label: { Color.clear }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.init("n"), modifiers: [.control])
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)

            TextField("输入想找的功能…", text: $query)
                .padding()
                .font(.system(size: 20, weight: .light))
                .frame(height: 48)
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .onChange(of: isTextFieldFocused) { focused in
                    if !focused { dismiss() }
                }
                .onExitCommand { dismiss() }
                .onMoveCommand { dir in
                    switch dir {
                    case .up: moveSelection(-1)
                    case .down: moveSelection(1)
                    default: break
                    }
                }
                .onSubmit {
                    dismiss()
                    selectedOption?.action()
                }
        }
    }

    private func moveSelection(_ delta: Int) {
        let count = filteredOptions.count
        guard count > 0 else { return }
        let current: Int
        if let idx = selectedIndex {
            current = Int(idx)
        } else {
            current = delta > 0 ? -1 : count
        }
        let next = (current + delta + count) % count
        selectedIndex = UInt(next)
    }

    private func dismiss() {
        isPresented = false
        query = ""
    }
}
