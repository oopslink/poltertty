# File Browser Panel Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Workspace 的 Sidebar 和 Terminal 之间插入文件浏览器面板，展示当前 Workspace 的 rootDir 目录树，支持 Git 状态标注、FSEvents 实时监控、文件操作和终端联动。

**Architecture:** 6 个新文件放在 `FileBrowser/` 子目录，`FileBrowserViewModel` 由 `WorkspaceManager` 以字典持有（per-workspace），面板可见性/宽度持久化在 `WorkspaceModel` 中。

**Tech Stack:** Swift 6, SwiftUI, AppKit, CoreServices (FSEvents), Foundation (Process for git)

---

## 文件结构

### 新建文件
- `macos/Sources/Features/Workspace/FileBrowser/FileNode.swift` — 数据模型 struct + GitStatus enum
- `macos/Sources/Features/Workspace/FileBrowser/GitStatusService.swift` — 异步跑 `git status --porcelain`
- `macos/Sources/Features/Workspace/FileBrowser/FileSystemMonitor.swift` — FSEventStream 封装
- `macos/Sources/Features/Workspace/FileBrowser/FileBrowserViewModel.swift` — @MainActor ObservableObject
- `macos/Sources/Features/Workspace/FileBrowser/FileNodeRow.swift` — 单行视图
- `macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift` — 主容器视图

### 修改文件
- `macos/Sources/Features/Workspace/WorkspaceModel.swift` — 新增 fileBrowserVisible/fileBrowserWidth 字段
- `macos/Sources/Features/Workspace/WorkspaceManager.swift` — 新增 fileBrowserViewModels 字典
- `macos/Sources/Features/Workspace/PolterttyRootView.swift` — 插入面板，新增 notification，accessor vars
- `macos/Sources/Features/Terminal/TerminalController.swift` — injectToActiveSurface，saveSnapshot 更新，窗口生命周期
- `macos/Sources/App/macOS/AppDelegate.swift` — Cmd+\ 菜单项

---

## Chunk 1: 数据模型 + 服务层

### Task 1: FileNode.swift + GitStatus

**Files:**
- Create: `macos/Sources/Features/Workspace/FileBrowser/FileNode.swift`

- [ ] **Step 1: 创建 FileNode.swift**

```swift
// macos/Sources/Features/Workspace/FileBrowser/FileNode.swift
import Foundation

enum GitStatus: Int, Comparable {
    case untracked = 0   // ?
    case added = 1       // A
    case modified = 2    // M
    case deleted = 3     // D — 最高优先级

    static func < (lhs: GitStatus, rhs: GitStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var symbol: String {
        switch self {
        case .untracked: return "?"
        case .added:     return "A"
        case .modified:  return "M"
        case .deleted:   return "D"
        }
    }

    var colorHex: String {
        switch self {
        case .untracked: return "#9ca3af"
        case .added:     return "#4ade80"
        case .modified:  return "#facc15"
        case .deleted:   return "#f87171"
        }
    }
}

struct FileNode: Identifiable {
    let id: UUID
    let url: URL
    var isDirectory: Bool
    var isExpanded: Bool = false
    var children: [FileNode]?  // nil = 目录但未加载；[] = 空目录或文件
    var gitStatus: GitStatus?

    init(url: URL) {
        self.id = UUID()
        self.url = url
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue
    }

    var name: String { url.lastPathComponent }
    var isHidden: Bool { name.hasPrefix(".") }
}
```

- [ ] **Step 2: 编译检查**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep "FileBrowser/FileNode.swift" | grep "error:"
```

Expected: 无 error 输出

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/FileNode.swift
git commit -m "feat(file-browser): add FileNode data model and GitStatus enum"
```

---

### Task 2: GitStatusService.swift

**Files:**
- Create: `macos/Sources/Features/Workspace/FileBrowser/GitStatusService.swift`

- [ ] **Step 1: 创建 GitStatusService.swift**

