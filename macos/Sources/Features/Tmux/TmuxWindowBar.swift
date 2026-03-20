// macos/Sources/Features/Tmux/TmuxWindowBar.swift
import SwiftUI

/// 终端右上角 tmux window 切换 overlay + detach 按钮
struct TmuxWindowBar: View {
    let state: TmuxAttachState
    let onSelectWindow: (Int) -> Void
    let onCloseWindow: (Int) -> Void
    let onNewWindow: () -> Void
    let onDetach: () -> Void

    @State private var isHovered = false
    @State private var showOverflowPopover = false
    @State private var windowToClose: TmuxAttachState.WindowInfo? = nil

    private let maxVisible = 4

    var body: some View {
        HStack(spacing: 4) {
            ForEach(visibleWindows) { window in
                windowPill(window)
            }

            if state.windows.count > maxVisible {
                overflowPill
            }

            newWindowButton
            detachButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .opacity(isHovered ? 1.0 : 0.4)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { isHovered = $0 }
        .alert(
            "Close tmux Window",
            isPresented: Binding(
                get: { windowToClose != nil },
                set: { if !$0 { windowToClose = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { windowToClose = nil }
            Button("Close", role: .destructive) {
                if let w = windowToClose {
                    onCloseWindow(w.index)
                    windowToClose = nil
                }
            }
        } message: {
            if let w = windowToClose {
                Text("确定关闭 window \(w.index):\(w.name)？")
            }
        }
    }

    private var visibleWindows: [TmuxAttachState.WindowInfo] {
        Array(state.windows.prefix(maxVisible))
    }

    private func windowPill(_ window: TmuxAttachState.WindowInfo) -> some View {
        Button {
            onSelectWindow(window.index)
        } label: {
            Text("\(window.index):\(window.name)")
                .font(.system(size: 10, weight: window.active ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    window.active
                        ? AnyShapeStyle(Color.accentColor.opacity(0.3))
                        : AnyShapeStyle(.quaternary)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Switch to Window") { onSelectWindow(window.index) }
            Divider()
            Button("Close Window", role: .destructive) {
                windowToClose = window
            }
        }
    }

    private var overflowPill: some View {
        Button {
            showOverflowPopover = true
        } label: {
            Text("···")
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showOverflowPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(state.windows) { window in
                    Button {
                        onSelectWindow(window.index)
                        showOverflowPopover = false
                    } label: {
                        HStack {
                            Text("\(window.index):\(window.name)")
                                .font(.system(size: 11))
                            Spacer()
                            if window.active {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Close Window", role: .destructive) {
                            showOverflowPopover = false
                            windowToClose = window
                        }
                    }
                }
            }
            .padding(4)
            .frame(minWidth: 140)
        }
    }

    private var newWindowButton: some View {
        Button {
            onNewWindow()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .semibold))
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New tmux window")
    }

    private var detachButton: some View {
        Button {
            onDetach()
        } label: {
            Image(systemName: "eject")
                .font(.system(size: 10))
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Detach from tmux session")
    }
}
