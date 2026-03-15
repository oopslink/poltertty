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
- 面板宽度 per-workspace 持久化（见第 7 节）
- `PolterttyRootView` 中在 `WorkspaceSidebar` 和 `terminalView` 之间插入
- 面板关闭时完全从布局中移除（不占宽度）

## 3. 功能范围

### 3.1 目录树

- 展开/折叠目录（点击 chevron 或目录名）
- 文件/目录图标（系统 `NSWorkspace.shared.icon(forFile:)`）
- 单击：高亮选中
- 双击：用默认 App 打开（`NSWorkspace.shared.open(url)`）
- 隐藏文件（`.` 开头）默认隐藏，按 `.` 键切换（仅当面板 focused）
- `rootDir` 为空或路径不存在时，面板显示空状态提示，不启动 FSEvents 监控

### 3.2 Git 状态标注

| 状态 | 符号 | 颜色 |
|------|------|------|
| Modified | M | 黄色 `#facc15` |
| Added | A | 绿色 `#4ade80` |
| Deleted | D | 红色 `#f87171` |
| Untracked | ? | 灰色 `#9ca3af` |

- 目录继承子节点最高优先级状态：`max()` over children（D > M > A > ?）
- rootDir 不是 git repo 时静默忽略（`git status` exit code ≠ 0）
- 通过异步 `Process()` 运行 `git -C rootDir status --porcelain`
- **解析规则**：`--porcelain` 输出每行前两个字符为 `XY`（X=index, Y=working-tree）。优先取 working-tree 列（Y）；若 Y 为空格或 `-` 则取 X。若任一列为 `?`，状态为 `.untracked`。映射：`M`/`m` → `.modified`，`A` → `.added`，`D` → `.deleted`，`?` → `.untracked`；其余字符忽略。

### 3.3 Filter 搜索栏

面板顶部 filter 输入框有两种模式：

- **普通模式**（默认）：按名称过滤当前已展开的节点，未展开的目录内部不搜索
- **递归模式**（`Cmd+F` 激活）：自动展开所有目录，搜索所有节点名称；清空 filter 时折叠回激活前的展开状态
- 清空输入框退出当前模式，恢复原始展开状态

### 3.4 文件操作

**所有键盘快捷键仅在文件浏览器面板 focused 时生效**，不会干扰 terminal 输入。右键菜单在任意时候可用（不依赖面板 focus）。

| 操作 | 快捷键（面板 focused） | 右键菜单 |
|------|------|------|
| Open in Terminal | T | ✓ |
| 复制路径 | Cmd+Shift+C | ✓ |
| 新建文件 | N | ✓ |
| 新建目录 | Shift+N | ✓ |
| 重命名 | R（inline edit） | ✓ |
| 删除（移到废纸篓） | Cmd+Delete | ✓ |

### 3.5 终端联动

- **Open in Terminal**：向当前 focused surface 注入 `cd <path>\n`
  - 通过 `TerminalController.injectToActiveSurface(_ text: String)` 实现
  - `injectToActiveSurface` 查找 `surfaceTree` 中 focused surface，调用 Ghostty C API（`ghostty_surface_text` 或等效接口）注入文本
- **拖拽路径到 terminal**：使用 `SurfaceView` 现有的 AppKit `NSDraggingDestination` 路径处理 `.fileURL` 类型（不新增 SwiftUI `.onDrop` 以避免与现有 AppKit drop 逻辑冲突）。如果现有 `NSDraggingDestination` 实现已支持 `.fileURL`，直接复用；否则在 `SurfaceView_AppKit` 的 `performDragOperation` 中增加对 `.fileURL` 的处理，插入路径字符串。

### 3.6 FSEvents 实时监控

- 使用 CoreServices `FSEventStreamCreate`（`kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes`），递归监听 `rootDir`
- Stream 调度到 `DispatchQueue`（后台队列），回调切到 `@MainActor` 更新 ViewModel
- 300ms debounce（`DispatchWorkItem` cancel+reschedule）后调用 `FileBrowserViewModel.reload()`
- Workspace 切换到后台时调用 `FSEventStreamStop`，激活时 `FSEventStreamStart` 并强制 reload
- `rootDir` 为空或不存在时不创建 stream

## 4. 数据模型

```swift
// FileNode — 值类型，ViewModel 统一管理整个树的更新
struct FileNode: Identifiable {
    let id: UUID
    let url: URL
    var isDirectory: Bool
    var isExpanded: Bool = false
    var children: [FileNode]?  // nil = 目录但未加载；[] = 空目录或文件
    var gitStatus: GitStatus?
}

enum GitStatus: Int, Comparable {
    case untracked = 0   // ?
    case added = 1       // A
    case modified = 2    // M
    case deleted = 3     // D — 最高优先级
    // 目录继承：children.compactMap(\.gitStatus).max()
}
```

`FileNode` 使用 `struct`（值类型）而非 `ObservableObject` class，避免大型目录树下大量 Combine publisher 的性能开销。整棵树通过 `FileBrowserViewModel`（单一 `@ObservableObject`）统一 `@Published` 刷新。

## 5. 组件划分

所有文件位于 `macos/Sources/Features/Workspace/FileBrowser/`：