```swift
// macos/Sources/Features/Workspace/FileBrowser/GitStatusService.swift
import Foundation

struct GitStatusService {
    /// 异步跑 `git -C rootDir status --porcelain`，返回 [absolutePath: GitStatus]
    /// rootDir 不是 git repo 时（exit code ≠ 0）静默返回空字典
    static func fetchStatus(rootDir: String) async -> [String: GitStatus] {
        guard !rootDir.isEmpty else { return [:] }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: fetchStatusSync(rootDir: rootDir))
            }
        }
    }

    private static func fetchStatusSync(rootDir: String) -> [String: GitStatus] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", rootDir, "status", "--porcelain"]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return [:]
        }

        guard process.terminationStatus == 0 else { return [:] }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [:] }

        var result: [String: GitStatus] = [:]
        for line in output.components(separatedBy: "\n") {
            guard line.count >= 3 else { continue }
            let chars = Array(line)
            let x = chars[0]
            let y = chars[1]
            // space after XY
            let path = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { continue }

            // Handle rename: "old -> new", take the new path
            let effectivePath: String
            if path.contains(" -> ") {
                effectivePath = String(path.split(separator: " ").last ?? Substring(path))
            } else {
                effectivePath = path
            }

            let fullPath = (rootDir as NSString).appendingPathComponent(effectivePath)

            // Untracked: either column is '?'
            if x == "?" || y == "?" {
                result[fullPath] = .untracked
                continue
            }

            // Working-tree column (Y) takes priority over index (X)
            let effectiveChar: Character
            if y != " " && y != "-" {
                effectiveChar = y
            } else {
                effectiveChar = x
            }

            switch effectiveChar {
            case "M", "m": result[fullPath] = .modified
            case "A":       result[fullPath] = .added
            case "D":       result[fullPath] = .deleted
            default:        break
            }
        }
        return result
    }
}
```

- [ ] **Step 2: 编译检查**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep "GitStatusService.swift" | grep "error:"
```

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/GitStatusService.swift
git commit -m "feat(file-browser): add GitStatusService for async git status parsing"
```

---

### Task 3: FileSystemMonitor.swift

**Files:**
- Create: `macos/Sources/Features/Workspace/FileBrowser/FileSystemMonitor.swift`

- [ ] **Step 1: 创建 FileSystemMonitor.swift**

```swift
// macos/Sources/Features/Workspace/FileBrowser/FileSystemMonitor.swift
import Foundation
import CoreServices

/// FSEventStream 封装，监听 rootDir 的文件系统变更，带 300ms debounce。
/// 调用方在主线程接收 onChange 回调。
final class FileSystemMonitor {
    private var stream: FSEventStreamRef?
    private let rootDir: String
    private let queue = DispatchQueue(label: "poltertty.fsevents", qos: .utility)
    private var debounceWorkItem: DispatchWorkItem?

    /// 收到变更通知（主线程回调）
    var onChange: (() -> Void)?

    init(rootDir: String) {
        self.rootDir = rootDir
    }

    deinit {
        stop()
    }

    func start() {
        guard !rootDir.isEmpty,
              FileManager.default.fileExists(atPath: rootDir),
              stream == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let paths = [rootDir] as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let monitor = Unmanaged<FileSystemMonitor>.fromOpaque(info).takeUnretainedValue()
            monitor.scheduleReload()
        }

        guard let newStream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,  // latency — further debounce handled in scheduleReload
            flags
        ) else { return }

        stream = newStream
        FSEventStreamSetDispatchQueue(newStream, queue)
        FSEventStreamStart(newStream)
    }

    func stop() {
        debounceWorkItem?.cancel()
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    private func scheduleReload() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                self?.onChange?()
            }
        }
        debounceWorkItem = item
        queue.asyncAfter(deadline: .now() + 0.3, execute: item)
    }
}
```

- [ ] **Step 2: 编译检查**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep "FileSystemMonitor.swift" | grep "error:"
```

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/FileSystemMonitor.swift
git commit -m "feat(file-browser): add FileSystemMonitor with FSEventStream and debounce"
```

---

## Chunk 2: ViewModel

### Task 4: FileBrowserViewModel.swift

**Files:**
- Create: `macos/Sources/Features/Workspace/FileBrowser/FileBrowserViewModel.swift`

- [ ] **Step 1: 创建 FileBrowserViewModel.swift**

```swift
// macos/Sources/Features/Workspace/FileBrowser/FileBrowserViewModel.swift
import Foundation
import AppKit

@MainActor
final class FileBrowserViewModel: ObservableObject {
    // MARK: - Published State

    @Published var rootNodes: [FileNode] = []
    @Published var gitStatuses: [String: GitStatus] = [:]
    @Published var filterText: String = ""
    @Published var showHiddenFiles: Bool = false
    @Published var isVisible: Bool
    @Published var panelWidth: CGFloat
    @Published var renamingNodeId: UUID? = nil

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

    /// Workspace 切换到后台时暂停
    func pause() {
        monitor?.stop()
    }

    /// Workspace 激活时恢复并强制 reload
    func resume() {
        monitor?.start()
        reload()
    }

    /// Workspace 销毁时停止
    func stop() {
        monitor?.stop()
    }

    // MARK: - Reload

    func reload() {
        guard !rootDir.isEmpty, FileManager.default.fileExists(atPath: rootDir) else {
            rootNodes = []
            return
        }
        let expanded = currentExpandedUrls()
        rootNodes = loadChildren(at: URL(fileURLWithPath: rootDir), expandedUrls: expanded)
        Task { await refreshGitStatus() }
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

        // Sort: directories first, then alphabetical (case-insensitive)
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
                node.children = nil  // lazy: will load on expand
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

    // MARK: - Visible Nodes (flat list with depth)

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

    // MARK: - Hidden Files

    func toggleHiddenFiles() {
        showHiddenFiles.toggle()
        reload()
    }

    // MARK: - Recursive Filter

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
        gitStatuses = statuses
    }

    /// 返回某 URL 的 git 状态（目录：取子节点最高优先级）
    func gitStatus(for url: URL) -> GitStatus? {
        if let direct = gitStatuses[url.path] { return direct }
        // Directory: find max status among children
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
}
```

