# 底部状态栏设计文档

**日期:** 2026-03-17
**状态:** 草稿 v3

---

## 概述

为 Poltertty 终端窗口添加底部状态栏，显示当前工作目录路径和 git 分支及脏状态。独立实现，不与已批准的 `worktree-statusbar` 设计合并。

---

## 目标

- 显示当前焦点 surface 的工作目录（`~` 缩写）
- 显示当前 git 分支名及脏状态计数（`+N ~M`）
- pwd 变化和 `.git/HEAD` / `.git/index` 变化时即时刷新
- 非 git repo 时自动隐藏整个状态栏
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
- 左侧路径：`.secondary` 颜色，超长时截断左侧保留末尾（`.truncationMode(.head)`）
- 右侧分支名：`.primary` 颜色；`+N` 绿色；`~M` 黄色

**可见性规则：**

| 条件 | 状态栏 |
|------|--------|
| 临时 workspace 或 `workspaceId == nil` | 不渲染（`showStatusBar = false`，由 `TerminalController` 计算传入） |
| `isGitRepo == false` | 整个状态栏不渲染（`EmptyView()`，零高度零占位） |
| 一个分支，无脏文件 | 左侧路径 + 右侧 `⎇ main` |
| 有脏文件 | 左侧路径 + 右侧 `⎇ main  +2 ~1` |
| detached HEAD | 左侧路径 + 右侧 `⎇ detached` |

> **注：** `isGitRepo == false` 时状态栏完全消失（含左侧路径），不仅隐藏右侧 git 区域。

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

    private let queue = DispatchQueue(label: "poltertty.git-status-monitor")
}
```

### 内部串行队列

`GitStatusMonitor` 使用私有串行队列 `queue`。所有 `DispatchSource` 的目标 queue 均设为该串行 queue（`source.setTarget(queue: queue)`），确保 source handler 与 `stopWatching()` 串行执行，消除取消竞态。`refresh()` 在串行 queue 上执行，完成后通过 `DispatchQueue.main.async` 更新 `@Published` 属性。

### 初始化

`init(pwd:)` 通过 `queue.async` 异步分发 git root 检测（`/usr/bin/git -C <pwd> rev-parse --show-toplevel`），不阻塞调用线程（`TerminalController.init` 可安全调用）：
- 成功（exit 0）→ 在串行 queue 上设 `isGitRepo = true`，调用 `setupWatching()`
- 失败（exit 非 0）→ `isGitRepo = false`，不启动监听

subprocess 使用绝对路径 `/usr/bin/git`，不设自定义环境变量（与现有 `GitStatusService.swift` 保持一致）。

### 文件监听策略

`DispatchSource.makeFileSystemObjectSource` 监听两个文件：

- `<gitRoot>/.git/HEAD`：分支切换时触发
- `<gitRoot>/.git/index`：暂存区变化时触发

每个 source 的 fd 在 `makeFileSystemObjectSource` 之前 `open(2)`；`open(2)` 返回 -1 时 `NSLog` 错误并跳过该 source（不启动），不影响另一个 source。fd 有效时在 `setCancelHandler` 中 `close(2)`。两个 source 的目标 queue 均设为内部串行 `queue`。

两个 source 触发均走同一 debounced `refresh()`（300ms `DispatchWorkItem`，调度在串行 `queue` 上）。

### refresh()

在串行 queue 上顺序执行两条命令：

1. `/usr/bin/git -C <pwd> branch --show-current` → `branch`（空输出 = detached HEAD，`branch = nil`）
2. `/usr/bin/git -C <pwd> status --porcelain` → 逐行解析（每行前两字符为 XY 状态码，`chars[0]` = index 列，`chars[1]` = worktree 列）：
   - `added`：`chars[0] == "?" && chars[1] == "?"`（untracked），或 `chars[0] == "A"`（staged new，严格匹配 `A`，不含 `R`/`C`，有意设计）
   - `modified`：`chars[0] == "M"` 或 `chars[1] == "M"`（staged/unstaged modified）

结果构造 `GitStatus`，通过 `DispatchQueue.main.async` 赋值给 `status`。

### updatePwd

- `path` 为空时直接返回，保留当前监听和状态（有意保留"上次已知状态"）
- 否则：通过 `queue.async` 分发，在串行 queue 上调用 `stopWatching()`，重新检测 git root，调用 `setupWatching()`

### stopWatching

取消所有活跃 `DispatchSource`（cancel handler 关闭 fd），取消 pending `DispatchWorkItem`，均在串行 queue 上执行。`deinit` 中调用。

---

## BottomStatusBarView

新文件：`macos/Sources/Features/Workspace/BottomStatusBarView.swift`

```swift
struct BottomStatusBarView: View {
    @ObservedObject var monitor: GitStatusMonitor
    let pwd: String
}
```

布局结构：

```swift
var body: some View {
    let status = monitor.status
    if !status.isGitRepo {
        EmptyView()  // 零高度，整个状态栏消失
    } else {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 6) {
                // 左：路径
                Label(abbreviatedPwd, systemImage: "folder")
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                // 右：git 状态
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                    Text(status.branch ?? "detached")
                        .foregroundColor(.primary)
                    if status.added > 0 {
                        Text("+\(status.added)").foregroundColor(.green)
                    }
                    if status.modified > 0 {
                        Text("~\(status.modified)").foregroundColor(.yellow)
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        }
        .font(.system(size: 11))
    }
}

