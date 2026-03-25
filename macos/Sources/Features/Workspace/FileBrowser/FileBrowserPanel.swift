// macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift
import SwiftUI
import AppKit

struct FileBrowserPanel: View {
    @ObservedObject var viewModel: FileBrowserViewModel
    var onOpenInTerminal: ((URL) -> Void)?
    var worktreeMonitor: GitWorktreeMonitor? = nil

    @State private var renameText: String = ""
    @FocusState private var isFocused: Bool
    @State private var treeDividerHovered = false
    @State private var showBatchDeleteAlert = false
    @State private var showMoveError = false
    @State private var moveErrorMessage = ""
    @State private var showFileHistorySheet = false
    @State private var fileHistoryPath: String?

    var body: some View {
        panelContent
            .background(Color(nsColor: .windowBackgroundColor))
            .focusable()
            .focused($isFocused)
            .backport.onKeyPress(".") { handleDotKey(modifiers: $0) }
            .backport.onKeyPress("o") { handleOKey(modifiers: $0) }
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
            .backport.onKeyPress("?") { handleQuestionKey(modifiers: $0) }
            .backport.onKeyPress("g") { handleGKey(modifiers: $0) }
            .onChange(of: viewModel.filterText) { text in
                if text.isEmpty {
                    viewModel.deactivateRecursiveFilter()
                }
            }
            .alert("Delete \(viewModel.selectedNodeIds.count) Items?", isPresented: $showBatchDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Move to Trash", role: .destructive) {
                    let errors = viewModel.deleteSelected()
                    if !errors.isEmpty {
                        moveErrorMessage = "The following items could not be deleted: \(errors.joined(separator: ", "))"
                        showMoveError = true
                    }
                }
            } message: {
                Text("Items will be moved to Trash and can be recovered.")
            }
            .alert("Operation Failed", isPresented: $showMoveError) {
                Button("OK") {}
            } message: {
                Text(moveErrorMessage)
            }
            .sheet(isPresented: $showFileHistorySheet) {
                if let path = fileHistoryPath, let repo = viewModel.gitRepo {
                    FileHistorySheet(path: path, repo: repo)
                }
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
                if let monitor = worktreeMonitor, monitor.worktrees.count > 1 {
                    WorktreeNavigationBar(monitor: monitor, viewModel: viewModel)
                    Divider()
                }
                filterBar
                if !viewModel.gitStatuses.isEmpty {
                    FilterChipsView(viewModel: viewModel)
                    Divider()
                }
                if !viewModel.breadcrumbSegments.isEmpty {
                    BreadcrumbView(segments: viewModel.breadcrumbSegments) { segment in
                        viewModel.focusDirectory(segment.url)
                    }
                    Divider()
                }
                Divider()
                if viewModel.rootDir.isEmpty || !FileManager.default.fileExists(atPath: viewModel.rootDir) {
                    emptyStateView
                } else {
                    treeScrollView
                }
                Divider()
                rootPathStatusBar
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
                    },
                    gitDelta: viewModel.gitDelta(for: url),
                    gitRepo: viewModel.gitRepo
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
        panel.prompt = "Move Here"
        panel.message = "Choose destination directory"

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