- [ ] **Step 2: 编译检查**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep "FileBrowserViewModel.swift" | grep "error:"
```

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/FileBrowserViewModel.swift
git commit -m "feat(file-browser): add FileBrowserViewModel with tree management, filter, git status"
```

---

## Chunk 3: UI 组件

### Task 5: FileNodeRow.swift

**Files:**
- Create: `macos/Sources/Features/Workspace/FileBrowser/FileNodeRow.swift`

- [ ] **Step 1: 创建 FileNodeRow.swift**

```swift
// macos/Sources/Features/Workspace/FileBrowser/FileNodeRow.swift
import SwiftUI
import AppKit

struct FileNodeRow: View {
    let node: FileNode
    let depth: Int
    let gitStatus: GitStatus?
    let isSelected: Bool
    let onToggleExpand: () -> Void
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void
    let onOpenInTerminal: () -> Void
    let onCopyPath: () -> Void
    let onNewFile: () -> Void
    let onNewDirectory: () -> Void
    let onDelete: () -> Void
    let onStartRename: () -> Void

    // Rename state — controlled by parent (FileBrowserPanel)
    var isRenaming: Bool = false
    var renameText: Binding<String>? = nil
    var onCommitRename: ((String) -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            // Indentation
            Rectangle()
                .fill(.clear)
                .frame(width: CGFloat(depth) * 16, height: 1)

            // Chevron for directories
            if node.isDirectory {
                Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .frame(width: 12)
                    .foregroundColor(.secondary)
                    .contentShape(Rectangle())
                    .onTapGesture { onToggleExpand() }
            } else {
                Spacer().frame(width: 12)
            }

            // File/folder icon from NSWorkspace
            FileIconView(url: node.url)
                .frame(width: 16, height: 16)

            // Name or rename TextField
            if isRenaming, let binding = renameText {
                TextField("", text: binding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        if !binding.wrappedValue.isEmpty {
                            onCommitRename?(binding.wrappedValue)
                        }
                    }
            } else {
                Text(node.name)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Git status badge
            if let status = gitStatus {
                Text(status.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: status.colorHex) ?? .secondary)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.2)
                : Color.clear
        )
        .contentShape(Rectangle())
        .gesture(
            TapGesture(count: 2).onEnded { onDoubleClick() }
        )
        .simultaneousGesture(
            TapGesture(count: 1).onEnded { onSingleClick() }
        )
        .contextMenu {
            Button("Open in Terminal") { onOpenInTerminal() }
            Button("Copy Path") { onCopyPath() }
            Divider()
            Button("New File") { onNewFile() }
            Button("New Directory") { onNewDirectory() }
            Divider()
            Button("Rename") { onStartRename() }
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}

// MARK: - File Icon

private struct FileIconView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyDown
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = NSWorkspace.shared.icon(forFile: url.path)
    }
}
```

- [ ] **Step 2: 编译检查**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep "FileNodeRow.swift" | grep "error:"
```

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/FileNodeRow.swift
git commit -m "feat(file-browser): add FileNodeRow with icons, git badge, context menu, inline rename"
```

---

### Task 6: FileBrowserPanel.swift

**Files:**
- Create: `macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift`

- [ ] **Step 1: 创建 FileBrowserPanel.swift**

