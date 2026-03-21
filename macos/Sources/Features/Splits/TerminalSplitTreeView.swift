import SwiftUI

// No custom EnvironmentKey needed — TabBarViewModel injected via .environmentObject()

/// A single operation within the split tree.
///
/// Rather than binding the split tree (which is immutable), any mutable operations are
/// exposed via this enum to the embedder to handle.
enum TerminalSplitOperation {
    case resize(Resize)
    case drop(Drop)
    case close(Close)

    struct Resize {
        let node: SplitTree<Ghostty.SurfaceView>.Node
        let ratio: Double
    }

    struct Drop {
        /// The surface being dragged.
        let payload: Ghostty.SurfaceView

        /// The surface it was dragged onto
        let destination: Ghostty.SurfaceView

        /// The zone it was dropped to determine how to split the destination.
        let zone: TerminalSplitDropZone
    }

    struct Close {
        let surface: Ghostty.SurfaceView
    }
}

struct TerminalSplitTreeView: View {
    let tree: SplitTree<Ghostty.SurfaceView>
    let action: (TerminalSplitOperation) -> Void

    var body: some View {
        if let node = tree.zoomed ?? tree.root {
            TerminalSplitSubtreeView(
                node: node,
                isRoot: node == tree.root,
                action: action)
            // This is necessary because we can't rely on SwiftUI's implicit
            // structural identity to detect changes to this view. Due to
            // the tree structure of splits it could result in bad behaviors.
            // See: https://github.com/ghostty-org/ghostty/issues/7546
            .id(node.structuralIdentity)
        }
    }
}

private struct TerminalSplitSubtreeView: View {
    @EnvironmentObject var ghostty: Ghostty.App

    let node: SplitTree<Ghostty.SurfaceView>.Node
    var isRoot: Bool = false
    let action: (TerminalSplitOperation) -> Void

    var body: some View {
        switch node {
        case .leaf(let leafView):
            TerminalSplitLeafContainer(surfaceView: leafView, isSplit: !isRoot, action: action)

        case .split(let split):
            let splitViewDirection: SplitViewDirection = switch split.direction {
            case .horizontal: .horizontal
            case .vertical: .vertical
            }

            SplitView(
                splitViewDirection,
                .init(get: {
                    CGFloat(split.ratio)
                }, set: {
                    action(.resize(.init(node: node, ratio: $0)))
                }),
                dividerColor: ghostty.config.splitDividerColor,
                resizeIncrements: .init(width: 1, height: 1),
                left: {
                    TerminalSplitSubtreeView(node: split.left, action: action)
                },
                right: {
                    TerminalSplitSubtreeView(node: split.right, action: action)
                },
                onEqualize: {
                    guard let surface = node.leftmostLeaf().surface else { return }
                    ghostty.splitEqualize(surface: surface)
                }
            )
        }
    }
}

private struct TerminalSplitLeafContainer: View {
    let surfaceView: Ghostty.SurfaceView
    let isSplit: Bool
    let action: (TerminalSplitOperation) -> Void

    @StateObject private var statusMonitor = GitStatusMonitor(pwd: "")
    @Environment(\.showStatusBar) private var showStatusBar
    @FocusedValue(\.ghosttySurfaceView) private var focusedSurface

    private var isFocused: Bool {
        // focusedSurface 为 nil 时（窗口失焦），默认视为 focused，避免所有 pane 同时变半透明
        guard let focused = focusedSurface else { return true }
        return focused === surfaceView
    }

    var body: some View {
        TerminalSplitLeaf(surfaceView: surfaceView, isSplit: isSplit, action: action)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showStatusBar {
                    BottomStatusBarView(
                        monitor: statusMonitor,
                        pwd: surfaceView.pwd ?? "",
                        isFocused: isFocused
                    )
                }
            }
            .onReceive(surfaceView.$pwd.compactMap { $0 }.removeDuplicates()) { pwd in
                statusMonitor.updatePwd(pwd)
            }
    }
}

private struct TerminalSplitLeaf: View {
    let surfaceView: Ghostty.SurfaceView
    let isSplit: Bool
    let action: (TerminalSplitOperation) -> Void

    @EnvironmentObject var tabBarVM: TabBarViewModel
    @State private var dropState: DropState = .idle
    @State private var isSelfDragging: Bool = false
    @State private var isHovering: Bool = false

