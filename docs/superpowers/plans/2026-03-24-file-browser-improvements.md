# 文件浏览器增强 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为文件浏览器添加快捷键面板、路径面包屑、智能过滤 Chip 栏、Git Diff 预览和 Stage/Unstage 操作。

**Architecture:** 三组独立功能，按组分支开发。每组只新增聚焦文件，尽量避免大范围改动现有文件。ViewModel 扩展遵循现有 `@Published` + `ObservableObject` 模式。

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit, FSEventStream, `git` CLI（通过 Process 调用）

**规范参考：** 开发前必须阅读 `docs/development-rules.md` 和 `docs/build-rules.md`

---

## 文件结构

### 第一组：快捷键面板 + 路径面包屑

| 操作 | 文件 |
|------|------|
| 新建 | `macos/Sources/Features/Workspace/FileBrowser/ShortcutHelpView.swift` |
| 新建 | `macos/Sources/Features/Workspace/FileBrowser/BreadcrumbView.swift` |
| 修改 | `macos/Sources/Features/Workspace/FileBrowser/FileBrowserViewModel.swift` |
| 修改 | `macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift` |

### 第二组：智能过滤 Chip 栏

| 操作 | 文件 |
|------|------|
| 新建 | `macos/Sources/Features/Workspace/FileBrowser/FilterChipsView.swift` |
| 修改 | `macos/Sources/Features/Workspace/FileBrowser/FileBrowserViewModel.swift` |
| 修改 | `macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift` |

### 第三组：Git 深度集成

| 操作 | 文件 |
|------|------|
| 新建 | `macos/Sources/Features/Workspace/FileBrowser/DiffView.swift` |
| 修改 | `macos/Sources/Features/Workspace/FileBrowser/GitStatusService.swift` |
| 修改 | `macos/Sources/Features/Workspace/FileBrowser/FilePreviewView.swift` |
| 修改 | `macos/Sources/Features/Workspace/FileBrowser/FileNodeRow.swift` |
| 修改 | `macos/Sources/Features/Workspace/FileBrowser/FileBrowserViewModel.swift` |

---

## 第一组：快捷键面板 + 路径面包屑

### Task 1: ViewModel 扩展——快捷键面板 + 面包屑状态

**Files:**
- Modify: `macos/Sources/Features/Workspace/FileBrowser/FileBrowserViewModel.swift`

- [ ] **Step 1: 在 Published State 区域添加快捷键面板状态**

在 `// Preview state` 块后追加：

```swift
// Shortcut help
@Published var showShortcutHelp: Bool = false

// Breadcrumb
@Published var focusedRootURL: URL? = nil
```

- [ ] **Step 2: 添加 breadcrumbSegments 计算属性**

在 `// MARK: - Keyboard Navigation` 之前添加：

```swift
// MARK: - Breadcrumb

struct BreadcrumbSegment: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
}

/// 从 workspace 根目录到当前选中文件的父目录路径段
var breadcrumbSegments: [BreadcrumbSegment] {
    guard let selectedId = lastSelectedId,
          let selectedURL = findNodeURL(id: selectedId) else { return [] }
    let root = URL(fileURLWithPath: rootDir)
    let targetDir = selectedURL.hasDirectoryPath ? selectedURL : selectedURL.deletingLastPathComponent()

    var segments: [BreadcrumbSegment] = []
    var current = targetDir
    while current.path.hasPrefix(root.path) {
        segments.insert(
            BreadcrumbSegment(name: current.lastPathComponent, url: current),
            at: 0
        )
        if current.path == root.path { break }
        current = current.deletingLastPathComponent()
    }
    return segments
}

func focusDirectory(_ url: URL) {
    let rootURL = URL(fileURLWithPath: rootDir)
    focusedRootURL = (url == rootURL) ? nil : url
}
```

- [ ] **Step 3: 修改 visibleNodes，当 focusedRootURL 非 nil 时只显示子树**

找到 `var visibleNodes` 计算属性，将：

```swift
var visibleNodes: [(node: FileNode, depth: Int)] {
    var result: [(FileNode, Int)] = []
    let source = filterText.isEmpty ? rootNodes : filteredNodes
    collectVisible(from: source, depth: 0, into: &result)
    return result
}
```

改为：