```swift
// macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift
import SwiftUI
import AppKit

struct FileBrowserPanel: View {
    @ObservedObject var viewModel: FileBrowserViewModel
    var onOpenInTerminal: ((URL) -> Void)?

    @State private var selectedNodeId: UUID? = nil
    @State private var renameText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            if viewModel.rootDir.isEmpty || !FileManager.default.fileExists(atPath: viewModel.rootDir) {
                emptyStateView
            } else {
                treeScrollView
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .focusable()
        .focused($isFocused)
        // Keyboard shortcuts — only fire when panel is focused
        .onKeyPress(".") {
            if isFocused {
                viewModel.toggleHiddenFiles()
                return .handled
            }
            return .ignored
        }
        .onKeyPress("t") {
            if isFocused, let nodeId = selectedNodeId,
               let entry = viewModel.visibleNodes.first(where: { $0.node.id == nodeId }) {
                onOpenInTerminal?(entry.node.url)
                return .handled
            }
            return .ignored
        }
        .onKeyPress("r") {
            if isFocused, let nodeId = selectedNodeId {
                if let entry = viewModel.visibleNodes.first(where: { $0.node.id == nodeId }) {
                    renameText = entry.node.name
                    viewModel.renamingNodeId = nodeId
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress("n") {
            if isFocused, let nodeId = selectedNodeId,
               let entry = viewModel.visibleNodes.first(where: { $0.node.id == nodeId }) {
                let dir = entry.node.isDirectory ? entry.node.url : entry.node.url.deletingLastPathComponent()
                viewModel.createFile(inDirectory: dir, name: "untitled")
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.init("N"), modifiers: .shift) {
            if isFocused, let nodeId = selectedNodeId,
               let entry = viewModel.visibleNodes.first(where: { $0.node.id == nodeId }) {
                let dir = entry.node.isDirectory ? entry.node.url : entry.node.url.deletingLastPathComponent()
                viewModel.createDirectory(inDirectory: dir, name: "untitled")
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.delete, modifiers: .command) {
            if isFocused, let nodeId = selectedNodeId,
               let entry = viewModel.visibleNodes.first(where: { $0.node.id == nodeId }) {
                viewModel.delete(url: entry.node.url)
                selectedNodeId = nil
                return .handled
            }
            return .ignored
        }
        .onKeyPress("c", modifiers: [.command, .shift]) {
            if isFocused, let nodeId = selectedNodeId,
               let entry = viewModel.visibleNodes.first(where: { $0.node.id == nodeId }) {
                viewModel.copyPath(entry.node.url)
                return .handled
            }
            return .ignored
        }
        .onKeyPress("f", modifiers: .command) {
            if isFocused {
                viewModel.activateRecursiveFilter()
                return .handled
            }
            return .ignored
        }
        .onChange(of: viewModel.filterText) { text in
            if text.isEmpty {
                viewModel.deactivateRecursiveFilter()
            }
        }
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
                .foregroundColor(.secondary.opacity(0.5))
            Text(viewModel.rootDir.isEmpty ? "No directory set" : "Directory not found")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tree View

    private var treeScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.visibleNodes, id: \.node.id) { entry in
                    FileNodeRow(
                        node: entry.node,
                        depth: entry.depth,
                        gitStatus: viewModel.gitStatus(for: entry.node.url),
                        isSelected: selectedNodeId == entry.node.id,
                        onToggleExpand: {
                            viewModel.toggleExpand(nodeId: entry.node.id)
                        },
                        onSingleClick: {
                            selectedNodeId = entry.node.id
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
                            if selectedNodeId == entry.node.id { selectedNodeId = nil }
                        },
                        onStartRename: {
                            renameText = entry.node.name
                            viewModel.renamingNodeId = entry.node.id
                        },
                        isRenaming: viewModel.renamingNodeId == entry.node.id,
                        renameText: viewModel.renamingNodeId == entry.node.id
                            ? Binding(
                                get: { renameText },
                                set: { renameText = $0 }
                            )
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
```

- [ ] **Step 2: 编译检查**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep "FileBrowserPanel.swift" | grep "error:"
```

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift
git commit -m "feat(file-browser): add FileBrowserPanel with filter bar, tree view, keyboard shortcuts"
```

---

## Chunk 4: 数据持久化 + ViewModel 所有权

### Task 7: WorkspaceModel — 新增持久化字段

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceModel.swift`

- [ ] **Step 1: 在 WorkspaceModel 中新增字段**

在 `isTemporary` 字段之后新增：

```swift
    var fileBrowserVisible: Bool = false
    var fileBrowserWidth: CGFloat = 260
```

在 `init(from decoder:)` 中，在 `isTemporary` 行之后新增：

```swift
        fileBrowserVisible = try container.decodeIfPresent(Bool.self, forKey: .fileBrowserVisible) ?? false
        fileBrowserWidth   = try container.decodeIfPresent(CGFloat.self, forKey: .fileBrowserWidth) ?? 260
```

在 `CodingKeys` enum（编译器合成的 Codable 会包含所有 stored properties）。
**注意**：`WorkspaceModel` 使用合成 `encode(to:)` 和手写 `init(from:)`。只需要在手写 decoder 中加 `decodeIfPresent`，encode 是自动的。

完整修改后的 `init(from decoder:)` 尾部：

```swift
        isTemporary = try container.decodeIfPresent(Bool.self, forKey: .isTemporary) ?? false
        fileBrowserVisible = try container.decodeIfPresent(Bool.self, forKey: .fileBrowserVisible) ?? false
        fileBrowserWidth   = try container.decodeIfPresent(CGFloat.self, forKey: .fileBrowserWidth) ?? 260