private var abbreviatedPwd: String {
    pwd.replacingOccurrences(of: NSHomeDirectory(), with: "~")
}
```

> `pwd` 由 `PolterttyRootView` 从 `@FocusedValue(\.ghosttySurfacePwd)` 传入，避免 view 内部持有 FocusedValue 依赖。

---

## 集成点

### PolterttyRootView.swift

新增构造参数（加在 `init` 签名末尾，保持现有参数顺序不变）：

```swift
let statusMonitor: GitStatusMonitor
let showStatusBar: Bool   // false = 临时 workspace 或 workspaceId == nil
```

新增 `@FocusedValue`：

```swift
@FocusedValue(\.ghosttySurfacePwd) private var focusedPwd
```

**`.safeAreaInset` 挂载在 `.terminal` case 的 `HStack` 上**（不挂在外层 ZStack，避免影响 onboarding / restore 界面）：

```swift
case .terminal:
    HStack(spacing: 0) {
        // ... sidebar, file browser, terminalAreaView ...
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
        if showStatusBar {
            BottomStatusBarView(
                monitor: statusMonitor,
                pwd: focusedPwd ?? ""
            )
        }
    }
    .onChange(of: focusedPwd) { newPwd in
        // 单参数 closure，兼容 macOS 13+（项目最低支持版本）
        guard let pwd = newPwd, !pwd.isEmpty else { return }
        statusMonitor.updatePwd(pwd)
    }
```

### TerminalController.swift

新增 `let` 存储属性（不可变，Swift 要求在 `super.init` 前完成赋值）：

```swift
let statusMonitor: GitStatusMonitor
```

初始化位置：在 `self.workspaceId = workspaceId` 之后、`super.init()` 之前，与其他 `let` 属性一起：

```swift
let rootDir = workspaceId
    .flatMap { WorkspaceManager.shared.workspace(for: $0) }?.rootDirExpanded
    ?? NSHomeDirectory()
self.statusMonitor = GitStatusMonitor(pwd: rootDir)
// super.init(...) 紧随其后
```

`windowDidLoad` 新增传参：

```swift
// workspaceId == nil（非 workspace 窗口）或 isTemporary 时均不显示状态栏
let showStatusBar: Bool = {
    guard let id = workspaceId,
          let ws = WorkspaceManager.shared.workspace(for: id) else { return false }
    return !ws.isTemporary
}()

// PolterttyRootView(...) 新增（末尾参数）：
statusMonitor: self.statusMonitor,
showStatusBar: showStatusBar,
```

---

## 错误处理

| 场景 | 行为 |
|------|------|
| 不是 git repo | `isGitRepo = false`，整个状态栏不渲染（含路径） |
| `git` 命令失败 | `NSLog` 错误，保持上次已知状态 |
| pwd 为空 | `updatePwd` 直接返回，保留当前监听和状态 |
| `.git/HEAD` / `.git/index` 不存在 | source 不启动，仅依赖 pwd 变化触发刷新 |
| detached HEAD | `branch = nil`，显示 `⎇ detached` |
| window 关闭 | `deinit` 调用 `stopWatching()`，fd 全部关闭 |
| 临时 workspace 或 `workspaceId == nil` | `showStatusBar = false`，view 不渲染；monitor 以 `NSHomeDirectory()` 初始化但不影响性能 |
| source cancel 竞态 | 串行 queue 保证 cancel 与 handler 不并发 |

---

## 文件清单

**新增：**
- `macos/Sources/Features/Workspace/GitStatusMonitor.swift`
- `macos/Sources/Features/Workspace/BottomStatusBarView.swift`

**修改：**
- `macos/Sources/Features/Workspace/PolterttyRootView.swift` — 新增参数 + `.safeAreaInset`（挂 `.terminal` HStack）+ `.onChange`
- `macos/Sources/Features/Terminal/TerminalController.swift` — 新增 `statusMonitor` `let` 属性 + 初始化 + 传参

**上游文件：零修改**