```swift
var visibleNodes: [(node: FileNode, depth: Int)] {
    var result: [(FileNode, Int)] = []
    let baseNodes: [FileNode]
    if let focusURL = focusedRootURL,
       let focusNode = findNodeByURL(url: focusURL, in: rootNodes),
       let children = focusNode.children {
        baseNodes = children
    } else {
        baseNodes = rootNodes
    }
    let source = filterText.isEmpty ? baseNodes : filterTree(nodes: baseNodes, query: filterText.lowercased())
    collectVisible(from: source, depth: 0, into: &result)
    return result
}
```

- [ ] **Step 4: 构建并验证编译无报错**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty
xcodebuild -project macos/Poltertty.xcodeproj -scheme Poltertty -destination 'platform=macOS' build 2>&1 | tail -20
```

期望：`BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/FileBrowserViewModel.swift
git commit -m "feat(file-browser): 添加快捷键面板和面包屑的 ViewModel 状态"
```

---

### Task 2: ShortcutHelpView——快捷键帮助浮层

**Files:**
- Create: `macos/Sources/Features/Workspace/FileBrowser/ShortcutHelpView.swift`

- [ ] **Step 1: 创建 ShortcutHelpView.swift**

```swift
// macos/Sources/Features/Workspace/FileBrowser/ShortcutHelpView.swift
import SwiftUI

struct ShortcutHelpView: View {
    var onDismiss: () -> Void

    private struct ShortcutItem: Identifiable {
        let id = UUID()
        let keys: String
        let description: String
    }

    private struct ShortcutSection: Identifiable {
        let id = UUID()
        let title: String
        let items: [ShortcutItem]
    }

    private let sections: [ShortcutSection] = [
        ShortcutSection(title: "导航", items: [
            ShortcutItem(keys: "↑ / ↓", description: "上下选择"),
            ShortcutItem(keys: "Return", description: "展开/折叠目录"),
        ]),
        ShortcutSection(title: "文件操作", items: [
            ShortcutItem(keys: "n", description: "新建文件"),
            ShortcutItem(keys: "N", description: "新建目录"),
            ShortcutItem(keys: "r", description: "重命名"),
            ShortcutItem(keys: "⌘⌫", description: "删除"),
            ShortcutItem(keys: "t", description: "在终端打开"),
        ]),
        ShortcutSection(title: "搜索与视图", items: [
            ShortcutItem(keys: "⌘F", description: "过滤文件"),
            ShortcutItem(keys: ".", description: "切换隐藏文件"),
            ShortcutItem(keys: "Space", description: "切换预览面板"),
            ShortcutItem(keys: "⌘⇧C", description: "复制路径"),
            ShortcutItem(keys: "⌘A", description: "全选"),
        ]),
        ShortcutSection(title: "帮助", items: [
            ShortcutItem(keys: "?", description: "显示/隐藏此面板"),
        ]),
    ]

    var body: some View {
        ZStack {
            // 点击背景关闭
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            // 面板
            VStack(alignment: .leading, spacing: 0) {
                // 标题栏
                HStack {
                    Text("快捷键")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                Divider()

                // 快捷键列表
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(section.title)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 16)

                                ForEach(section.items) { item in
                                    HStack(spacing: 0) {
                                        Text(item.keys)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.primary)
                                            .frame(width: 80, alignment: .leading)
                                        Text(item.description)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }

            }
            .frame(width: 280)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 8)
        }
    }
}
```

- [ ] **Step 2: 构建验证**

```bash
xcodebuild -project macos/Poltertty.xcodeproj -scheme Poltertty -destination 'platform=macOS' build 2>&1 | tail -10
```

期望：`BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/ShortcutHelpView.swift
git commit -m "feat(file-browser): 新增快捷键帮助浮层 ShortcutHelpView"
```

---

### Task 3: BreadcrumbView——路径面包屑

**Files:**
- Create: `macos/Sources/Features/Workspace/FileBrowser/BreadcrumbView.swift`

- [ ] **Step 1: 创建 BreadcrumbView.swift**

```swift
// macos/Sources/Features/Workspace/FileBrowser/BreadcrumbView.swift
import SwiftUI