```

- [ ] **Step 2: 编译检查**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep "WorkspaceModel.swift" | grep "error:"
```

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceModel.swift
git commit -m "feat(file-browser): add fileBrowserVisible/Width fields to WorkspaceModel with decodeIfPresent"
```

---

### Task 8: WorkspaceManager — ViewModel 字典

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceManager.swift`

- [ ] **Step 1: 新增 fileBrowserViewModels 字典和访问方法**

在 `activeWindows` 之后新增：

```swift
    // MARK: - File Browser ViewModels (per-workspace)

    private var fileBrowserViewModels: [UUID: FileBrowserViewModel] = [:]

    @MainActor
    func fileBrowserViewModel(for workspaceId: UUID) -> FileBrowserViewModel {
        if let existing = fileBrowserViewModels[workspaceId] { return existing }
        let ws = workspace(for: workspaceId)
        let vm = FileBrowserViewModel(
            rootDir: ws?.rootDirExpanded ?? "",
            isVisible: ws?.fileBrowserVisible ?? false,
            panelWidth: ws?.fileBrowserWidth ?? 260
        )
        fileBrowserViewModels[workspaceId] = vm
        return vm
    }

    @MainActor
    func removeFileBrowserViewModel(for workspaceId: UUID) {
        fileBrowserViewModels[workspaceId]?.stop()
        fileBrowserViewModels.removeValue(forKey: workspaceId)
    }
```

- [ ] **Step 2: 在 delete(id:) 中调用 removeFileBrowserViewModel**

在 `delete(id:)` 方法中，`workspaces.removeAll` 之后添加：

```swift
    func delete(id: UUID) {
        workspaces.removeAll { $0.id == id }
        activeWindows.removeValue(forKey: id)
        Task { @MainActor in
            removeFileBrowserViewModel(for: id)
        }
        let path = snapshotPath(for: id)
        try? FileManager.default.removeItem(atPath: path)
    }
```

- [ ] **Step 3: 编译检查**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep "WorkspaceManager.swift" | grep "error:"
```

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceManager.swift
git commit -m "feat(file-browser): add fileBrowserViewModels dictionary to WorkspaceManager"
```

---

## Chunk 5: UI 集成 — PolterttyRootView

### Task 9: PolterttyRootView — 插入面板

**Files:**
- Modify: `macos/Sources/Features/Workspace/PolterttyRootView.swift`

- [ ] **Step 1: 新增 toggleFileBrowser Notification.Name**

在 `toggleWorkspaceSidebar` 等 Notification.Name 之后添加：

```swift
    static let toggleFileBrowser = Notification.Name("poltertty.toggleFileBrowser")
```

- [ ] **Step 2: 新增 @State 和 @StateObject**

在 `PolterttyRootView` 结构体中，在已有 `@State private var sidebarVisible` 等之后添加：

```swift
    @StateObject private var fileBrowserVM: FileBrowserViewModel = {
        // 在 body 渲染前无法访问 workspaceId，通过 onAppear 初始化
        // 这里提供一个空占位；实际值在 onAppear 中由 WorkspaceManager 提供
        FileBrowserViewModel(rootDir: "")
    }()
```

**注意**：Swift 的 `@StateObject` 只初始化一次。正确做法是用 `init` 注入，而非 body 中计算。修改如下：

将上面的 `@StateObject` 替换为 `@ObservedObject`，并在 `init` 中获取 ViewModel：

```swift
    // 改为 @ObservedObject，ViewModel 由 WorkspaceManager 拥有
    @ObservedObject private var fileBrowserVM: FileBrowserViewModel
```

修改 `PolterttyRootView` 的 `init`（当前没有显式 init，需要新增）：

```swift
    init(
        workspaceId: UUID?,
        terminalView: TerminalContent,
        onSwitchWorkspace: @escaping (UUID) -> Void,
        onCloseWorkspace: @escaping (UUID) -> Void,
        initialStartupMode: WorkspaceStartupMode,
        onCreateFormalWorkspace: ((_ name: String, _ rootDir: String, _ colorHex: String, _ description: String) -> Void)?,
        onCreateTemporaryWorkspace: (() -> Void)?,
        onRestoreWorkspaces: (([UUID]) -> Void)?,
        onCreateTemporary: (() -> Void)?
    ) {
        self.workspaceId = workspaceId
        self.terminalView = terminalView
        self.onSwitchWorkspace = onSwitchWorkspace
        self.onCloseWorkspace = onCloseWorkspace
        self.initialStartupMode = initialStartupMode
        self.onCreateFormalWorkspace = onCreateFormalWorkspace
        self.onCreateTemporaryWorkspace = onCreateTemporaryWorkspace
        self.onRestoreWorkspaces = onRestoreWorkspaces
        self.onCreateTemporary = onCreateTemporary

        // Initialize fileBrowserVM from WorkspaceManager
        if let wsId = workspaceId {
            self._fileBrowserVM = ObservedObject(
                wrappedValue: WorkspaceManager.shared.fileBrowserViewModel(for: wsId)
            )
        } else {
            self._fileBrowserVM = ObservedObject(
                wrappedValue: FileBrowserViewModel(rootDir: "")
            )
        }
    }
```

