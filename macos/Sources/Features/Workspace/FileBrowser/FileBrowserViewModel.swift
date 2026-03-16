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
    @Published var renamingNodeId: UUID? = nil

    // Preview state
    @Published var selectedNodeId: UUID? = nil
    @Published var showPreviewPanel: Bool = false
    @Published var isPreviewFullscreen: Bool = false

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
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard !self.rootDir.isEmpty, FileManager.default.fileExists(atPath: self.rootDir) else {
                self.rootNodes = []
                return
            }

            // Preserve selected file URL across reload
            let selectedURL = self.selectedNodeId.flatMap { self.findNodeURL(id: $0) }

            let expanded = self.currentExpandedUrls()
            self.rootNodes = self.loadChildren(at: URL(fileURLWithPath: self.rootDir), expandedUrls: expanded)

            // Restore selection by URL
            if let url = selectedURL, let newNode = self.findNodeByURL(url: url, in: self.rootNodes) {
                self.selectedNodeId = newNode.id
            } else if selectedURL != nil {
                // Selected file was deleted
                self.selectedNodeId = nil
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

    func toggleExpand(nodeId: UUID) {
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
        renamingNodeId = nil
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

    // MARK: - Preview

    func selectNode(id: UUID?) {
        selectedNodeId = id
        if let id, let node = findNodeInTree(id: id, nodes: rootNodes), !node.isDirectory {
            showPreviewPanel = true
        }
    }

    func togglePreviewPanel() {
        showPreviewPanel.toggle()
        if !showPreviewPanel {
            isPreviewFullscreen = false
        }
    }

    func togglePreviewFullscreen() {
        isPreviewFullscreen.toggle()
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
}
