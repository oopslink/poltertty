// macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift
import SwiftUI
import AppKit

struct FileBrowserPanel: View {
    @ObservedObject var viewModel: FileBrowserViewModel
    var onOpenInTerminal: ((URL) -> Void)?

    @State private var renameText: String = ""
    @FocusState private var isFocused: Bool
    @State private var treeWidth: CGFloat = 260

    var body: some View {
        panelContent
            .background(Color(nsColor: .windowBackgroundColor))
            .focusable()
            .focused($isFocused)
            .backport.onKeyPress(".") { handleDotKey(modifiers: $0) }
            .backport.onKeyPress("t") { handleTKey(modifiers: $0) }
            .backport.onKeyPress("r") { handleRKey(modifiers: $0) }
            .backport.onKeyPress("n") { handleNKey(modifiers: $0) }
            .backport.onKeyPress(KeyEquivalent.delete) { handleDeleteKey(modifiers: $0) }
            .backport.onKeyPress("c") { handleCKey(modifiers: $0) }
            .backport.onKeyPress("f") { handleFKey(modifiers: $0) }
            .backport.onKeyPress("N") { handleUpperNKey(modifiers: $0) }
            .backport.onKeyPress(" ") { handleSpaceKey(modifiers: $0) }
            .onChange(of: viewModel.filterText) { text in
                if text.isEmpty {
                    viewModel.deactivateRecursiveFilter()
                }
            }
    }

    private var panelContent: some View {
        HStack(spacing: 0) {
            // Left: File tree (always visible)
            VStack(spacing: 0) {
                filterBar
                Divider()
                if viewModel.rootDir.isEmpty || !FileManager.default.fileExists(atPath: viewModel.rootDir) {
                    emptyStateView
                } else {
                    treeScrollView
                }
            }
            .frame(minWidth: 200, maxWidth: viewModel.showPreviewPanel ? treeWidth : .infinity)
            .frame(width: viewModel.showPreviewPanel ? treeWidth : nil)

            // Right: Preview panel (if enabled)
            if viewModel.showPreviewPanel, let nodeId = viewModel.selectedNodeId,
               let url = viewModel.findNodeURL(id: nodeId),
               !url.hasDirectoryPath {
                draggableDivider
                FilePreviewView(
                    url: url,
                    isFullscreen: viewModel.isPreviewFullscreen,
                    onToggleFullscreen: {
                        viewModel.togglePreviewFullscreen()
                    }
                )
                .frame(minWidth: 200)
            }
        }
    }