struct BreadcrumbView: View {
    let segments: [FileBrowserViewModel.BreadcrumbSegment]
    let onTap: (FileBrowserViewModel.BreadcrumbSegment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    Button(action: { onTap(segment) }) {
                        Text(segment.name)
                            .font(.system(size: 10))
                            .foregroundColor(index == segments.count - 1 ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(height: 22)
    }
}
```

- [ ] **Step 2: 在 FileBrowserPanel 中集成 BreadcrumbView 和 ShortcutHelpView**

打开 `FileBrowserPanel.swift`。

**2a. 在 `body` 修饰链中添加 `?` 键绑定**（在 `handleAKey` 那行之后）：

```swift
.backport.onKeyPress("?") { handleQuestionKey(modifiers: $0) }
```

**2b. 添加 `handleQuestionKey` 方法**（在 `// MARK: - Key Handlers` 区域）：

```swift
private func handleQuestionKey(modifiers: EventModifiers) -> BackportKeyPressResult {
    guard isFocused else { return .ignored }
    viewModel.showShortcutHelp.toggle()
    return .handled
}
```

**2c. 在 `panelContent` 的 VStack 中，`filterBar` 之前插入 BreadcrumbView**（当 segments 非空时显示）：

找到：
```swift
private var panelContent: some View {
    HStack(spacing: 0) {
        // Left: File tree (always visible)
        VStack(spacing: 0) {
            filterBar
            Divider()
```

改为：
```swift
private var panelContent: some View {
    HStack(spacing: 0) {
        // Left: File tree (always visible)
        VStack(spacing: 0) {
            if !viewModel.breadcrumbSegments.isEmpty {
                BreadcrumbView(segments: viewModel.breadcrumbSegments) { segment in
                    viewModel.focusDirectory(segment.url)
                }
                Divider()
            }
            filterBar
            Divider()
```

**2d. 将 ShortcutHelpView 作为 overlay 叠加在整个 body 上**。

在 `body` 的最外层 `.background(...)` 修饰之后添加：

```swift
.overlay {
    if viewModel.showShortcutHelp {
        ShortcutHelpView(onDismiss: { viewModel.showShortcutHelp = false })
            .transition(.opacity)
    }
}
```

- [ ] **Step 3: 构建验证**

```bash
xcodebuild -project macos/Poltertty.xcodeproj -scheme Poltertty -destination 'platform=macOS' build 2>&1 | tail -10
```

期望：`BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/BreadcrumbView.swift
git add macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift
git commit -m "feat(file-browser): 集成面包屑导航和快捷键帮助面板"
```

---

## 第二组：智能过滤 Chip 栏

### Task 4: ViewModel 扩展——多维过滤

**Files:**
- Modify: `macos/Sources/Features/Workspace/FileBrowser/FileBrowserViewModel.swift`

- [ ] **Step 1: 在 Published State 区域添加过滤状态**

在 `@Published var filterText` 行之后添加：

```swift
@Published var activeExtensions: Set<String> = []
@Published var activeGitStatuses: Set<GitStatus> = []
```

- [ ] **Step 2: 添加 availableExtensions 计算属性**

在 `// MARK: - Breadcrumb` 区域之前添加：

```swift
// MARK: - Smart Filter

/// 遍历整个树，统计各扩展名的文件数量（目录不计）
var availableExtensions: [(ext: String, count: Int)] {
    var counts: [String: Int] = [:]
    collectExtensions(from: rootNodes, into: &counts)
    return counts
        .map { (ext: $0.key, count: $0.value) }
        .sorted { $0.ext < $1.ext }
}

private func collectExtensions(from nodes: [FileNode], into counts: inout [String: Int]) {
    for node in nodes {
        if !node.isDirectory {
            let ext = node.url.pathExtension.lowercased()
            if !ext.isEmpty {
                counts[ext, default: 0] += 1
            }
        }
        if let children = node.children {
            collectExtensions(from: children, into: &counts)
        }
    }
}

func toggleExtensionFilter(_ ext: String) {
    if activeExtensions.contains(ext) {
        activeExtensions.remove(ext)
    } else {
        activeExtensions.insert(ext)
    }
}

func toggleGitStatusFilter(_ status: GitStatus) {
    if activeGitStatuses.contains(status) {
        activeGitStatuses.remove(status)
    } else {
        activeGitStatuses.insert(status)
    }
}

func clearAllFilters() {
    activeExtensions = []
    activeGitStatuses = []
    filterText = ""
}

var hasActiveFilters: Bool {
    !activeExtensions.isEmpty || !activeGitStatuses.isEmpty || !filterText.isEmpty
}
```

- [ ] **Step 3: 扩展 filterTree，叠加扩展名和 git 状态过滤**

找到 `private var filteredNodes` 计算属性：

```swift
private var filteredNodes: [FileNode] {
    let query = filterText.lowercased()
    return filterTree(nodes: rootNodes, query: query)
}
```

改为：

```swift
private var filteredNodes: [FileNode] {
    let query = filterText.lowercased()
    let baseNodes: [FileNode]
    if let focusURL = focusedRootURL,
       let focusNode = findNodeByURL(url: focusURL, in: rootNodes),
       let children = focusNode.children {
        baseNodes = children
    } else {
        baseNodes = rootNodes
    }
    return filterTree(nodes: baseNodes, query: query)
}
```

找到 `private func filterTree(nodes:query:)` 方法，将其替换为支持多维过滤的版本：

```swift
private func filterTree(nodes: [FileNode], query: String) -> [FileNode] {
    var result: [FileNode] = []
    for node in nodes {
        if node.isDirectory {
            let filteredChildren: [FileNode]
            if let children = node.children {
                filteredChildren = filterTree(nodes: children, query: query)
            } else {
                filteredChildren = []
            }
            if !filteredChildren.isEmpty {
                var copy = node
                copy.children = filteredChildren
                copy.isExpanded = true
                result.append(copy)
            }
        } else {
            // 文本过滤
            if !query.isEmpty && !node.name.lowercased().contains(query) { continue }
            // 扩展名过滤
            if !activeExtensions.isEmpty {
                let ext = node.url.pathExtension.lowercased()
                if !activeExtensions.contains(ext) { continue }
            }
            // Git 状态过滤
            if !activeGitStatuses.isEmpty {
                let status = gitStatus(for: node.url)
                guard let status, activeGitStatuses.contains(status) else { continue }
            }
            result.append(node)
        }
    }
    return result
}
```

- [ ] **Step 4: 修改 visibleNodes，在无过滤条件时也应用 focusedRootURL**

（已在 Task 1 Step 3 完成，验证逻辑正确即可）

- [ ] **Step 5: 构建验证**

```bash
xcodebuild -project macos/Poltertty.xcodeproj -scheme Poltertty -destination 'platform=macOS' build 2>&1 | tail -10
```

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/FileBrowserViewModel.swift
git commit -m "feat(file-browser): ViewModel 支持多维过滤（扩展名+git状态）"
```

---

### Task 5: FilterChipsView——过滤 Chip 栏 UI

**Files:**
- Create: `macos/Sources/Features/Workspace/FileBrowser/FilterChipsView.swift`
- Modify: `macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift`

- [ ] **Step 1: 创建 FilterChipsView.swift**

```swift
// macos/Sources/Features/Workspace/FileBrowser/FilterChipsView.swift
import SwiftUI

struct FilterChipsView: View {
    @ObservedObject var viewModel: FileBrowserViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // 扩展名 Chips
                ForEach(viewModel.availableExtensions, id: \.ext) { item in
                    FilterChip(
                        label: ".\(item.ext)",
                        count: item.count,
                        isActive: viewModel.activeExtensions.contains(item.ext),
                        color: .accentColor
                    ) {
                        viewModel.toggleExtensionFilter(item.ext)
                    }
                }

                if !viewModel.availableExtensions.isEmpty && !gitStatusItems.isEmpty {
                    Divider().frame(height: 16)
                }

                // Git 状态 Chips
                ForEach(gitStatusItems, id: \.status.rawValue) { item in
                    FilterChip(
                        label: item.label,
                        count: nil,
                        isActive: viewModel.activeGitStatuses.contains(item.status),
                        color: Color(hex: item.status.colorHex) ?? .secondary
                    ) {
                        viewModel.toggleGitStatusFilter(item.status)
                    }
                }

                // 清除全部按钮
                if viewModel.hasActiveFilters {
                    Button(action: { viewModel.clearAllFilters() }) {
                        Text("清除")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .frame(height: 28)
    }

    private struct GitStatusItem {
        let status: GitStatus
        let label: String
    }

    private var gitStatusItems: [GitStatusItem] {
        guard !viewModel.gitStatuses.isEmpty else { return [] }
        return [
            GitStatusItem(status: .modified, label: "已修改"),
            GitStatusItem(status: .untracked, label: "未追踪"),
            GitStatusItem(status: .added, label: "已添加"),
            GitStatusItem(status: .deleted, label: "已删除"),
        ]
    }
}

private struct FilterChip: View {
    let label: String
    let count: Int?
    let isActive: Bool
    let color: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 10))
                if let count {
                    Text("×\(count)")
                        .font(.system(size: 9))
                        .opacity(0.7)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(isActive ? color.opacity(0.2) : Color.primary.opacity(0.07))
            .foregroundColor(isActive ? color : .secondary)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isActive ? color.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: 在 FileBrowserPanel 的 filterBar 之后插入 FilterChipsView**

找到 `filterBar` 私有变量，在其 VStack 末尾（`// 多选计数` 块之后）**不**修改，而是在 `panelContent` 的 VStack 中，`filterBar` 之后、第一个 `Divider()` 之前插入：

在 `panelContent` 中找到：
```swift
            filterBar
            Divider()
            if viewModel.rootDir.isEmpty
```

改为：
```swift
            filterBar
            if !viewModel.availableExtensions.isEmpty || !viewModel.gitStatuses.isEmpty {
                FilterChipsView(viewModel: viewModel)
                Divider()
            }
            Divider()
            if viewModel.rootDir.isEmpty
```

- [ ] **Step 3: 构建验证**

```bash
xcodebuild -project macos/Poltertty.xcodeproj -scheme Poltertty -destination 'platform=macOS' build 2>&1 | tail -10
```

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/FilterChipsView.swift
git add macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift
git commit -m "feat(file-browser): 添加过滤 Chip 栏（扩展名+git状态）"
```

---

## 第三组：Git 深度集成

### Task 6: GitStatusService 扩展——diff、stage、unstage

**Files:**
- Modify: `macos/Sources/Features/Workspace/FileBrowser/GitStatusService.swift`

- [ ] **Step 1: 在 GitStatusService 中添加 fetchDiff、stage、unstage 方法**

在 `fetchStatus` 方法之后追加：

```swift
/// 获取文件的 git diff 内容
/// - Parameters:
///   - staged: true 时使用 `git diff --cached`（已暂存），false 时使用 `git diff HEAD`
static func fetchDiff(rootDir: String, fileURL: URL, staged: Bool) async -> String {
    guard !rootDir.isEmpty else { return "" }
    return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            if staged {
                process.arguments = ["-C", rootDir, "diff", "--cached", "--", fileURL.path]
            } else {
                process.arguments = ["-C", rootDir, "diff", "HEAD", "--", fileURL.path]
            }
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                continuation.resume(returning: "")
                return
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            continuation.resume(returning: output)
        }
    }
}

/// 暂存文件（git add）
static func stage(rootDir: String, urls: [URL]) async throws {
    try await runGitCommand(rootDir: rootDir, args: ["add", "--"] + urls.map(\.path))
}

/// 取消暂存（git restore --staged）
static func unstage(rootDir: String, urls: [URL]) async throws {
    try await runGitCommand(rootDir: rootDir, args: ["restore", "--staged", "--"] + urls.map(\.path))
}

private static func runGitCommand(rootDir: String, args: [String]) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", rootDir] + args
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(domain: "GitStatusService", code: Int(process.terminationStatus)))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
```

- [ ] **Step 2: 构建验证**

```bash
xcodebuild -project macos/Poltertty.xcodeproj -scheme Poltertty -destination 'platform=macOS' build 2>&1 | tail -10
```

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/GitStatusService.swift
git commit -m "feat(file-browser): GitStatusService 添加 diff/stage/unstage 方法"
```