| 文件 | 职责 |
|------|------|
| `FileBrowserPanel.swift` | 主容器视图，toolbar + tree scroll view + footer |
| `FileBrowserViewModel.swift` | `@ObservableObject`，持有根 FileNode 数组，filter/hidden 状态，git 状态，调用 reload |
| `FileNode.swift` | 数据模型（struct），懒加载子节点逻辑 |
| `FileNodeRow.swift` | 单行视图，indent + icon + name + git badge |
| `FileSystemMonitor.swift` | FSEventStream 封装，debounce，暂停/恢复接口 |
| `GitStatusService.swift` | 异步跑 `git status --porcelain`，返回 `[String: GitStatus]` |

## 6. FileBrowserViewModel 所有权

`WorkspaceModel` 是 `struct`，无法持有 `ObservableObject`。`FileBrowserViewModel` 实例由 `WorkspaceManager` 以 `[UUID: FileBrowserViewModel]` 字典持有：

```swift
// WorkspaceManager.swift
private var fileBrowserViewModels: [UUID: FileBrowserViewModel] = [:]

func fileBrowserViewModel(for workspaceId: UUID) -> FileBrowserViewModel {
    if let existing = fileBrowserViewModels[workspaceId] { return existing }
    let ws = workspace(id: workspaceId)
    let vm = FileBrowserViewModel(rootDir: ws?.rootDirExpanded ?? "")
    fileBrowserViewModels[workspaceId] = vm
    return vm
}

func removeFileBrowserViewModel(for workspaceId: UUID) {
    fileBrowserViewModels[workspaceId]?.stop()
    fileBrowserViewModels.removeValue(forKey: workspaceId)
}
```

`PolterttyRootView` 通过 `WorkspaceManager.shared.fileBrowserViewModel(for: workspaceId)` 获取 ViewModel，用 `@StateObject` 包装（SwiftUI 管理生命周期）。Workspace 删除时 `WorkspaceManager` 清理对应 ViewModel。

## 7. 面板状态持久化

`fileBrowserVisible` 和 `fileBrowserWidth` 需要 per-workspace 持久化。由于 `WorkspaceModel` 使用手写 `init(from:)` decoder，新增字段必须使用 `decodeIfPresent` 加默认值：

```swift
// WorkspaceModel.swift — 新增字段
var fileBrowserVisible: Bool = false
var fileBrowserWidth: CGFloat = 260

// init(from:) 中新增：
fileBrowserVisible = try container.decodeIfPresent(Bool.self, forKey: .fileBrowserVisible) ?? false
fileBrowserWidth   = try container.decodeIfPresent(CGFloat.self, forKey: .fileBrowserWidth) ?? 260
```

这确保旧 JSON 文件（无这两个字段）反序列化时使用默认值，向后兼容。

**saveSnapshot 集成**：`PolterttyRootView` 新增两个 accessor vars，与现有 `currentSidebarWidth`/`currentSidebarVisible` 同等地位：

```swift
var currentFileBrowserVisible: Bool { ... }
var currentFileBrowserWidth: CGFloat { ... }
```

`TerminalController` 在调用 `saveSnapshot` 前，将这两个值写回对应 `WorkspaceModel`（通过 `WorkspaceManager.update(id:)`），保证快照时状态最新。

**临时 Workspace**：遵循现有 `save()` guard，不持久化到磁盘。

## 8. 现有代码改动

### WorkspaceModel（`WorkspaceModel.swift`）
- 新增 `fileBrowserVisible: Bool`、`fileBrowserWidth: CGFloat`（`decodeIfPresent` + 默认值）

### WorkspaceManager（`WorkspaceManager.swift`）
- 新增 `fileBrowserViewModels: [UUID: FileBrowserViewModel]`
- 新增 `fileBrowserViewModel(for:)` 和 `removeFileBrowserViewModel(for:)` 方法
- workspace 删除时调用 `removeFileBrowserViewModel`

### PolterttyRootView（`PolterttyRootView.swift`）
- terminal mode HStack 中在 Sidebar 和 terminalView 之间插入 `FileBrowserPanel`
- 新增 `.toggleFileBrowser` notification 接收，notification userInfo 携带 `workspaceId`，仅响应匹配本窗口 workspace 的通知
- 新增 `currentFileBrowserVisible`、`currentFileBrowserWidth` accessor vars

### TerminalController（`TerminalController.swift`）
- `Cmd+\` 注册为 `NSMenuItem`（在 `AppDelegate` 菜单构建处，与 `toggleWorkspaceSidebar` 同等模式）
- 实现 `injectToActiveSurface(_ text: String)`

### Notification.Name（`PolterttyRootView.swift` 顶部）
```swift
static let toggleFileBrowser = Notification.Name("poltertty.toggleFileBrowser")
```
通知 post 时携带 `userInfo: ["workspaceId": workspaceId]`，接收方过滤匹配。

### AppDelegate（`AppDelegate.swift`）
- 在菜单构建处新增 `Cmd+\` 菜单项，action 为 post `.toggleFileBrowser`（携带 keyWindow 的 workspaceId）

## 9. 不在本次范围内

- Sort 选项（name/size/modified/kind）
- 多选
- Pinned directories
- Preview file (Space)
- Open in $EDITOR (E)
- MCP addressability
