# 文件浏览器 UX 优化设计文档

**日期：** 2026-03-31
**状态：** 已批准
**范围：** `macos/Sources/Features/Workspace/FileBrowser/`

---

## 背景

现有文件浏览器存在三类体验问题：

1. **点击展开/折叠抖动**：单击目录行时，展开后立即折叠
2. **鼠标 hover 无防抖**：鼠标扫过列表触发大量重绘
3. **滚动掉帧**：图标同步加载阻塞主线程，`visibleNodes` 无缓存每帧重算

---

## 一、点击行为修复

### 问题根因

`FileNodeRow` 的行手势与箭头手势同时触发：

- 箭头：`.onTapGesture { onToggleExpand() }`
- 行：`.simultaneousGesture(TapGesture(count: 1).onEnded { onSingleClick() })`

`simultaneousGesture` 不拦截子 view 事件，单击箭头时两者都触发，对目录执行两次 `toggleExpand` → 展开后立即折叠。

### 修复方案

**`FileBrowserPanel.swift` — `onSingleClick` 回调**

单击行只做选中，移除目录的 `toggleExpand` 调用：

```swift
onSingleClick: {
    let flags = NSEvent.modifierFlags
    if flags.contains(.command) {
        viewModel.toggleSelection(id: entry.node.id)
    } else if flags.contains(.shift) {
        viewModel.extendSelection(to: entry.node.id)
    } else {
        viewModel.selectNode(id: entry.node.id)
        // 移除：if entry.node.isDirectory { viewModel.toggleExpand(nodeId: entry.node.id) }
    }
    DispatchQueue.main.async { isFocused = true }
},
```

**`FileBrowserPanel.swift` — `onDoubleClick` 回调**

双击目录执行展开/折叠（原来对目录无操作）：

```swift
onDoubleClick: {
    if entry.node.isDirectory {
        viewModel.toggleExpand(nodeId: entry.node.id)
    } else {
        viewModel.openInDefaultApp(entry.node.url)
    }
},
```

**展开入口汇总（修改后）：**

| 操作 | 行为 |
|------|------|
| 点击箭头 | 展开/折叠 |
| 双击目录行 | 展开/折叠 |
| 键盘 `Return` | 展开/折叠（已有） |
| 单击目录行 | 仅选中 |

此行为与 VSCode / Xcode Sidebar 一致。

---

## 二、hover 防抖

### 问题根因

`FileNodeRow` 的 `.onHover` 直接赋值，鼠标扫过 N 行触发 N 次 SwiftUI 重绘：

```swift
.onHover { hovering in
    isHovering = hovering  // 无防抖
}
```

### 修复方案

**`FileNodeRow.swift`**

新增 `@State private var hoverTask: Task<Void, Never>?`，enter 时延迟 50ms 再生效，leave 时立即清除：

```swift
@State private var hoverTask: Task<Void, Never>? = nil

// .onHover 替换为：
.onHover { hovering in
    hoverTask?.cancel()
    if hovering {
        hoverTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            guard !Task.isCancelled else { return }
            await MainActor.run { isHovering = true }
        }
    } else {
        isHovering = false
    }
}
```

效果：快速扫过的行不触发高亮重绘，停留 50ms 以上才显示 hover 背景。

---

## 三、图标缓存 + visibleNodes 缓存

### 3.1 图标异步缓存

**问题：** `FileIconView.updateNSView` 每次刷新同步调用 `NSWorkspace.shared.icon(forFile:)`，主线程阻塞，一屏 30 行 = 每帧最多 30 次同步 I/O。

**修复：** `FileIconView` 引入静态 `NSCache`，命中缓存直接展示，未命中时异步加载后回写。

```swift
private struct FileIconView: NSViewRepresentable {
    let url: URL

    private static let cache = NSCache<NSURL, NSImage>()

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyDown
        view.imageAlignment = .alignCenter
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        if let cached = Self.cache.object(forKey: url as NSURL) {
            nsView.image = cached
            return
        }
        // 异步加载，避免主线程阻塞
        let nsurl = url as NSURL
        Task.detached(priority: .utility) {
            let icon = NSWorkspace.shared.icon(forFile: nsurl.path ?? "")
            Self.cache.setObject(icon, forKey: nsurl)
            await MainActor.run { nsView.image = icon }
        }
    }
}
```

### 3.2 visibleNodes 缓存

**问题：** `visibleNodes` 是无缓存计算属性，每次 SwiftUI 访问都全量执行过滤逻辑。

**修复：** 改为 `@Published` 存储属性，由相关状态变化驱动刷新。

**`FileBrowserViewModel.swift` 变更：**

```swift
// 改为存储属性
@Published private(set) var visibleNodes: [(node: FileNode, depth: Int)] = []

// 在 init 和所有会影响可见节点的操作后调用
private func rebuildVisibleNodes() {
    // 原 visibleNodes 计算属性的逻辑移至此处
    var result: [(FileNode, Int)] = []
    let baseNodes: [FileNode]
    if let focusURL = focusedRootURL,
       let focusNode = findNodeByURL(url: focusURL, in: rootNodes),
       let children = focusNode.children {
        baseNodes = children
    } else {
        baseNodes = rootNodes
    }
    let source = filterText.isEmpty && activeExtensions.isEmpty && activeGitStatuses.isEmpty
        ? baseNodes
        : filterTree(nodes: baseNodes, query: filterText.lowercased())
    collectVisible(from: source, depth: 0, into: &result)
    visibleNodes = result
}
```

**触发时机**（在以下操作末尾调用 `rebuildVisibleNodes()`）：

- `reload()` 完成后
- `toggleExpand()` 后
- `filterText` didSet
- `activeExtensions` didSet
- `activeGitStatuses` didSet
- `focusedRootURL` didSet
- `showHiddenFiles` didSet
- `overrideRootDir` didSet

---

## 改动文件清单

| 文件 | 改动 |
|------|------|
| `FileBrowserPanel.swift` | `onSingleClick` 移除目录 toggleExpand；`onDoubleClick` 对目录执行 toggleExpand |
| `FileNodeRow.swift` | `.onHover` 加 50ms 防抖 Task；`FileIconView` 加静态 NSCache + 异步加载 |
| `FileBrowserViewModel.swift` | `visibleNodes` 改为 `@Published` 存储属性，新增 `rebuildVisibleNodes()`，各入口调用 |

---

## 不在本次范围内

- 虚拟化列表（行级 recycling）
- 图标预加载（预取视口外图标）
- 文件系统监听防抖（FSEvents 重复触发问题）