    private var draggableDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .overlay(
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let newWidth = treeWidth + value.translation.width
                                treeWidth = max(200, min(newWidth, 600))
                            }
                    )
            )
    }

    // MARK: - Key Handlers

    private func handleDotKey(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused else { return .ignored }
        viewModel.toggleHiddenFiles()
        return .handled
    }

    private func handleTKey(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused, let nodeId = viewModel.selectedNodeId,
              let entry = viewModel.visibleNodes.first(where: { $0.node.id == nodeId }) else { return .ignored }
        onOpenInTerminal?(entry.node.url)
        return .handled
    }

    private func handleRKey(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused, let nodeId = viewModel.selectedNodeId,
              let entry = viewModel.visibleNodes.first(where: { $0.node.id == nodeId }) else { return .ignored }
        renameText = entry.node.name
        viewModel.renamingNodeId = nodeId
        return .handled
    }

    private func handleNKey(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused, let nodeId = viewModel.selectedNodeId,
              let entry = viewModel.visibleNodes.first(where: { $0.node.id == nodeId }) else { return .ignored }
        let dir = entry.node.isDirectory ? entry.node.url : entry.node.url.deletingLastPathComponent()
        viewModel.createFile(inDirectory: dir, name: "untitled")
        return .handled
    }

    private func handleDeleteKey(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused, modifiers.contains(.command) else { return .ignored }
        guard let nodeId = viewModel.selectedNodeId,
              let entry = viewModel.visibleNodes.first(where: { $0.node.id == nodeId }) else { return .ignored }
        viewModel.delete(url: entry.node.url)
        viewModel.selectedNodeId = nil
        return .handled
    }

    private func handleCKey(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused, modifiers.contains(.command), modifiers.contains(.shift) else { return .ignored }
        guard let nodeId = viewModel.selectedNodeId,
              let entry = viewModel.visibleNodes.first(where: { $0.node.id == nodeId }) else { return .ignored }
        viewModel.copyPath(entry.node.url)
        return .handled
    }

    private func handleFKey(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused, modifiers.contains(.command) else { return .ignored }
        viewModel.activateRecursiveFilter()
        return .handled
    }

    private func handleUpperNKey(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused, modifiers.contains(.shift) else { return .ignored }
        guard let nodeId = viewModel.selectedNodeId,
              let entry = viewModel.visibleNodes.first(where: { $0.node.id == nodeId }) else { return .ignored }
        let dir = entry.node.isDirectory ? entry.node.url : entry.node.url.deletingLastPathComponent()
        viewModel.createDirectory(inDirectory: dir, name: "untitled")
        return .handled
    }

    private func handleSpaceKey(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused, viewModel.selectedNodeId != nil else { return .ignored }
        // Toggle preview panel with space key
        viewModel.togglePreviewPanel()
        return .handled
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            TextField("Filter", text: $viewModel.filterText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack {
            Spacer()
            Image(systemName: "folder")
                .font(.system(size: 24))
                .foregroundColor(Color.secondary.opacity(0.5))
            Text(viewModel.rootDir.isEmpty ? "No directory set" : "Directory not found")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tree Scroll View

    private var treeScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.visibleNodes, id: \.node.id) { entry in
                    FileNodeRow(
                        node: entry.node,
                        depth: entry.depth,
                        gitStatus: viewModel.gitStatus(for: entry.node.url),
                        isSelected: viewModel.selectedNodeId == entry.node.id,
                        onToggleExpand: {
                            viewModel.toggleExpand(nodeId: entry.node.id)
                        },
                        onSingleClick: {
                            viewModel.selectNode(id: entry.node.id)
                            isFocused = true
                        },
                        onDoubleClick: {
                            if entry.node.isDirectory {
                                viewModel.toggleExpand(nodeId: entry.node.id)
                            } else {
                                viewModel.openInDefaultApp(entry.node.url)
                            }
                        },
                        onOpenInTerminal: {
                            onOpenInTerminal?(entry.node.url)
                        },
                        onCopyPath: {
                            viewModel.copyPath(entry.node.url)
                        },
                        onNewFile: {
                            let dir = entry.node.isDirectory
                                ? entry.node.url
                                : entry.node.url.deletingLastPathComponent()
                            viewModel.createFile(inDirectory: dir, name: "untitled")
                        },
                        onNewDirectory: {
                            let dir = entry.node.isDirectory
                                ? entry.node.url
                                : entry.node.url.deletingLastPathComponent()
                            viewModel.createDirectory(inDirectory: dir, name: "untitled")
                        },
                        onDelete: {
                            viewModel.delete(url: entry.node.url)
                            if viewModel.selectedNodeId == entry.node.id {
                                viewModel.selectedNodeId = nil
                                viewModel.showPreviewPanel = false
                            }
                        },
                        onStartRename: {
                            renameText = entry.node.name
                            viewModel.renamingNodeId = entry.node.id
                        },
                        isRenaming: viewModel.renamingNodeId == entry.node.id,
                        renameText: viewModel.renamingNodeId == entry.node.id
                            ? Binding(get: { renameText }, set: { renameText = $0 })
                            : nil,
                        onCommitRename: { newName in
                            viewModel.rename(url: entry.node.url, to: newName)
                        }
                    )
                }
            }
        }
    }
}