**重要**：`WorkspaceManager.fileBrowserViewModel(for:)` 被标注为 `@MainActor`，而 `init` 不是。需要将该方法的 `@MainActor` 去掉，改为不加注解（WorkspaceManager 不是 actor，线程安全由调用方保证）。在 `WorkspaceManager.swift` 中，去掉这两个方法的 `@MainActor` 注解：

```swift
    func fileBrowserViewModel(for workspaceId: UUID) -> FileBrowserViewModel { ... }
    func removeFileBrowserViewModel(for workspaceId: UUID) { ... }
```

同时，`FileBrowserViewModel` 是 `@MainActor` class，所以从非 main actor 调用其 init 可能产生编译错误。解决方案：将 `FileBrowserViewModel` 不标注 `@MainActor`，而是内部用 `DispatchQueue.main.async` 或 `MainActor.run` 保护 `@Published` 更新。

**架构调整**：将 `FileBrowserViewModel` 改为普通 class（去掉 `@MainActor`），在 `reload()` 和 git 更新时确保主线程：

```swift
// FileBrowserViewModel.swift — 去掉 @MainActor，改为内部保证主线程
final class FileBrowserViewModel: ObservableObject {
    // ... 其余不变

    func reload() {
        // 可在任意线程调用，dispatch 到主线程更新 @Published
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard !self.rootDir.isEmpty, FileManager.default.fileExists(atPath: self.rootDir) else {
                self.rootNodes = []
                return
            }
            let expanded = self.currentExpandedUrls()
            self.rootNodes = self.loadChildren(at: URL(fileURLWithPath: self.rootDir), expandedUrls: expanded)
            Task { await self.refreshGitStatus() }
        }
    }

    // refreshGitStatus 用 Task + MainActor.run
    func refreshGitStatus() async {
        let statuses = await GitStatusService.fetchStatus(rootDir: rootDir)
        await MainActor.run { gitStatuses = statuses }
    }
}
```

- [ ] **Step 3: 在 terminal mode HStack 中插入 FileBrowserPanel**

将 terminal mode case 的 HStack 修改为：

```swift
            case .terminal:
                HStack(spacing: 0) {
                    // Sidebar
                    if sidebarVisible {
                        WorkspaceSidebar(...)
                        .frame(width: effectiveSidebarWidth)
                        Divider()
                    }

                    // File Browser Panel
                    if fileBrowserVM.isVisible {
                        FileBrowserPanel(
                            viewModel: fileBrowserVM,
                            onOpenInTerminal: { [self] url in
                                // 注入 cd 命令到 terminal — 通过 notification 传递给 TerminalController
                                NotificationCenter.default.post(
                                    name: .fileBrowserOpenInTerminal,
                                    object: nil,
                                    userInfo: [
                                        "workspaceId": workspaceId as Any,
                                        "path": url.path
                                    ]
                                )
                            }
                        )
                        .frame(width: fileBrowserVM.panelWidth)

                        panelDivider
                    }

                    // Terminal view
                    terminalView
                }
```

同时新增 Notification.Name：

```swift
    static let fileBrowserOpenInTerminal = Notification.Name("poltertty.fileBrowserOpenInTerminal")
```

新增 `panelDivider`：

```swift
    private var panelDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newWidth = fileBrowserVM.panelWidth + value.translation.width
                                fileBrowserVM.panelWidth = max(160, min(600, newWidth))
                            }
                    )
            )
    }
```

- [ ] **Step 4: 接收 toggleFileBrowser 通知**

在 `.onReceive` 链中添加：

```swift
        .onReceive(NotificationCenter.default.publisher(for: .toggleFileBrowser)) { notification in
            guard let wsId = notification.userInfo?["workspaceId"] as? UUID,
                  wsId == workspaceId else { return }
            fileBrowserVM.isVisible.toggle()
        }
```

- [ ] **Step 5: 新增 accessor vars**

在文件末尾（`currentSidebarWidth`/`currentSidebarVisible` 之后）：

```swift
    var currentFileBrowserVisible: Bool { fileBrowserVM.isVisible }
    var currentFileBrowserWidth: CGFloat { fileBrowserVM.panelWidth }
```

