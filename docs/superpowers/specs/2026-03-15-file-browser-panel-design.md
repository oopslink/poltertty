# File Browser Panel — Design Spec

**Date:** 2026-03-15
**Status:** Approved

## 1. Overview

在 Workspace 的 Sidebar 和 Terminal 区域之间插入一个独立的文件浏览器面板，展示当前 Workspace 的 `rootDir` 目录树。面板状态 per-workspace 独立保存，通过 `Cmd+\` 切换显示/隐藏。

## 2. 布局

```
┌──────────┬──────────────────┬─────────────────────────┐
│ Workspace│  File Browser    │   Terminal (splits)     │
│ Sidebar  │  Panel           │                         │
│  (48px   │  (260px default, │                         │
│  or      │   draggable)     │                         │
│  200px)  │                  │                         │
└──────────┴──────────────────┴─────────────────────────┘
```

- 默认宽度：260px，可拖拽调整
- 面板宽度 per-workspace 持久化到 `WorkspaceModel`
- `PolterttyRootView` 中在 `WorkspaceSidebar` 和 `terminalView` 之间插入
- 面板关闭时完全从布局中移除（不占宽度）

## 3. 功能范围

### 3.1 目录树

- 展开/折叠目录（点击 chevron 或目录名）
- 文件/目录图标（SF Symbols 或系统图标）
- 单击：高亮选中
- 双击：用默认 App 打开（`NSWorkspace.shared.open(url)`）
- 隐藏文件（`.` 开头）默认隐藏，按 `.` 键切换

### 3.2 Git 状态标注

| 状态 | 符号 | 颜色 |
|------|------|------|
| Modified | M | 黄色 `#facc15` |
| Added | A | 绿色 `#4ade80` |
| Deleted | D | 红色 `#f87171` |
| Untracked | ? | 灰色 `#9ca3af` |

- 目录继承子节点最高优先级状态（D > M > A > ?）
- rootDir 不是 git repo 时静默忽略（`git status` exit code ≠ 0）
- 通过异步 `Process()` 运行 `git -C rootDir status --porcelain`

### 3.3 Filter 搜索栏

- 面板顶部输入框，实时过滤当前展开的节点
- `Cmd+F` 聚焦到 filter 输入框并开启递归搜索模式
- 清空 filter 恢复原始树

### 3.4 文件操作

通过右键菜单和键盘快捷键触发：

| 操作 | 快捷键 |
|------|--------|
| 新建文件 | N |
| 新建目录 | Shift+N |
| 重命名 | R（inline edit） |
| 删除（移到废纸篓） | Cmd+Delete |
| 复制路径 | Cmd+Shift+C |
| Open in Terminal | T |

### 3.5 终端联动

- **Open in Terminal**：向当前 focused surface 注入 `cd <path>\n`
  - 通过 `TerminalController.injectToActiveSurface(_ text: String)` 实现
  - `injectToActiveSurface` 查找 `surfaceTree` 中 focused surface，调用 Ghostty C API 注入文本
- **拖拽路径到 terminal**：`FileNode` conform `Transferable`，提供 `.fileURL` representation；`SurfaceView` 增加 `.onDrop(of: [.fileURL])` 处理插入路径字符串

### 3.6 FSEvents 实时监控

- 用 macOS FSEvents 监听 `rootDir` 目录树递归变化
- 300ms debounce 后调用 `FileBrowserViewModel.reload()`
- Workspace 切换到后台时暂停监听，激活时恢复并强制 reload
- 实现类：`FileSystemMonitor`，封装 `DispatchSource` 或 CoreServices FSEventStream

## 4. 数据模型

```swift
// FileNode — 懒加载子目录
class FileNode: ObservableObject, Identifiable {
    let url: URL
    var isDirectory: Bool
    @Published var isExpanded: Bool = false
    @Published var children: [FileNode]?  // nil = not yet loaded
    var gitStatus: GitStatus?
}

enum GitStatus: Int, Comparable {
    case untracked = 0
    case added = 1
    case modified = 2
    case deleted = 3  // 最高优先级
}
```

## 5. 组件划分

所有文件位于 `macos/Sources/Features/Workspace/FileBrowser/`：

| 文件 | 职责 |
|------|------|
| `FileBrowserPanel.swift` | 主容器视图，toolbar + tree + footer |
| `FileBrowserViewModel.swift` | `@ObservableObject`，持有根 FileNode，filter/hidden 状态，调用 reload |
| `FileNode.swift` | 数据模型，懒加载子节点 |
| `FileNodeRow.swift` | 单行视图，indent + icon + name + git badge |
| `FileSystemMonitor.swift` | FSEvents 封装，debounce publish |
| `GitStatusService.swift` | 异步跑 `git status --porcelain`，返回 `[String: GitStatus]` |

## 6. 现有代码改动

### WorkspaceModel
新增两个字段（持久化到 JSON）：
```swift
var fileBrowserVisible: Bool = false
var fileBrowserWidth: CGFloat = 260
```

### PolterttyRootView
在 terminal mode 的 HStack 中，Sidebar 和 terminalView 之间插入：
```swift
if workspace.fileBrowserVisible {
    FileBrowserPanel(viewModel: workspace.fileBrowserViewModel)
        .frame(width: workspace.fileBrowserWidth)
    Divider()
}
```
接收 `.toggleFileBrowser` notification，toggle `currentWorkspace.fileBrowserVisible`。

### TerminalController
- 注册 `Cmd+\` 快捷键 → post `.toggleFileBrowser`
- 实现 `injectToActiveSurface(_ text: String)`

### Notification.Name（PolterttyRootView.swift）
```swift
static let toggleFileBrowser = Notification.Name("poltertty.toggleFileBrowser")
```

## 7. 面板状态持久化

`fileBrowserVisible` 和 `fileBrowserWidth` 存储在 `WorkspaceModel`（JSON 文件），随 workspace save/load 自动持久化。临时 Workspace 不持久化（遵循现有 `save()` guard）。

## 8. 不在本次范围内

- Sort 选项（name/size/modified/kind）
- 多选
- Pinned directories
- Preview file (Space)
- Open in $EDITOR (E)
- MCP addressability
