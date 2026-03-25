# Git Panel — Design Spec

**Date:** 2026-03-25
**Status:** Approved

## Overview

在 Poltertty 侧边栏新增独立的 **Git Tab**，提供仓库级提交历史、文件变更管理、diff 查看、文件历史及 revert 操作。所有 git 操作统一通过 libgit2（C API + Swift 薄封装）实现，废弃现有 subprocess 方案。

## Goals

- **Changes 管理**：查看 staged/unstaged 文件列表，支持 stage、unstage、discard
- **提交历史**：仓库级 git log，commit 展开后显示变更文件 + diff
- **文件历史**：FileBrowser 右键进入文件级 commit 历史，支持 restore to commit
- **统一 git 后端**：废弃所有 subprocess 调用，统一走 libgit2

## Out of Scope

- Side-by-side（双栏对比）diff（v2）
- Stash 管理
- Branch 创建/删除（已有 worktree 面板覆盖）
- Push / Pull / Fetch 等远程操作
- Inline blame（v2）
- Commit 提交（UI 上预留按钮，功能 v2）

---

## 废弃文件

| 废弃文件 | 原因 |
|---------|------|
| `FileBrowser/GitStatusService.swift` | 替换为 `GitRepository` |
| `Workspace/GitStatusMonitor.swift` | 替换为 `GitRepository` + ViewModel |
| `FileBrowser/DiffView.swift` | 替换为结构化 `DiffView` |
| FileBrowserViewModel 中的 git 逻辑 | 改为调用 `GitRepository.status()` |

---

## 架构

```
libgit2 (vendored 静态库, universal binary)
    │  C API via Clibgit2 SPM system library target
    ▼
GitRepository (Swift actor)
    │  async throws API
    ▼
GitPanelViewModel (ObservableObject, @MainActor)
FileBrowserViewModel (git status 部分)
    │
    ▼
GitPanelView (侧边栏 Git tab)
DiffView (结构化渲染)
FileBrowser 右键菜单扩展
```

---

## libgit2 集成

**目录结构：**
```
macos/vendor/libgit2/
├── include/          # libgit2 头文件
├── lib/
│   └── libgit2.a    # 预编译 universal binary (arm64 + x86_64)
└── module.modulemap
```

**Package.swift：**
```swift
.systemLibrary(
    name: "Clibgit2",
    path: "vendor/libgit2"
),
.target(
    name: "GitKit",
    dependencies: ["Clibgit2"],
    path: "Sources/GitKit"
)
```

---

## 数据模型

```swift
struct GitCommit: Identifiable, Equatable {
    let id: String          // full SHA
    let shortId: String     // 前7位
    let message: String     // 第一行 summary
    let author: String
    let date: Date
    let parentIds: [String]
}

struct GitCommitFile: Identifiable {
    let id: String          // path
    let path: String
    let delta: GitDelta
    let oldPath: String?    // renamed 时的旧路径
}

enum GitDelta {
    case added, modified, deleted, renamed, untracked
}

struct GitFileDiff {
    let commitFile: GitCommitFile
    let patches: [GitPatch]
}

struct GitPatch {
    let header: String      // @@ -a,b +c,d @@
    let lines: [GitDiffLine]
}

struct GitDiffLine {
    enum Origin { case added, removed, context }
    let origin: Origin
    let oldLineNo: Int?
    let newLineNo: Int?
    let content: String
}

struct GitChange: Identifiable {
    let id: String          // path
    let path: String
    let status: GitDelta
    let isStaged: Bool
}
```

---

## GitRepository（libgit2 Swift Actor）

```swift
// macos/Sources/GitKit/GitRepository.swift
actor GitRepository {
    // 初始化：传入 working directory，自动 discover git root
    init?(path: String) throws

    // 仓库状态
    func currentBranch() throws -> String?
    func status() throws -> [GitChange]           // staged + unstaged

    // 提交历史
    func log(maxCount: Int = 100) throws -> [GitCommit]
    func fileLog(path: String, maxCount: Int = 50) throws -> [GitCommit]

    // Diff
    func commitDiff(oid: String) throws -> [GitCommitFile]
    func fileDiff(oid: String, path: String) throws -> GitFileDiff
    func workingDiff(path: String, staged: Bool) throws -> GitFileDiff

    // 操作
    func stage(paths: [String]) throws
    func unstage(paths: [String]) throws
    func discard(paths: [String]) throws          // git restore（丢弃工作区变更）
    func restoreToCommit(path: String, oid: String) throws
}
```

---

## GitPanelViewModel