    private func handleOKey(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused, let nodeId = viewModel.lastSelectedId,
              let entry = viewModel.visibleNodes.first(where: { $0.node.id == nodeId }) else { return .ignored }
        viewModel.openInFinder(entry.node.url)
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
                moveErrorMessage = "The following items could not be deleted: \(errors.joined(separator: ", "))"
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

    private func handleQuestionKey(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused else { return .ignored }
        viewModel.showShortcutHelp.toggle()
        return .handled
    }

    private func handleGKey(modifiers: EventModifiers) -> BackportKeyPressResult {
        guard isFocused, !viewModel.gitStatuses.isEmpty else { return .ignored }
        viewModel.toggleUncommittedFilter()
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
                if !viewModel.availableExtensions.isEmpty || !viewModel.gitStatuses.isEmpty {
                    filterButtonGroup
                }
                Button {
                    viewModel.showShortcutHelp.toggle()
                } label: {
                    Image(systemName: "questionmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Keyboard Shortcuts (?)")
                .popover(isPresented: $viewModel.showShortcutHelp, arrowEdge: .trailing) {
                    ShortcutHelpView()
                }
                Button {
                    viewModel.isVisible = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close File Browser")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            if viewModel.selectedNodeIds.count > 1 {
                HStack {
                    Text("\(viewModel.selectedNodeIds.count) items selected")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Deselect All") { viewModel.clearSelection() }
                        .font(.system(size: 10))
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Filter Button Group

    /// 过滤器按钮组：文件类型下拉菜单（左）+ 未提交文件快速过滤（右）
    private var filterButtonGroup: some View {
        HStack(spacing: 0) {
            // 文件类型下拉菜单
            if !viewModel.availableExtensions.isEmpty {
                Menu {
                    ForEach(viewModel.availableExtensions, id: \.ext) { item in
                        Button {
                            viewModel.toggleExtensionFilter(item.ext)
                        } label: {
                            Label {
                                Text(".\(item.ext)  ×\(item.count)")
                            } icon: {
                                if viewModel.activeExtensions.contains(item.ext) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    if !viewModel.activeExtensions.isEmpty {
                        Divider()
                        Button("Clear Extension Filters") {
                            viewModel.activeExtensions = []
                        }
                    }
                } label: {
                    Image(systemName: viewModel.activeExtensions.isEmpty
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(viewModel.activeExtensions.isEmpty ? .secondary : .accentColor)
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Filter by File Type")
            }

            // 分隔线
            if !viewModel.availableExtensions.isEmpty && !viewModel.gitStatuses.isEmpty {
                Rectangle()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 1, height: 12)
                    .padding(.horizontal, 2)
            }

            // 未提交文件过滤按钮
            if !viewModel.gitStatuses.isEmpty {
                Button {
                    viewModel.toggleUncommittedFilter()
                } label: {
                    Image(systemName: viewModel.isUncommittedFilterActive
                          ? "exclamationmark.circle.fill"
                          : "exclamationmark.circle")
                        .font(.system(size: 11))
                        .foregroundColor(viewModel.isUncommittedFilterActive ? .orange : .secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Show Uncommitted Files Only (g)")
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.06))
        .cornerRadius(5)
    }

    // MARK: - Root Path Status Bar

    private var rootPathStatusBar: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.6))
            Text(viewModel.effectiveRootDir)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack {
            Spacer()
            Image(systemName: "folder")
                .font(.system(size: 24))
                .foregroundColor(Color.secondary.opacity(0.5))
            Text(viewModel.effectiveRootDir.isEmpty ? "No directory set" : "Directory not found")
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
            gitDelta: viewModel.gitDelta(for: entry.node.url),
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
            onOpenInFinder: {
                viewModel.openInFinder(entry.node.url)
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
            onStage: {
                let urls = viewModel.selectedNodeIds.count > 1
                    ? viewModel.selectedURLs
                    : [entry.node.url]
                viewModel.stageFiles(urls)
            },
            onUnstage: {
                let urls = viewModel.selectedNodeIds.count > 1
                    ? viewModel.selectedURLs
                    : [entry.node.url]
                viewModel.unstageFiles(urls)
            },
            onShowFileHistory: { path in
                fileHistoryPath = path
                showFileHistorySheet = true
            },
            onDiscardChanges: { path in
                Task {
                    do {
                        try await viewModel.gitRepo?.discard(paths: [path])
                    } catch {
                        await MainActor.run {
                            moveErrorMessage = "Discard failed: \(error.localizedDescription)"
                            showMoveError = true
                        }
                    }
                    await viewModel.refreshGitStatus()
                }
            },
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

// MARK: - Worktree Navigation Bar

/// 显示当前所在 worktree 并提供快速切换的工具栏
private struct WorktreeNavigationBar: View {
    @ObservedObject var monitor: GitWorktreeMonitor
    @ObservedObject var viewModel: FileBrowserViewModel

    var body: some View {
        let effectivePath = viewModel.effectiveRootDir
        let current = monitor.worktrees.first {
            URL(fileURLWithPath: $0.path).standardized.path
                == URL(fileURLWithPath: effectivePath).standardized.path
        }
        let currentLabel = currentDisplayLabel(for: current, fallback: effectivePath)

        HStack(spacing: 4) {
            if viewModel.overrideRootDir != nil {
                Button {
                    viewModel.switchRoot(to: nil)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .semibold))
                        Text("主仓库")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("返回主仓库根目录")
            }

            Spacer()

            Menu {
                ForEach(monitor.worktrees) { wt in
                    let isActive = URL(fileURLWithPath: wt.path).standardized.path
                        == URL(fileURLWithPath: effectivePath).standardized.path
                    Button {
                        if wt.isMain {
                            viewModel.switchRoot(to: nil)
                        } else {
                            viewModel.switchRoot(to: wt.path)
                        }
                    } label: {
                        Label {
                            Text(wt.isMain ? "主仓库" : (wt.branch ?? wt.path))
                        } icon: {
                            if isActive {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(isActive)
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10))
                    Text(currentLabel)
                        .font(.system(size: 11))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("切换 Worktree")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    private func currentDisplayLabel(for wt: GitWorktree?, fallback: String) -> String {
        guard let wt else { return URL(fileURLWithPath: fallback).lastPathComponent }
        if wt.isMain { return "主仓库" }
        return wt.branch ?? wt.path
    }
}