---

### Task 7: DiffView——Git Diff 渲染视图

**Files:**
- Create: `macos/Sources/Features/Workspace/FileBrowser/DiffView.swift`

- [ ] **Step 1: 创建 DiffView.swift**

```swift
// macos/Sources/Features/Workspace/FileBrowser/DiffView.swift
import SwiftUI

struct DiffView: View {
    let rootDir: String
    let fileURL: URL
    let isStaged: Bool

    @State private var diffContent: String = ""
    @State private var isLoading: Bool = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if diffContent.isEmpty {
                Text("无变更内容")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(parsedLines.enumerated()), id: \.offset) { _, line in
                            diffLineView(line)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .task(id: "\(fileURL.path)-\(isStaged)") {
            isLoading = true
            diffContent = await GitStatusService.fetchDiff(
                rootDir: rootDir,
                fileURL: fileURL,
                staged: isStaged
            )
            isLoading = false
        }
    }

    private struct DiffLine {
        enum Kind { case added, removed, context, header, hunk }
        let kind: Kind
        let text: String
        let lineNum: String
    }

    private var parsedLines: [DiffLine] {
        var result: [DiffLine] = []
        var oldNum = 0
        var newNum = 0
        var hunkOld = 0
        var hunkNew = 0

        for line in diffContent.components(separatedBy: "\n") {
            if line.hasPrefix("@@") {
                // 解析 @@ -a,b +c,d @@ 格式
                if let match = line.range(of: #"\-(\d+).*\+(\d+)"#, options: .regularExpression) {
                    let nums = line[match].components(separatedBy: CharacterSet(charactersIn: "-+,")).compactMap { Int($0) }
                    if nums.count >= 2 {
                        hunkOld = nums[0]; hunkNew = nums[1]
                        oldNum = hunkOld; newNum = hunkNew
                    }
                }
                result.append(DiffLine(kind: .hunk, text: line, lineNum: ""))
            } else if line.hasPrefix("diff ") || line.hasPrefix("index ") || line.hasPrefix("--- ") || line.hasPrefix("+++ ") {
                result.append(DiffLine(kind: .header, text: line, lineNum: ""))
            } else if line.hasPrefix("+") {
                result.append(DiffLine(kind: .added, text: String(line.dropFirst()), lineNum: "\(newNum)"))
                newNum += 1
            } else if line.hasPrefix("-") {
                result.append(DiffLine(kind: .removed, text: String(line.dropFirst()), lineNum: "\(oldNum)"))
                oldNum += 1
            } else {
                result.append(DiffLine(kind: .context, text: String(line.dropFirst()), lineNum: "\(newNum)"))
                oldNum += 1; newNum += 1
            }
        }
        return result
    }

    @ViewBuilder
    private func diffLineView(_ line: DiffLine) -> some View {
        HStack(spacing: 0) {
            // 行号
            Text(line.lineNum)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 8)

            // 前缀符号
            Text(linePrefix(line.kind))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(lineForeground(line.kind))
                .frame(width: 12)

            // 内容
            Text(line.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(lineForeground(line.kind))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(lineBackground(line.kind))
    }

    private func linePrefix(_ kind: DiffLine.Kind) -> String {
        switch kind {
        case .added: return "+"
        case .removed: return "-"
        case .hunk: return "@@"
        default: return " "
        }
    }

    private func lineForeground(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: return Color(hex: "#4ade80") ?? .green
        case .removed: return Color(hex: "#f87171") ?? .red
        case .hunk: return Color(hex: "#60a5fa") ?? .blue
        case .header: return .secondary
        case .context: return .primary.opacity(0.8)
        }
    }

    private func lineBackground(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: return Color(hex: "#4ade80")?.opacity(0.08) ?? .clear
        case .removed: return Color(hex: "#f87171")?.opacity(0.08) ?? .clear
        default: return .clear
        }
    }
}
```