```swift
@MainActor
class GitPanelViewModel: ObservableObject {
    @Published var branch: String?
    @Published var stagedFiles: [GitChange] = []
    @Published var unstagedFiles: [GitChange] = []
    @Published var commits: [GitCommit] = []
    @Published var expandedCommits: Set<String> = []
    @Published var commitFiles: [String: [GitCommitFile]] = [:]  // oid → files
    @Published var selectedDiff: GitFileDiff?
    @Published var isLoading = false
    @Published var error: String?

    private var repo: GitRepository?

    func load(rootDir: String) async
    func refresh() async
    func stage(_ change: GitChange) async
    func unstage(_ change: GitChange) async
    func discard(_ change: GitChange) async
    func expandCommit(_ commit: GitCommit) async
    func selectFile(_ file: GitCommitFile, in commit: GitCommit) async
    func selectWorkingFile(_ change: GitChange, staged: Bool) async
}
```

变更监听：保留现有 DispatchSource 方式监听 `.git/HEAD` 和 `.git/index`，变更时调用 `refresh()`。

---

## UI 结构

### Git 侧边栏 Tab

```
┌─────────────────────────────────┐
│ ⎇ main  ↑2 ↓0    [↻] [+ Commit]│  ← 头部（Commit 按钮 v2）
├─────────────────────────────────┤
│ ▼ CHANGES                       │
│   ▼ Staged (2)                  │
│     M  src/Foo.swift      [−]   │  [−] = unstage
│     A  src/New.swift      [−]   │
│   ▼ Unstaged (3)                │
│     M  src/Bar.swift   [+] [✕]  │  [+] = stage, [✕] = discard
│     ?  src/Draft.swift [+] [✕]  │
│     D  src/Old.swift   [+] [✕]  │
├─────────────────────────────────┤
│ ▼ COMMITS                       │
│  ● abc1234  Add feature X  3h   │  ← 展开/折叠
│    ├ M  src/Foo.swift      →    │  → 点击右侧显示 diff
│    └ A  src/New.swift      →    │
│  ○ def5678  Fix bug Y      1d   │
│  ○ ghi9012  Refactor Z     2d   │
└─────────────────────────────────┘
```

点击文件后右侧（或下方 pane）显示 DiffView。

### DiffView（结构化渲染）

```
src/Foo.swift  ·  abc1234 · Add feature X
─────────────────────────────────────────
 12  │   │ func oldMethod() {
 13  │ - │     return nil              ← 红底
    │ + │     return value            ← 绿底
 14  │   │ }
```

基于 `GitFileDiff` 结构渲染，不再解析原始字符串。

### FileBrowser 右键菜单扩展

```
Show File History    →  打开 FileHistorySheet
─────────────────────
Discard Changes      →  仅 unstaged 文件显示
Restore to Commit…   →  打开 FileHistorySheet（选中后可 restore）
```

### FileHistorySheet

```
┌──────────────────────────────────┐
│ History: src/Foo.swift     [✕]   │
├──────────────────────────────────┤
│ ● abc1234  Add feature X   3h    │  ← 点击右侧显示 diff
│ ○ def5678  Fix bug Y       1d    │
│ ○ ghi9012  Initial commit  5d    │
├──────────────────────────────────┤
│  [Restore to Selected Commit]    │
└──────────────────────────────────┘
```

---

## 文件结构

```
macos/Sources/
├── GitKit/                          # 新 SPM target
│   ├── GitRepository.swift          # libgit2 actor wrapper
│   ├── GitModels.swift              # 数据模型
│   └── GitError.swift               # 错误类型
└── Features/
    └── Workspace/
        ├── GitPanel/
        │   ├── GitPanelView.swift
        │   ├── GitPanelViewModel.swift
        │   ├── GitChangesSection.swift
        │   ├── GitCommitsSection.swift
        │   ├── GitCommitRow.swift
        │   └── FileHistorySheet.swift
        └── FileBrowser/
            ├── DiffView.swift       # 重写（结构化）
            └── FileNodeRow.swift    # 扩展右键菜单
```

---

## 错误处理

- libgit2 错误通过 `GitError` enum 统一包装，ViewModel 捕获后写入 `@Published var error`
- 非 git repo 时 Git tab 显示 "Not a git repository" 占位
- 操作失败（discard/restore）弹 Alert 提示

---

## 测试策略

- `GitRepository` 方法用临时 git repo（`mktemp`）做集成测试
- ViewModel 用 mock `GitRepository` 做单元测试
- UI 层不测，依赖手动验证
