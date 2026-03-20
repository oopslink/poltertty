// macos/Sources/Features/Tmux/TmuxWindowBar.swift
import SwiftUI

/// 终端右上角 tmux window 切换 overlay + detach 按钮
struct TmuxWindowBar: View {
    let state: TmuxAttachState
    let onSelectWindow: (Int) -> Void
    let onDetach: () -> Void

    @State private var isHovered = false
    @State private var showOverflowPopover = false

    private let maxVisible = 4

    var body: some View {
        HStack(spacing: 4) {
            ForEach(visibleWindows) { window in
                windowPill(window)
            }

            if state.windows.count > maxVisible {
                overflowPill
            }

            detachButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .opacity(isHovered ? 1.0 : 0.4)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { isHovered = $0 }
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
                }
            }
            .padding(4)
            .frame(minWidth: 140)
        }
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
