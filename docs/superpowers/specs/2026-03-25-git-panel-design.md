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
- 合并冲突状态展示（`UU`/`AA`/`DD` 等）（v2）
- Branch 创建/删除（已有 worktree 面板覆盖）
- Push / Pull / Fetch 等远程操作
- Inline blame（v2）
- Commit 提交（UI 上预留按钮，功能 v2）

---

## 废弃文件

| 废弃文件 | 原因 |
|---------|------|
| `FileBrowser/GitStatusService.swift` | 替换为 `GitRepository` |
| `Workspace/GitStatusMonitor.swift`（含 `GitRepoStatus`、`GitStatusParser`）| 替换为 `GitRepository` + `GitPanelViewModel` |
| `FileBrowser/DiffView.swift` | 替换为结构化 `DiffView` |
| `FileBrowser/FileNode.swift` 中的 `enum GitStatus` | 替换为 `GitDelta` |
| `FileBrowserViewModel` 中的 git 逻辑（`gitStatuses`、`refreshGitStatus()`、`stageFiles(_:)`、`unstageFiles(_:)`）| 改为调用 `GitRepository.status()` |

**底部状态栏迁移**：`BottomStatusBarView` 当前依赖 `GitRepoStatus`（branch、added、modified 计数）。废弃后改为订阅 `GitPanelViewModel`：
- `branch` → `GitPanelViewModel.branch`
- changed 计数 → `stagedFiles.count + unstagedFiles.count`

---

## 架构

```
libgit2 (vendored 静态库, universal binary)
    │  C API，通过 Xcode bridging header 引入
    ▼
GitRepository (Swift actor)
    │  async throws API，actor 串行保证线程安全
    ▼
GitPanelViewModel (@MainActor, ObservableObject)
    ├── 订阅 DispatchSource（.git/HEAD、.git/index 变更触发 refresh）
    └── FileBrowserViewModel（git status 部分）
    │
    ▼
GitPanelView（侧边栏 Git tab）
DiffView（结构化渲染）
FileBrowser 右键菜单扩展
FileHistorySheet（独立 sheet，持有轻量 FileHistoryViewModel）
```

---

## libgit2 集成

项目使用 **Xcode project**（无 SPM），libgit2 以 vendored 静态库方式引入：

**目录结构：**
```
macos/vendor/libgit2/
├── include/
│   └── git2.h（及其他头文件）
└── lib/
    └── libgit2.a    # 预编译 universal binary (arm64 + x86_64)
```

**Xcode 配置：**
- `LIBRARY_SEARCH_PATHS` 添加 `$(SRCROOT)/vendor/libgit2/lib`
- `HEADER_SEARCH_PATHS` 添加 `$(SRCROOT)/vendor/libgit2/include`
- `OTHER_LDFLAGS` 添加 `-lgit2`
- Bridging header（`Ghostty-Bridging-Header.h`）加入：
  ```c
  #import <git2.h>
  ```

**线程安全注意**：libgit2 的 `git_repository*` 句柄不支持并发访问。`GitRepository` actor 通过串行 executor 保证同一时刻只有一个 libgit2 调用执行，`git_repository*` 指针不得泄漏到 actor 外部。

---

## 数据模型

```swift
// macos/Sources/GitKit/GitModels.swift

struct GitCommit: Identifiable, Equatable {
    let id: String          // full SHA
    let shortId: String     // 前7位
    let message: String     // 第一行 summary
    let fullMessage: String // 完整提交信息（含 body）
    let author: String
    let date: Date
    let parentIds: [String]
}

struct GitCommitFile: Identifiable {
    let id: String          // path（rename 后的新路径）
    let path: String
    let delta: GitDelta
    let oldPath: String?    // renamed/copied 时的旧路径
}

enum GitDelta {
    case added, modified, deleted, renamed, copied, untracked
    // 注：合并冲突状态（conflicted）为 v2
    // untracked 仅用于 GitChange（working tree 状态）和 workingDiff 场景
    // commit diff（GitCommitFile/GitFileDiff）中不会出现 untracked
}

struct GitFileDiff {
    let path: String
    let oldPath: String?
    let delta: GitDelta
    let patches: [GitPatch]
    // untracked 文件：patch header 为 @@ -0,0 +1,N @@，oldLineNo 全部 nil
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

// 用于 Changes 区域：staged 和 unstaged 各自独立列表
// 同一文件可同时出现在两个列表，delta 可能不同（如 staged=modified, unstaged=deleted）
struct GitChange: Identifiable {
    let id: String          // "\(isStaged ? "s" : "u"):\(path)"（保证唯一）
    let path: String
    let delta: GitDelta
    let isStaged: Bool
}
```

---

## GitRepository（libgit2 Swift Actor）

