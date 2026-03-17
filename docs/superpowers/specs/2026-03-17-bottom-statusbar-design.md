# 底部状态栏设计文档

**日期:** 2026-03-17
**状态:** 草稿 v1

---

## 概述

为 Poltertty 终端窗口添加底部状态栏，显示当前工作目录路径和 git 分支及脏状态。独立实现，不与已批准的 `worktree-statusbar` 设计合并。

---

## 目标

- 显示当前焦点 surface 的工作目录（`~` 缩写）
- 显示当前 git 分支名及脏状态计数（`+N ~M`）
- pwd 变化和 `.git/HEAD` / `.git/index` 变化时即时刷新
- 非 git repo 时自动隐藏右侧 git 区域
- 临时 workspace 不显示状态栏

## 非目标

- 不合并 worktree 导航功能（由 worktree-statusbar 设计覆盖）
- 不支持 fetch / pull 等 git 操作
- 不支持手动隐藏/折叠
- 不修改任何上游 Ghostty 文件

---

## 视觉设计

```
┌─────────────────────────────────────────────────────────────┐
│  ~/works/codes/poltertty/src          ⎇ main  +2 ~1        │
└─────────────────────────────────────────────────────────────┘
```

- 固定高度 22px
- 背景：`Color(nsColor: .windowBackgroundColor).opacity(0.95)`
- 顶部 1px 分割线：`Color(nsColor: .separatorColor)`
- 字体：11px system font
- 左侧路径：`.secondary` 颜色，超长时截断左侧保留末尾
- 右侧分支名：`.primary` 颜色；`+N` 绿色；`~M` 黄色
- `isGitRepo == false` 时整个 view 渲染为零高度

**可见性规则：**

| 条件 | 状态栏 |
|------|--------|
| 临时 workspace | 不渲染 |
| `isGitRepo == false` | `EmptyView()`（零高度） |
| 一个分支，无脏文件 | `⎇ main` |
| 有脏文件 | `⎇ main  +2 ~1` |
| detached HEAD | `⎇ detached` |

---

## 数据模型

```swift
struct GitStatus: Equatable {
    let branch: String?   // nil = detached HEAD
    let added: Int        // untracked + staged new 行数
    let modified: Int     // staged modified + unstaged modified 行数
    let isGitRepo: Bool
}
```

---

## GitStatusMonitor

新文件：`macos/Sources/Features/Workspace/GitStatusMonitor.swift`

```swift
class GitStatusMonitor: ObservableObject {
    @Published var status: GitStatus = GitStatus(branch: nil, added: 0, modified: 0, isGitRepo: false)

    init(pwd: String)
    func updatePwd(_ path: String)
    private func refresh()
    private func setupWatching()
    private func stopWatching()
}
```

### 初始化

`init(pwd:)` 检测 git root（`git rev-parse --show-toplevel`），成功则设 `isGitRepo = true` 并调用 `setupWatching()`；失败则 `isGitRepo = false`。

subprocess 环境：`["HOME": NSHomeDirectory()]`。

### 文件监听策略

`DispatchSource.makeFileSystemObjectSource` 监听两个文件：

- `.git/HEAD`：分支切换时触发
- `.git/index`：暂存区变化时触发

每个 source 的 fd 在 `makeFileSystemObjectSource` 前 `open(2)`，在 `setCancelHandler` 中 `close(2)`。

两个 source 触发均走同一 debounced `refresh()`（300ms `DispatchWorkItem`）。

### refresh()

顺序执行两条命令：

1. `git -C <pwd> branch --show-current` → `branch`（空输出 = detached HEAD，`branch = nil`）
2. `git -C <pwd> status --porcelain` → 逐行解析：
   - `added`：`??` 开头（untracked）+ `A ` 开头（staged new）
   - `modified`：`M ` / ` M` / `MM` 开头

结果构造 `GitStatus` 并 `DispatchQueue.main.async` 赋值给 `status`。

### updatePwd

调用 `stopWatching()`，重新检测 git root，调用 `setupWatching()`。

### stopWatching