    var body: some View {
        GeometryReader { geometry in
            Ghostty.InspectableSurface(
                surfaceView: surfaceView,
                isSplit: isSplit)
            .background {
                // If we're dragging ourself, we hide the entire drop zone. This makes
                // it so that a released drop animates back to its source properly
                // so it is a proper invalid drop zone.
                if !isSelfDragging {
                    Color.clear
                        .onDrop(of: [.ghosttySurfaceId], delegate: SplitDropDelegate(
                            dropState: $dropState,
                            viewSize: geometry.size,
                            destinationSurface: surfaceView,
                            action: action
                        ))
                }
            }
            .overlay {
                if !isSelfDragging, case .dropping(let zone) = dropState {
                    zone.overlay(in: geometry)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSplit && isHovering && !isSelfDragging {
                    SplitCloseButton {
                        action(.close(.init(surface: surfaceView)))
                    }
                    .padding(6)
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                }
            }
            .overlay(alignment: .topTrailing) {
                if let tmuxState = tabBarVM.tmuxStates[surfaceView.id],
                   !tmuxState.windows.isEmpty {
                    TmuxWindowBar(
                        state: tmuxState,
                        onSelectWindow: { index in
                            let sessionName = tmuxState.sessionName
                            Task {
                                try? await TmuxCommandRunner.runSilent(
                                    args: ["select-window", "-t", "\(sessionName):\(index)"]
                                )
                            }
                        },
                        onCloseWindow: { index in
                            let sessionName = tmuxState.sessionName
                            Task {
                                try? await TmuxCommandRunner.runSilent(
                                    args: ["kill-window", "-t", "\(sessionName):\(index)"]
                                )
                                await MainActor.run { tabBarVM.tmuxMonitor.refresh() }
                            }
                        },
                        onNewWindow: {
                            let sessionName = tmuxState.sessionName
                            Task {
                                try? await TmuxCommandRunner.runSilent(
                                    args: ["new-window", "-t", sessionName]
                                )
                                await MainActor.run { tabBarVM.tmuxMonitor.refresh() }
                            }
                        },
                        onDetach: {
                            let sessionName = tmuxState.sessionName
                            Task {
                                try? await TmuxCommandRunner.runSilent(
                                    args: ["detach-client", "-s", sessionName]
                                )
                                await MainActor.run {
                                    tabBarVM.tmuxStates.removeValue(forKey: surfaceView.id)
                                    tabBarVM.tmuxMonitor.stopIfIdle()
                                }
                            }
                        }
                    )
                    .padding(.top, isSplit ? 24 : 8)
                    .padding(.trailing, 8)
                    .transition(.opacity)
                }
            }
            .onHover { hovering in
                isHovering = hovering
            }
            .onPreferenceChange(Ghostty.DraggingSurfaceKey.self) { value in
                isSelfDragging = value == surfaceView.id
                if isSelfDragging {
                    dropState = .idle
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Terminal pane")
        }
    }

    private enum DropState: Equatable {
        case idle
        case dropping(TerminalSplitDropZone)
    }

    private struct SplitDropDelegate: DropDelegate {
        @Binding var dropState: DropState
        let viewSize: CGSize
        let destinationSurface: Ghostty.SurfaceView
        let action: (TerminalSplitOperation) -> Void

        func validateDrop(info: DropInfo) -> Bool {
            info.hasItemsConforming(to: [.ghosttySurfaceId])
        }

        func dropEntered(info: DropInfo) {
            dropState = .dropping(.calculate(at: info.location, in: viewSize))
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            // For some reason dropUpdated is sent after performDrop is called
            // and we don't want to reset our drop zone to show it so we have
            // to guard on the state here.
            guard case .dropping = dropState else { return DropProposal(operation: .forbidden) }
            dropState = .dropping(.calculate(at: info.location, in: viewSize))
            return DropProposal(operation: .move)
        }

        func dropExited(info: DropInfo) {
            dropState = .idle
        }

        func performDrop(info: DropInfo) -> Bool {
            let zone = TerminalSplitDropZone.calculate(at: info.location, in: viewSize)
            dropState = .idle

            // Load the dropped surface asynchronously using Transferable
            let providers = info.itemProviders(for: [.ghosttySurfaceId])
            guard let provider = providers.first else { return false }

            // Capture action before the async closure
            _ = provider.loadTransferable(type: Ghostty.SurfaceView.self) { [weak destinationSurface] result in
                switch result {
                case .success(let sourceSurface):
                    DispatchQueue.main.async {
                        // Don't allow dropping on self
                        guard let destinationSurface else { return }
                        guard sourceSurface !== destinationSurface else { return }
                        action(.drop(.init(payload: sourceSurface, destination: destinationSurface, zone: zone)))
                    }

                case .failure:
                    break
                }
            }

            return true
        }
    }
}

private struct SplitCloseButton: View {
    let action: () -> Void

    @State private var isButtonHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .background(
                    .regularMaterial,
                    in: Circle()
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
                .scaleEffect(isButtonHovering ? 1.1 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isButtonHovering = hovering
            }
        }
        .accessibilityLabel("Close split pane")
    }
}

enum TerminalSplitDropZone: String, Equatable {
    case top
    case bottom
    case left
    case right

    /// Determines which drop zone the cursor is in based on proximity to edges.
    ///
    /// Divides the view into four triangular regions by drawing diagonals from
    /// corner to corner. The drop zone is determined by which edge the cursor
    /// is closest to, creating natural triangular hit regions for each side.
    static func calculate(at point: CGPoint, in size: CGSize) -> TerminalSplitDropZone {
        let relX = point.x / size.width
        let relY = point.y / size.height

        let distToLeft = relX
        let distToRight = 1 - relX
        let distToTop = relY
        let distToBottom = 1 - relY

        let minDist = min(distToLeft, distToRight, distToTop, distToBottom)

        if minDist == distToLeft { return .left }
        if minDist == distToRight { return .right }
        if minDist == distToTop { return .top }
        return .bottom
    }

    @ViewBuilder
    func overlay(in geometry: GeometryProxy) -> some View {
        let overlayColor = Color.accentColor.opacity(0.3)

        switch self {
        case .top:
            VStack(spacing: 0) {
                Rectangle()
                    .fill(overlayColor)
                    .frame(height: geometry.size.height / 2)
                Spacer()
            }
        case .bottom:
            VStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(overlayColor)
                    .frame(height: geometry.size.height / 2)
            }
        case .left:
            HStack(spacing: 0) {
                Rectangle()
                    .fill(overlayColor)
                    .frame(width: geometry.size.width / 2)
                Spacer()
            }
        case .right:
            HStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(overlayColor)
                    .frame(width: geometry.size.width / 2)
            }
        }
    }
}

// MARK: - ShowStatusBar Environment Key

private struct ShowStatusBarKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var showStatusBar: Bool {
        get { self[ShowStatusBarKey.self] }
        set { self[ShowStatusBarKey.self] = newValue }
    }
}