```swift
// macos/Sources/GitKit/GitRepository.swift
actor GitRepository {
    // 初始化：传入 working directory，自动 discover git root
    // 非 git repo 时 throw GitError.notARepository
    init(path: String) throws

    // 仓库状态
    func currentBranch() throws -> String?
    func status() throws -> [GitChange]   // staged + unstaged，同一文件可各出现一次

    // 提交历史
    // v1 固定加载前 100 条，不支持翻页（v2 加 offset 参数）
    func log(maxCount: Int = 100) throws -> [GitCommit]
    func fileLog(path: String, maxCount: Int = 50) throws -> [GitCommit]

    // Diff
    func commitDiff(oid: String) throws -> [GitCommitFile]
    func fileDiff(oid: String, path: String) throws -> GitFileDiff
    // staged=true → index vs HEAD；staged=false → workdir vs index
    // untracked 文件（staged=false）返回全文件内容作为 added 行，oldLineNo 全部 nil
    func workingDiff(path: String, staged: Bool) throws -> GitFileDiff

    // 操作
    func stage(paths: [String]) throws
    func unstage(paths: [String]) throws
    func discard(paths: [String]) throws          // 丢弃工作区变更，恢复到 index 状态
    func restoreToCommit(path: String, oid: String) throws
}
```

---

## GitPanelViewModel

```swift
// macos/Sources/Features/Workspace/GitPanel/GitPanelViewModel.swift
@MainActor
class GitPanelViewModel: ObservableObject {
    // 状态栏数据（替代 GitRepoStatus）
    @Published var branch: String?
    // changedCount 为 computed property，不单独 @Published，避免与列表不同步
    var changedCount: Int { stagedFiles.count + unstagedFiles.count }

    // Changes 区
    @Published var stagedFiles: [GitChange] = []
    @Published var unstagedFiles: [GitChange] = []

    // Commits 区
    @Published var commits: [GitCommit] = []
    @Published var expandedCommits: Set<String> = []
    @Published var commitFiles: [String: [GitCommitFile]] = [:]  // oid → files

    // Diff 显示
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
    func selectCommitFile(_ file: GitCommitFile, oid: String) async
    func selectWorkingFile(_ change: GitChange) async
}
```

**变更监听**：`GitPanelViewModel` 内部持有 DispatchSource，监听 `.git/HEAD` 和 `.git/index` 文件变更事件。变更触发时：
```swift
// DispatchSource 事件 → Task bridge 到 actor 上下文
Task { [weak self] in
    await self?.refresh()
}
```

---

## FileHistoryViewModel

`FileHistorySheet` 有独立的轻量 ViewModel，通过共享同一个 `GitRepository` 实例（从 `GitPanelViewModel` 传入）获取数据：

```swift
@MainActor
class FileHistoryViewModel: ObservableObject {
    @Published var commits: [GitCommit] = []
    @Published var selectedCommit: GitCommit?
    @Published var selectedDiff: GitFileDiff?
    @Published var isLoading = false

    init(path: String, repo: GitRepository)

    func load() async
    func selectCommit(_ commit: GitCommit) async
    func restoreToSelected() async throws
}
```

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

点击文件后主内容区右侧显示 DiffView（与现有 FileBrowser 预览面板布局一致）。

### DiffView（结构化渲染）

```
src/Foo.swift  ·  abc1234 · Add feature X
─────────────────────────────────────────
 12   │   │ func oldMethod() {
 13   │ - │     return nil              ← 红底
      │ + │     return value            ← 绿底
 14   │   │ }
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

`FileHistorySheet` 通过 `FileBrowserPanel` 传入共享的 `GitRepository` 实例构建 `FileHistoryViewModel`。

---

## 文件结构

```
macos/
├── vendor/
│   └── libgit2/
│       ├── include/
│       └── lib/libgit2.a
└── Sources/
    ├── GitKit/                          # libgit2 Swift wrapper
    │   ├── GitRepository.swift
    │   ├── GitModels.swift
    │   └── GitError.swift
    └── Features/
        └── Workspace/
            ├── GitPanel/
            │   ├── GitPanelView.swift
            │   ├── GitPanelViewModel.swift
            │   ├── GitChangesSection.swift
            │   ├── GitCommitsSection.swift
            │   ├── GitCommitRow.swift
            │   ├── FileHistorySheet.swift
            │   └── FileHistoryViewModel.swift
            └── FileBrowser/
                ├── DiffView.swift       # 重写（结构化，基于 GitFileDiff）
                └── FileNodeRow.swift    # 扩展右键菜单
```

---

## 错误处理

- libgit2 错误通过 `GitError` enum 统一包装（含 libgit2 error code 和 message）
- ViewModel 捕获后写入 `@Published var error: String?`
- 非 git repo 时 Git tab 显示 "Not a git repository" 占位
- 操作失败（discard/restore）弹 Alert 提示

---

## 测试策略

- `GitRepository` 方法用临时 git repo（`mktemp -d` + `git init`）做集成测试
- ViewModel 用 mock `GitRepository` protocol 做单元测试
- UI 层不测，依赖手动验证