取消所有活跃 `DispatchSource`（cancel handler 关闭 fd），取消 pending `DispatchWorkItem`。`deinit` 中调用。

---

## BottomStatusBarView

新文件：`macos/Sources/Features/Workspace/BottomStatusBarView.swift`

```swift
struct BottomStatusBarView: View {
    @ObservedObject var monitor: GitStatusMonitor
}
```

布局结构：

```
VStack(spacing: 0) {
    Divider()  // 1px 顶部分割线
    HStack {
        // 左：文件夹图标 + pwd 路径
        Label(abbreviatedPwd, systemImage: "folder")
            .lineLimit(1)
            .truncationMode(.head)
        Spacer()
        // 右：git 区域（isGitRepo == false 时不渲染）
        if monitor.status.isGitRepo {
            gitStatusView
        }
    }
    .padding(.horizontal, 8)
    .frame(height: 22)
    .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
}
```

`abbreviatedPwd`：将 `NSHomeDirectory()` 替换为 `~`。

`gitStatusView`：

```
HStack(spacing: 4) {
    Image(systemName: "arrow.triangle.branch")
    Text(branch ?? "detached")
    if added > 0 { Text("+\(added)").foregroundColor(.green) }
    if modified > 0 { Text("~\(modified)").foregroundColor(.yellow) }
}
.font(.system(size: 11))
```

---

## 集成点

### PolterttyRootView.swift

新增构造参数：

```swift
let statusMonitor: GitStatusMonitor
let isTemporaryWorkspace: Bool
```

`body` 的 `ZStack` 末尾添加：

```swift
.safeAreaInset(edge: .bottom, spacing: 0) {
    if !isTemporaryWorkspace {
        BottomStatusBarView(monitor: statusMonitor)
    }
}
```

pwd 监听（在 `.terminal` case 的 VStack 或顶层）：

```swift
@FocusedValue(\.ghosttySurfacePwd) var focusedPwd

.onChange(of: focusedPwd) { newPwd in
    guard let pwd = newPwd else { return }
    statusMonitor.updatePwd(pwd)
}
```

### TerminalController.swift

新增存储属性：

```swift
let statusMonitor: GitStatusMonitor
```

初始化（`super.init` 之前，`workspaceId` 赋值之后）：

```swift
let rootDir = workspaceId
    .flatMap { WorkspaceManager.shared.workspace(for: $0) }?.rootDirExpanded
    ?? NSHomeDirectory()
self.statusMonitor = GitStatusMonitor(pwd: rootDir)
```

`windowDidLoad` 新增传参：

```swift
let isTemporary = workspaceId
    .flatMap { WorkspaceManager.shared.workspace(for: $0) }?.isTemporary ?? false

// PolterttyRootView(...) 新增：
statusMonitor: self.statusMonitor,
isTemporaryWorkspace: isTemporary,
```

---

## 错误处理

| 场景 | 行为 |
|------|------|
| 不是 git repo | `isGitRepo = false`，右侧 git 区域不渲染 |
| `git` 命令失败 | `NSLog` 错误，保持上次已知状态 |
| pwd 为空或无效 | `updatePwd` 跳过，不重置监听 |
| `.git/HEAD` / `.git/index` 不存在 | source 不启动，仅依赖 pwd 变化触发刷新 |
| detached HEAD | `branch = nil`，显示 `⎇ detached` |
| window 关闭 | `deinit` 调用 `stopWatching()`，fd 全部关闭 |
| 临时 workspace | view 不渲染，monitor 以 `NSHomeDirectory()` 初始化但不影响性能 |

---

## 文件清单

**新增：**
- `macos/Sources/Features/Workspace/GitStatusMonitor.swift`
- `macos/Sources/Features/Workspace/BottomStatusBarView.swift`

**修改：**
- `macos/Sources/Features/Workspace/PolterttyRootView.swift` — 新增参数 + `.safeAreaInset` + `.onChange`
- `macos/Sources/Features/Terminal/TerminalController.swift` — 新增 `statusMonitor` 属性 + 初始化 + 传参

**上游文件：零修改**