- [ ] **Step 6: 编译检查**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep "PolterttyRootView.swift\|FileBrowserPanel.swift\|FileBrowserViewModel.swift" | grep "error:"
```

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/Features/Workspace/PolterttyRootView.swift \
        macos/Sources/Features/Workspace/FileBrowser/FileBrowserViewModel.swift \
        macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift
git commit -m "feat(file-browser): integrate FileBrowserPanel into PolterttyRootView with toggle notification"
```

---

## Chunk 6: TerminalController + AppDelegate 集成

### Task 10: TerminalController — injectToActiveSurface + saveSnapshot + 窗口生命周期

**Files:**
- Modify: `macos/Sources/Features/Terminal/TerminalController.swift`

- [ ] **Step 1: 实现 injectToActiveSurface**

在 `switchToWorkspace` 之后新增方法：

```swift
    /// 向当前 focused surface 注入文本（如 "cd /path/to/dir\n"）
    func injectToActiveSurface(_ text: String) {
        guard let surface = focusedSurface?.surface else { return }
        surface.sendText(text)
    }
```

- [ ] **Step 2: 监听 fileBrowserOpenInTerminal 通知**

在 `init` 的 `NotificationCenter` 注册链中添加：

```swift
        center.addObserver(
            self,
            selector: #selector(onFileBrowserOpenInTerminal(_:)),
            name: .fileBrowserOpenInTerminal,
            object: nil
        )
```

在 `TerminalController` 中新增 handler：

```swift
    @objc private func onFileBrowserOpenInTerminal(_ notification: Notification) {
        guard let wsId = notification.userInfo?["workspaceId"] as? UUID,
              wsId == workspaceId,
              let path = notification.userInfo?["path"] as? String else { return }
        let escapedPath = Ghostty.Shell.escape(path)
        injectToActiveSurface("cd \(escapedPath)\n")
    }
```

- [ ] **Step 3: 更新 saveSnapshot 调用以保存 file browser 状态**

在 `switchToWorkspace` 中，在调用 `WorkspaceManager.shared.saveSnapshot` 之前，更新 WorkspaceModel：

```swift
    func switchToWorkspace(_ targetId: UUID) {
        if let currentId = workspaceId, let window = self.window {
            // 先将 file browser 状态写回 WorkspaceModel
            persistFileBrowserState(for: currentId)

            WorkspaceManager.shared.saveSnapshot(
                for: currentId,
                window: window,
                sidebarWidth: CGFloat(PolterttyConfig.shared.sidebarWidth),
                sidebarVisible: PolterttyConfig.shared.sidebarVisible
            )
        }
        // ... 其余不变
    }

    private func persistFileBrowserState(for workspaceId: UUID) {
        guard var ws = WorkspaceManager.shared.workspace(for: workspaceId) else { return }
        let vm = WorkspaceManager.shared.fileBrowserViewModel(for: workspaceId)
        ws.fileBrowserVisible = vm.isVisible
        ws.fileBrowserWidth = vm.panelWidth
        WorkspaceManager.shared.update(ws)
    }
```

- [ ] **Step 4: 窗口 become/resign key 时暂停/恢复 FSEvents**

在 `windowDidBecomeKey` / `windowDidResignKey`（若存在则修改，否则新增）中：

```swift
    // 若 BaseTerminalController 有 windowDidBecomeKey，在 TerminalController override 中添加：
    override func windowDidBecomeKey(_ notification: Notification) {
        super.windowDidBecomeKey(notification)
        if let wsId = workspaceId {
            WorkspaceManager.shared.fileBrowserViewModel(for: wsId).resume()
        }
    }

    override func windowDidResignKey(_ notification: Notification) {
        super.windowDidResignKey(notification)
        if let wsId = workspaceId {
            WorkspaceManager.shared.fileBrowserViewModel(for: wsId).pause()
        }
    }
```

**注意**：若 `BaseTerminalController` 没有这两个 override，在 TerminalController 中新增 `NSWindowDelegate` 方法。检查 `BaseTerminalController.swift` 中是否已有这些方法。

- [ ] **Step 5: 编译检查（整个项目）**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep "\.swift:" | grep "error:"
```

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Terminal/TerminalController.swift
git commit -m "feat(file-browser): add injectToActiveSurface, file browser state persistence, window lifecycle"
```

---

### Task 11: AppDelegate — Cmd+\ 菜单项

**Files:**
- Modify: `macos/Sources/App/macOS/AppDelegate.swift`

- [ ] **Step 1: 在 setupWorkspaceMenu 中新增菜单项**

在 `toggleSidebar` 那行之后添加：

```swift
        let toggleFileBrowser = NSMenuItem(
            title: "Toggle File Browser",
            action: #selector(toggleFileBrowser(_:)),
            keyEquivalent: "\\"
        )
        toggleFileBrowser.keyEquivalentModifierMask = .command
        workspaceMenu.addItem(toggleFileBrowser)
```

- [ ] **Step 2: 实现 action 方法**

