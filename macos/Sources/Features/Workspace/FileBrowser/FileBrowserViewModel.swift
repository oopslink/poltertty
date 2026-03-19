// macos/Sources/Features/Workspace/FileBrowser/FileBrowserViewModel.swift
import Foundation
import AppKit

final class FileBrowserViewModel: ObservableObject {
    // MARK: - Published State

    @Published var rootNodes: [FileNode] = []
    @Published var gitStatuses: [String: GitStatus] = [:]
    @Published var filterText: String = ""
    @Published var showHiddenFiles: Bool = false
    @Published var isVisible: Bool
    @Published var panelWidth: CGFloat
    @Published var renamingURL: URL? = nil

    // Preview state
    @Published var selectedNodeIds: Set<UUID> = []
    @Published private(set) var lastSelectedId: UUID? = nil   // @Published 保证预览面板 SwiftUI 响应性

    /// 兼容预览面板：返回最后一次明确选中的节点 ID
    var primarySelectedId: UUID? { lastSelectedId }

    @Published var showPreviewPanel: Bool = false
    @Published var isPreviewFullscreen: Bool = false
    @Published var treeWidth: CGFloat = 260
    @Published var previewTotalWidth: CGFloat = 700

    // MARK: - Internal State

    let rootDir: String
    private var monitor: FileSystemMonitor?
    private var isRecursiveFilter: Bool = false
    private var savedExpandedUrls: Set<URL> = []

    // MARK: - Init

    init(rootDir: String, isVisible: Bool = false, panelWidth: CGFloat = 260) {
        self.rootDir = rootDir
        self.isVisible = isVisible
        self.panelWidth = panelWidth

        guard !rootDir.isEmpty, FileManager.default.fileExists(atPath: rootDir) else { return }
        setupMonitor()
        reload()
    }

    // MARK: - Monitor

    private func setupMonitor() {
        monitor = FileSystemMonitor(rootDir: rootDir)
        monitor?.onChange = { [weak self] in
            self?.reload()
        }
        monitor?.start()
    }

    /// Pause FSEvents when workspace goes to background
    func pause() {
        monitor?.stop()
    }

    /// Resume FSEvents and force reload when workspace becomes active
    func resume() {
        monitor?.start()
        reload()
    }

    /// Stop FSEvents permanently (workspace destroyed)
    func stop() {
        monitor?.stop()
    }

    // MARK: - Reload