- [ ] **Step 2: 构建验证**

```bash
xcodebuild -project macos/Poltertty.xcodeproj -scheme Poltertty -destination 'platform=macOS' build 2>&1 | tail -10
```

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/DiffView.swift
git commit -m "feat(file-browser): 新增 DiffView 渲染 git diff 内容"
```

---

### Task 8: FilePreviewView 集成 Diff 切换

**Files:**
- Modify: `macos/Sources/Features/Workspace/FileBrowser/FilePreviewView.swift`

- [ ] **Step 1: 读取 FilePreviewView.swift 了解现有结构**

先读取文件确认接口：`macos/Sources/Features/Workspace/FileBrowser/FilePreviewView.swift`

- [ ] **Step 2: 为 FilePreviewView 添加 diff 相关属性和切换按钮**

FilePreviewView 接受 `url: URL` 参数。需要额外传入 `rootDir: String` 和 `gitStatus: GitStatus?`。

在 `FilePreviewView` 结构体属性中添加：
```swift
let rootDir: String
let gitStatus: GitStatus?
@State private var showDiff: Bool = false
```

在标题栏（onToggleFullscreen 按钮旁）添加 Diff 切换按钮，仅在 gitStatus 为 `.modified` 或 `.added` 时显示：

```swift
if gitStatus == .modified || gitStatus == .added {
    Button(action: { showDiff.toggle() }) {
        Text("Diff")
            .font(.system(size: 10, weight: showDiff ? .semibold : .regular))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(showDiff ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(4)
    }
    .buttonStyle(.plain)
    .foregroundColor(showDiff ? .accentColor : .secondary)
}
```

在内容区根据 `showDiff` 切换显示 `DiffView` 或原有内容视图：

```swift
if showDiff {
    DiffView(rootDir: rootDir, fileURL: url, isStaged: gitStatus == .added)
} else {
    // 原有内容视图
}
```

- [ ] **Step 3: 更新 FileBrowserPanel 传入 rootDir 和 gitStatus**

在 `panelContent` 中找到 `FilePreviewView(url: url, ...)` 调用，补充参数：

```swift
FilePreviewView(
    url: url,
    rootDir: viewModel.rootDir,
    gitStatus: viewModel.gitStatus(for: url),
    isFullscreen: viewModel.isPreviewFullscreen,
    onToggleFullscreen: { ... },
    onClose: { ... }
)
```

- [ ] **Step 4: 构建验证**

```bash
xcodebuild -project macos/Poltertty.xcodeproj -scheme Poltertty -destination 'platform=macOS' build 2>&1 | tail -10
```

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/FilePreviewView.swift
git add macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift
git commit -m "feat(file-browser): FilePreviewView 集成 Diff 切换视图"
```

---

### Task 9: Stage/Unstage——ViewModel + 右键菜单

**Files:**
- Modify: `macos/Sources/Features/Workspace/FileBrowser/FileBrowserViewModel.swift`
- Modify: `macos/Sources/Features/Workspace/FileBrowser/FileNodeRow.swift`
- Modify: `macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift`

- [ ] **Step 1: ViewModel 添加 stage/unstage 方法**

在 `// MARK: - Git Status` 区域末尾添加：

```swift
func stageFiles(_ urls: [URL]) {
    Task {
        try? await GitStatusService.stage(rootDir: rootDir, urls: urls)
        await refreshGitStatus()
    }
}

func unstageFiles(_ urls: [URL]) {
    Task {
        try? await GitStatusService.unstage(rootDir: rootDir, urls: urls)
        await refreshGitStatus()
    }
}
```

- [ ] **Step 2: FileNodeRow 添加 stage/unstage 回调和菜单项**

在 `FileNodeRow` 结构体中添加属性：

```swift
let onStage: (() -> Void)?
let onUnstage: (() -> Void)?
```

在 `.contextMenu` 的单选菜单中，在 `Open in Terminal` 之后，根据 gitStatus 动态添加菜单项：

```swift
// Git 操作（仅非目录文件）
if !node.isDirectory {
    Divider()
    if gitStatus == .modified || gitStatus == .untracked {
        Button("Stage") { onStage?() }
    } else if gitStatus == .added {
        Button("Unstage") { onUnstage?() }
    } else if gitStatus == .deleted {
        Button("Stage Deletion") { onStage?() }
        Button("Unstage") { onUnstage?() }
    }
}
```

在多选菜单中，在现有菜单项之后添加：

```swift
Divider()
Button("Stage \(selectedCount) 个项目") { onStage?() }
Button("Unstage \(selectedCount) 个项目") { onUnstage?() }
```

- [ ] **Step 3: FileBrowserPanel 传入 onStage/onUnstage 回调**

在 `nodeRowView(for:)` 方法的 `FileNodeRow(...)` 调用中补充：

```swift
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
```

- [ ] **Step 4: 构建验证**

```bash
xcodebuild -project macos/Poltertty.xcodeproj -scheme Poltertty -destination 'platform=macOS' build 2>&1 | tail -10
```

期望：`BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/FileBrowserViewModel.swift
git add macos/Sources/Features/Workspace/FileBrowser/FileNodeRow.swift
git add macos/Sources/Features/Workspace/FileBrowser/FileBrowserPanel.swift
git commit -m "feat(file-browser): 右键菜单添加 Stage/Unstage 操作"
```

---

## 完成检查

- [ ] 所有 9 个 Task 完成
- [ ] 所有构建均 `BUILD SUCCEEDED`
- [ ] 三组功能均有各自的 commit 记录
- [ ] 无编译警告新增（检查 `xcodebuild ... build 2>&1 | grep warning:`）
