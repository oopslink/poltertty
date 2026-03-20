// macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift
import SwiftUI
import AppKit

struct FileBrowserPanel: View {
    @ObservedObject var viewModel: FileBrowserViewModel
    var onOpenInTerminal: ((URL) -> Void)?

    @State private var renameText: String = ""
    @FocusState private var isFocused: Bool
    @State private var treeDividerHovered = false
    @State private var showBatchDeleteAlert = false
    @State private var showMoveError = false
    @State private var moveErrorMessage = ""

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
            .backport.onKeyPress(KeyEquivalent.upArrow)   { handleUpArrow(modifiers: $0) }
            .backport.onKeyPress(KeyEquivalent.downArrow) { handleDownArrow(modifiers: $0) }
            .backport.onKeyPress(KeyEquivalent.return)    { handleReturnKey(modifiers: $0) }
            .backport.onKeyPress("a") { handleAKey(modifiers: $0) }
            .onChange(of: viewModel.filterText) { text in
                if text.isEmpty {
                    viewModel.deactivateRecursiveFilter()
                }
            }
            .alert("删除 \(viewModel.selectedNodeIds.count) 个项目？", isPresented: $showBatchDeleteAlert) {
                Button("取消", role: .cancel) {}
                Button("移到废纸篓", role: .destructive) {
                    let errors = viewModel.deleteSelected()
                    if !errors.isEmpty {
                        moveErrorMessage = "以下项目无法删除：\(errors.joined(separator: "、"))"
                        showMoveError = true
                    }
                }
            } message: {
                Text("此操作将移至废纸篓，可恢复。")
            }
            .alert("操作失败", isPresented: $showMoveError) {
                Button("好") {}
            } message: {
                Text(moveErrorMessage)
            }
    }

    private var isPreviewVisible: Bool {
        guard viewModel.showPreviewPanel,
              let nodeId = viewModel.lastSelectedId,
              let url = viewModel.findNodeURL(id: nodeId),
              !url.hasDirectoryPath else { return false }
        return true
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
            .frame(minWidth: 200, maxWidth: isPreviewVisible ? viewModel.treeWidth : .infinity)
            .frame(width: isPreviewVisible ? viewModel.treeWidth : nil)

            // Right: Preview panel (if enabled)
            if viewModel.showPreviewPanel, let nodeId = viewModel.lastSelectedId,
               let url = viewModel.findNodeURL(id: nodeId),
               !url.hasDirectoryPath {
                draggableDivider
                FilePreviewView(
                    url: url,
                    isFullscreen: viewModel.isPreviewFullscreen,
                    onToggleFullscreen: {
                        viewModel.togglePreviewFullscreen()
                    },
                    onClose: {
                        withAnimation(nil) {
                            viewModel.showPreviewPanel = false
                            viewModel.isPreviewFullscreen = false
                        }
                    }
                )
                .frame(minWidth: 200)
            }
        }
    }

    private var draggableDivider: some View {
        ZStack {
            Color(nsColor: .separatorColor)
                .frame(width: 1)
            if treeDividerHovered {
                DividerGripHandle()
            }
        }
        .frame(width: 16)
        .contentShape(Rectangle())
        .onHover { inside in
            treeDividerHovered = inside
            if inside {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let newWidth = viewModel.treeWidth + value.translation.width
                    viewModel.treeWidth = max(200, min(newWidth, 600))
                }
        )
    }

    // MARK: - Move Panel

    private func presentMovePanel() {
        let urls = viewModel.selectedNodeIds.compactMap { viewModel.findNodeURL(id: $0) }
        guard !urls.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "移动到此处"
        panel.message = "选择目标目录"

        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            let errors = viewModel.move(urls: urls, to: destination)
            if !errors.isEmpty {
                DispatchQueue.main.async {
                    moveErrorMessage = errors.joined(separator: "\n")
                    showMoveError = true
                }
            }
        }
    }

    // MARK: - Key Handlers

    private func handleDotKey(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused else { return .ignored }
        viewModel.toggleHiddenFiles()
        return .handled
    }

    private func handleTKey(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused, let nodeId = viewModel.lastSelectedId,
              let entry = viewModel.visibleNodes.first(where: { $0.node.id == nodeId }) else { return .ignored }
        onOpenInTerminal?(entry.node.url)
        return .handled
    }

    private func handleRKey(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused, let nodeId = viewModel.lastSelectedId,
              let entry = viewModel.visibleNodes.first(where: { $0.node.id == nodeId }) else { return .ignored }
        renameText = entry.node.name
        viewModel.renamingURL = entry.node.url
        return .handled
    }

    private func handleNKey(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused, let nodeId = viewModel.lastSelectedId,
              let entry = viewModel.visibleNodes.first(where: { $0.node.id == nodeId }) else { return .ignored }
        let dir = entry.node.isDirectory ? entry.node.url : entry.node.url.deletingLastPathComponent()
        viewModel.createFile(inDirectory: dir, name: "untitled")
        return .handled
    }

    private func handleDeleteKey(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused, modifiers.contains(.command) else { return .ignored }
        guard !viewModel.selectedNodeIds.isEmpty else { return .ignored }
        if viewModel.selectedNodeIds.count > 1 {
            showBatchDeleteAlert = true
        } else {
            let errors = viewModel.deleteSelected()
            if !errors.isEmpty {
                moveErrorMessage = "以下项目无法删除：\(errors.joined(separator: "、"))"
                showMoveError = true
            }
        }
        return .handled
    }

    private func handleCKey(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused, modifiers.contains(.command), modifiers.contains(.shift) else { return .ignored }
        guard let nodeId = viewModel.lastSelectedId,
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
        guard let nodeId = viewModel.lastSelectedId,
              let entry = viewModel.visibleNodes.first(where: { $0.node.id == nodeId }) else { return .ignored }
        let dir = entry.node.isDirectory ? entry.node.url : entry.node.url.deletingLastPathComponent()
        viewModel.createDirectory(inDirectory: dir, name: "untitled")
        return .handled
    }

    private func handleSpaceKey(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused, viewModel.lastSelectedId != nil else { return .ignored }
        // Toggle preview panel with space key
        viewModel.togglePreviewPanel()
        return .handled
    }

    private func handleUpArrow(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused else { return .ignored }
        viewModel.selectPrevious()
        return .handled
    }

    private func handleDownArrow(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused else { return .ignored }
        viewModel.selectNext()
        return .handled
    }

    private func handleReturnKey(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused,
              let nodeId = viewModel.lastSelectedId,
              let entry = viewModel.visibleNodes.first(where: { $0.node.id == nodeId }),
              entry.node.isDirectory else { return .ignored }
        viewModel.toggleExpand(nodeId: nodeId)
        return .handled
    }

    private func handleAKey(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused, modifiers.contains(.command) else { return .ignored }
        viewModel.selectAll()
        return .handled
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField("Filter", text: $viewModel.filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                Button {
                    viewModel.isVisible = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭文件浏览器")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            if viewModel.selectedNodeIds.count > 1 {
                HStack {
                    Text("已选 \(viewModel.selectedNodeIds.count) 个项目")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("取消选择") { viewModel.clearSelection() }
                        .font(.system(size: 10))
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
        }
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    rootHeaderRow
                    ForEach(viewModel.visibleNodes, id: \.node.id) { entry in
                        nodeRowView(for: entry)
                    }
                }
            }
            .onChange(of: viewModel.lastSelectedId) { id in
                if let id {
                    proxy.scrollTo(id)
                }
            }
        }
    }

    // MARK: - Root Header Row

    @State private var rootDropTargeted = false

    private var rootHeaderRow: some View {
        let rootURL = URL(fileURLWithPath: viewModel.rootDir)
        let rootName = rootURL.lastPathComponent
        return HStack(spacing: 4) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(rootName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(rootDropTargeted ? Color.accentColor.opacity(0.15) : Color.clear)
        .dropDestination(for: URL.self) { droppedURLs, _ in
            let selectedURLs = viewModel.selectedNodeIds.compactMap { viewModel.findNodeURL(id: $0) }
            let isDraggingSelected = droppedURLs.first.map { selectedURLs.contains($0) } ?? false
            let urlsToMove = (isDraggingSelected && selectedURLs.count > 1) ? selectedURLs : droppedURLs
            _ = viewModel.move(urls: urlsToMove, to: rootURL)
            return true
        } isTargeted: { targeted in
            rootDropTargeted = targeted
        }
    }

    // 提取为独立方法以辅助 Swift 类型检查器完成类型推断
    private func nodeRowView(for entry: (node: FileNode, depth: Int)) -> some View {
        let renamingBinding: Binding<String>? = viewModel.renamingURL == entry.node.url
            ? Binding(get: { renameText }, set: { renameText = $0 })
            : nil
        return FileNodeRow(
            node: entry.node,
            depth: entry.depth,
            gitStatus: viewModel.gitStatus(for: entry.node.url),
            isSelected: viewModel.selectedNodeIds.contains(entry.node.id),
            onToggleExpand: {
                viewModel.toggleExpand(nodeId: entry.node.id)
            },
            onSingleClick: {
                let flags = NSEvent.modifierFlags
                if flags.contains(.command) {
                    viewModel.toggleSelection(id: entry.node.id)
                } else if flags.contains(.shift) {
                    viewModel.extendSelection(to: entry.node.id)
                } else {
                    viewModel.selectNode(id: entry.node.id)
                    if entry.node.isDirectory {
                        viewModel.toggleExpand(nodeId: entry.node.id)
                    }
                }
                isFocused = true
            },
            onDoubleClick: {
                if !entry.node.isDirectory {
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
                if viewModel.selectedNodeIds.count > 1 {
                    showBatchDeleteAlert = true
                } else {
                    // 确保右键点击的行被选中，再执行删除
                    viewModel.selectNode(id: entry.node.id)
                    viewModel.delete(url: entry.node.url)
                    viewModel.clearSelection()
                }
            },
            onStartRename: {
                renameText = entry.node.name
                viewModel.renamingURL = entry.node.url
            },
            isMultiSelected: viewModel.selectedNodeIds.count > 1,
            selectedCount: viewModel.selectedNodeIds.count,
            selectedURLs: viewModel.selectedURLs,
            onMoveSelected: { presentMovePanel() },
            isRenaming: viewModel.renamingURL == entry.node.url,
            renameText: renamingBinding,
            onCommitRename: { newName in
                viewModel.rename(url: entry.node.url, to: newName)
            },
            onCancelRename: {
                viewModel.renamingURL = nil
            }
        )
        .id(entry.node.id)
        .dropDestination(for: URL.self) { droppedURLs, _ in
            guard entry.node.isDirectory else { return false }
            // 若拖拽的 URL 属于当前多选集，则移动全部选中项，否则仅移动拖拽项。
            // 这样绕过了 NSItemProvider 单类型标识符只保留最后一个 URL 的限制。
            let selectedURLs = viewModel.selectedNodeIds.compactMap { viewModel.findNodeURL(id: $0) }
            let isDraggingSelected = droppedURLs.first.map { selectedURLs.contains($0) } ?? false
            let urlsToMove = (isDraggingSelected && selectedURLs.count > 1) ? selectedURLs : droppedURLs
            _ = viewModel.move(urls: urlsToMove, to: entry.node.url)
            return true
        } isTargeted: { _ in }
    }
}