    func reload() {
        // Don't reload while rename is in progress — would recreate nodes and interrupt input
        guard renamingURL == nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard !self.rootDir.isEmpty, FileManager.default.fileExists(atPath: self.rootDir) else {
                self.rootNodes = []
                return
            }

            // Preserve multi-selection URLs across reload
            let selectedURLs = self.selectedNodeIds.compactMap { self.findNodeURL(id: $0) }
            let lastSelectedURL = self.lastSelectedId.flatMap { self.findNodeURL(id: $0) }

            let expanded = self.currentExpandedUrls()
            self.rootNodes = self.loadChildren(at: URL(fileURLWithPath: self.rootDir), expandedUrls: expanded)

            // Restore multi-selection by URL
            var newIds = Set<UUID>()
            for url in selectedURLs {
                if let node = self.findNodeByURL(url: url, in: self.rootNodes) {
                    newIds.insert(node.id)
                }
            }
            self.selectedNodeIds = newIds

            // Restore lastSelectedId
            if let url = lastSelectedURL, let node = self.findNodeByURL(url: url, in: self.rootNodes) {
                self.lastSelectedId = node.id
            } else {
                self.lastSelectedId = nil
                self.showPreviewPanel = false
            }

            Task { await self.refreshGitStatus() }
        }
    }

    private func currentExpandedUrls() -> Set<URL> {
        var urls = Set<URL>()
        collectExpandedUrls(from: rootNodes, into: &urls)
        return urls
    }

    private func collectExpandedUrls(from nodes: [FileNode], into set: inout Set<URL>) {
        for node in nodes where node.isExpanded {
            set.insert(node.url)
            if let children = node.children {
                collectExpandedUrls(from: children, into: &set)
            }
        }
    }

    private func loadChildren(at url: URL, expandedUrls: Set<URL>) -> [FileNode] {
        var options: FileManager.DirectoryEnumerationOptions = []
        if !showHiddenFiles { options.insert(.skipsHiddenFiles) }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: options
        ) else { return [] }

        let sorted = contents.sorted { a, b in
            let aIsDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let bIsDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if aIsDir != bIsDir { return aIsDir }
            return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
        }

        return sorted.map { childURL -> FileNode in
            var node = FileNode(url: childURL)
            if node.isDirectory && expandedUrls.contains(childURL) {
                node.isExpanded = true
                node.children = loadChildren(at: childURL, expandedUrls: expandedUrls)
            } else if node.isDirectory {
                node.children = nil  // lazy load on expand
            }
            return node
        }
    }

    // MARK: - Expand / Collapse

    private var lastToggleTimes: [UUID: Date] = [:]
    private let toggleDebounceInterval: TimeInterval = 0.3

    func toggleExpand(nodeId: UUID) {
        let now = Date()
        if let last = lastToggleTimes[nodeId], now.timeIntervalSince(last) < toggleDebounceInterval {
            return
        }
        lastToggleTimes[nodeId] = now
        toggleExpandInTree(&rootNodes, nodeId: nodeId)
    }

    private func toggleExpandInTree(_ nodes: inout [FileNode], nodeId: UUID) {
        for i in nodes.indices {
            if nodes[i].id == nodeId {
                nodes[i].isExpanded.toggle()
                if nodes[i].isExpanded && nodes[i].children == nil {
                    nodes[i].children = loadChildren(at: nodes[i].url, expandedUrls: [])
                }
                return
            }
            if nodes[i].children != nil {
                toggleExpandInTree(&nodes[i].children!, nodeId: nodeId)
            }
        }
    }

    // MARK: - Visible Nodes (flat list with depth for the scroll view)

    var visibleNodes: [(node: FileNode, depth: Int)] {
        var result: [(FileNode, Int)] = []
        let source = filterText.isEmpty ? rootNodes : filteredNodes
        collectVisible(from: source, depth: 0, into: &result)
        return result
    }

    private var filteredNodes: [FileNode] {
        let query = filterText.lowercased()
        return filterTree(nodes: rootNodes, query: query)
    }

    private func filterTree(nodes: [FileNode], query: String) -> [FileNode] {
        var result: [FileNode] = []
        for node in nodes {
            if node.name.lowercased().contains(query) {
                result.append(node)
            } else if node.isExpanded, let children = node.children {
                let filtered = filterTree(nodes: children, query: query)
                if !filtered.isEmpty {
                    var copy = node
                    copy.children = filtered
                    result.append(copy)
                }
            }
        }
        return result
    }

    private func collectVisible(from nodes: [FileNode], depth: Int, into result: inout [(FileNode, Int)]) {
        for node in nodes {
            result.append((node, depth))
            if node.isExpanded, let children = node.children {
                collectVisible(from: children, depth: depth + 1, into: &result)
            }
        }
    }

    // MARK: - Hidden Files Toggle

    func toggleHiddenFiles() {
        showHiddenFiles.toggle()
        reload()
    }

    // MARK: - Recursive Filter (Cmd+F mode)

    func activateRecursiveFilter() {
        guard !isRecursiveFilter else { return }
        isRecursiveFilter = true
        savedExpandedUrls = currentExpandedUrls()
        expandAll(&rootNodes)
    }

    func deactivateRecursiveFilter() {
        guard isRecursiveFilter else { return }
        isRecursiveFilter = false
        filterText = ""
        collapseToSaved(&rootNodes, savedUrls: savedExpandedUrls)
        savedExpandedUrls = []
    }

    private func expandAll(_ nodes: inout [FileNode]) {
        for i in nodes.indices where nodes[i].isDirectory {
            if nodes[i].children == nil {
                nodes[i].children = loadChildren(at: nodes[i].url, expandedUrls: [])
            }
            nodes[i].isExpanded = true
            if nodes[i].children != nil {
                expandAll(&nodes[i].children!)
            }
        }
    }

    private func collapseToSaved(_ nodes: inout [FileNode], savedUrls: Set<URL>) {
        for i in nodes.indices where nodes[i].isDirectory {
            nodes[i].isExpanded = savedUrls.contains(nodes[i].url)
            if nodes[i].children != nil {
                collapseToSaved(&nodes[i].children!, savedUrls: savedUrls)
            }
        }
    }

    // MARK: - Git Status

    func refreshGitStatus() async {
        let statuses = await GitStatusService.fetchStatus(rootDir: rootDir)
        await MainActor.run { gitStatuses = statuses }
    }

    /// Returns git status for a URL; for directories returns max of children's statuses
    func gitStatus(for url: URL) -> GitStatus? {
        if let direct = gitStatuses[url.path] { return direct }
        let prefix = url.path + "/"
        return gitStatuses
            .filter { $0.key.hasPrefix(prefix) }
            .values
            .max()
    }

    // MARK: - File Operations

    func createFile(inDirectory dirURL: URL, name: String) {
        let target = dirURL.appendingPathComponent(name)
        FileManager.default.createFile(atPath: target.path, contents: nil)
    }

    func createDirectory(inDirectory dirURL: URL, name: String) {
        let target = dirURL.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    }

    func rename(url: URL, to newName: String) {
        let target = url.deletingLastPathComponent().appendingPathComponent(newName)
        try? FileManager.default.moveItem(at: url, to: target)
        renamingURL = nil
        reload()
    }

    func delete(url: URL) {
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    func copyPath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    func openInDefaultApp(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// 批量删除选中项，返回无法删除的文件名列表（供 UI 层汇总展示）
    @discardableResult
    func deleteSelected() -> [String] {
        let urls = selectedNodeIds.compactMap { findNodeURL(id: $0) }
        // 过滤：如果某 URL 的父路径链上已有另一个被选中的目录，跳过它（随父一起删除）
        let filteredURLs = urls.filter { url in
            !urls.contains(where: { parent in
                parent != url && parent.hasDirectoryPath &&
                url.standardized.path.hasPrefix(parent.standardized.path + "/")
            })
        }
        var errors: [String] = []
        for url in filteredURLs {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                errors.append(url.lastPathComponent)
            }
        }
        clearSelection()
        return errors
    }

    /// 批量移动，前置校验子目录和写权限，返回无法移动的文件名列表
    @discardableResult
    func move(urls: [URL], to destination: URL) -> [String] {
        // 校验：目标不能是被移动目录的子路径
        for url in urls where url.hasDirectoryPath {
            let destStd = destination.standardized
            let urlStd = url.standardized
            if destStd.path.hasPrefix(urlStd.path + "/") || destStd.path == urlStd.path {
                return ["目标路径不合法：不能移动到自身子目录"]
            }
        }
        // 校验：目标目录可写
        guard FileManager.default.isWritableFile(atPath: destination.path) else {
            return ["目标目录无写入权限"]
        }

        var errors: [String] = []
        var failedURLs = Set<URL>()
        for url in urls {
            let target = destination.appendingPathComponent(url.lastPathComponent)
            do {
                try FileManager.default.moveItem(at: url, to: target)
            } catch {
                errors.append(url.lastPathComponent)
                failedURLs.insert(url)
            }
        }
        // 仅清除成功移动项的选中状态，失败项保留高亮（用 URL 直接判断，避免同名文件误判）
        selectedNodeIds = selectedNodeIds.filter { id in
            guard let url = findNodeURL(id: id) else { return false }
            return failedURLs.contains(url)
        }
        if selectedNodeIds.isEmpty {
            lastSelectedId = nil
            showPreviewPanel = false
            isPreviewFullscreen = false
        } else if let last = lastSelectedId, !selectedNodeIds.contains(last) {
            lastSelectedId = nil
        }
        return errors
    }

    // MARK: - Selection

    func selectNode(id: UUID?) {
        if let id {
            selectedNodeIds = [id]
            lastSelectedId = id
            let node = findNodeInTree(id: id, nodes: rootNodes)
            if let node, !node.isDirectory {
                showPreviewPanel = true
            } else {
                showPreviewPanel = false
                isPreviewFullscreen = false
            }
        } else {
            clearSelection()
        }
    }

    func toggleSelection(id: UUID) {
        if selectedNodeIds.contains(id) {
            selectedNodeIds.remove(id)
            if lastSelectedId == id {
                lastSelectedId = nil   // Set 无序，不用 .first 避免不确定性；nil 表示"无主选"
            }
        } else {
            selectedNodeIds.insert(id)
            lastSelectedId = id
        }
        // 多选时关闭预览面板
        if selectedNodeIds.count != 1 {
            showPreviewPanel = false
            isPreviewFullscreen = false
        }
    }

    func extendSelection(to targetId: UUID) {
        guard let anchorId = lastSelectedId else {
            selectNode(id: targetId)
            return
        }
        let nodes = visibleNodes
        guard let anchorIdx = nodes.firstIndex(where: { $0.node.id == anchorId }),
              let targetIdx = nodes.firstIndex(where: { $0.node.id == targetId }) else { return }
        let range = min(anchorIdx, targetIdx)...max(anchorIdx, targetIdx)
        let rangeIds = Set(nodes[range].map { $0.node.id })
        selectedNodeIds = rangeIds
        lastSelectedId = targetId
        showPreviewPanel = false
        isPreviewFullscreen = false
    }

    func clearSelection() {
        selectedNodeIds = []
        lastSelectedId = nil
        showPreviewPanel = false
        isPreviewFullscreen = false
    }

    func selectAll() {
        let nodes = visibleNodes
        selectedNodeIds = Set(nodes.map { $0.node.id })
        lastSelectedId = nodes.last?.node.id
        showPreviewPanel = false
        isPreviewFullscreen = false
    }

    // MARK: - Preview

    func togglePreviewPanel() {
        showPreviewPanel.toggle()
        if !showPreviewPanel {
            isPreviewFullscreen = false
        }
    }

    func togglePreviewFullscreen() {
        isPreviewFullscreen.toggle()
    }

    /// URLs corresponding to current selection (computed for SwiftUI use)
    var selectedURLs: [URL] {
        selectedNodeIds.compactMap { findNodeURL(id: $0) }
    }

    /// Find the URL for a given node ID
    func findNodeURL(id: UUID) -> URL? {
        findNodeInTree(id: id, nodes: rootNodes)?.url
    }

    private func findNodeInTree(id: UUID, nodes: [FileNode]) -> FileNode? {
        for node in nodes {
            if node.id == id { return node }
            if let children = node.children,
               let found = findNodeInTree(id: id, nodes: children) {
                return found
            }
        }
        return nil
    }

    /// Find node by URL (used to restore selection after reload)
    private func findNodeByURL(url: URL, in nodes: [FileNode]) -> FileNode? {
        for node in nodes {
            if node.url == url { return node }
            if let children = node.children,
               let found = findNodeByURL(url: url, in: children) {
                return found
            }
        }
        return nil
    }

    // MARK: - Keyboard Navigation

    func selectNext() {
        let nodes = visibleNodes
        guard !nodes.isEmpty else { return }
        if let id = lastSelectedId,
           let idx = nodes.firstIndex(where: { $0.node.id == id }) {
            selectNode(id: nodes[min(idx + 1, nodes.count - 1)].node.id)
        } else {
            selectNode(id: nodes[0].node.id)
        }
    }

    func selectPrevious() {
        let nodes = visibleNodes
        guard !nodes.isEmpty else { return }
        if let id = lastSelectedId,
           let idx = nodes.firstIndex(where: { $0.node.id == id }) {
            selectNode(id: nodes[max(idx - 1, 0)].node.id)
        } else {
            selectNode(id: nodes[0].node.id)
        }
    }
}