在 `toggleWorkspaceSidebar` 之后新增：

```swift
    @objc func toggleFileBrowser(_ sender: Any?) {
        guard let window = NSApp.keyWindow,
              let wsId = WorkspaceManager.shared.workspaceId(for: window) else { return }
        NotificationCenter.default.post(
            name: .toggleFileBrowser,
            object: nil,
            userInfo: ["workspaceId": wsId]
        )
    }
```

- [ ] **Step 3: 编译检查**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep "AppDelegate.swift" | grep "error:"
```

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/App/macOS/AppDelegate.swift
git commit -m "feat(file-browser): add Cmd+\\ menu item to toggle file browser panel"
```

---

## Chunk 7: 全量编译验证 + 功能测试

### Task 12: 完整编译并手动测试

- [ ] **Step 1: 完整编译**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep "\.swift:" | grep "error:"
```

Expected: 0 errors

- [ ] **Step 2: 修复编译错误**

如有编译错误，按错误信息逐一修复。常见问题：
- Swift 6 concurrency: `@MainActor` 方法从 non-isolated 上下文调用 → 用 `Task { @MainActor in ... }`
- `Sendable` 警告 → 视情况加 `@unchecked Sendable` 或重构
- `windowDidBecomeKey` 找不到 super → 检查 `BaseTerminalController` 是否实现，若无则直接实现 NSWindowDelegate

- [ ] **Step 3: 运行 App，手动验证以下场景**

1. **面板切换**：Cmd+\ 打开/关闭文件浏览器面板
2. **目录树**：Workspace 的 rootDir 目录树显示正确，展开/折叠正常
3. **隐藏文件**：按 `.` 键切换隐藏文件显示（面板 focused 时）
4. **Filter**：顶部搜索栏过滤节点名称
5. **Cmd+F 递归**：Cmd+F 展开所有目录并搜索；清空 filter 折叠回原状
6. **Git 标注**：有 git 仓库的目录显示 M/A/D/? 颜色标注
7. **Open in Terminal**：按 T / 右键 "Open in Terminal" 注入 `cd path\n` 到 terminal
8. **双击文件**：用默认 App 打开
9. **重命名**：按 R 触发 inline 编辑，Enter 确认
10. **删除**：Cmd+Delete 移到废纸篓
11. **宽度持久化**：拖拽调整面板宽度 → 切换 Workspace → 回来宽度保持
12. **可见性持久化**：关闭面板 → 重启 App → 面板状态恢复
13. **rootDir 为空**：显示空状态提示，无错误
14. **FSEvents**：在 Finder 中新建/删除文件，面板自动刷新（300ms debounce）

- [ ] **Step 4: Final Commit**

```bash
git add -p  # 检查是否有遗漏的改动
git commit -m "feat(file-browser): complete file browser panel implementation

- File browser panel between workspace sidebar and terminal
- FSEvents real-time monitoring with 300ms debounce
- Git status annotations (M/A/D/?) with color coding
- Filter bar with normal and recursive (Cmd+F) modes
- File operations: open in terminal, copy path, new file/dir, rename, delete
- Per-workspace state persistence (visible, width)
- Cmd+\\ shortcut to toggle panel"
```

---

## 实现注意事项

### Swift 6 Concurrency
- `FileBrowserViewModel` 的 `@Published` 属性更新必须在主线程。用 `DispatchQueue.main.async` 或 `await MainActor.run { }` 包装。
- `WorkspaceManager.fileBrowserViewModel(for:)` 从 SwiftUI init 调用（已在主线程）——无并发问题。
- `FileSystemMonitor` 的 `onChange` 通过 `DispatchQueue.main.async` 回到主线程。

### init 中访问 WorkspaceManager
`PolterttyRootView.init` 调用 `WorkspaceManager.shared.fileBrowserViewModel(for:)` 是安全的：SwiftUI View 的 init 在主线程调用。

### windowDidBecomeKey / windowDidResignKey
先查 `BaseTerminalController.swift` 是否实现了这两个方法。若有，在 TerminalController 的 override 里调用 super 并添加 resume/pause 逻辑。若无，直接在 TerminalController 新增实现（同时确认 TerminalController 遵守 NSWindowDelegate）。

### DragGesture 与 @State 冲突
`panelDivider` 中的 `DragGesture` 修改 `fileBrowserVM.panelWidth`（ObservableObject），会触发 PolterttyRootView 重绘。使用 `@GestureState` + `.updating` 可更流畅，但简单 `.onChanged` 也可行，性能上可接受。

### WorkspaceSnapshot 兼容性
`fileBrowserVisible` 和 `fileBrowserWidth` 用 `decodeIfPresent` 加默认值，旧 snapshot JSON（无这两个字段）反序列化时使用默认值，完全向后兼容。
