# Workspace 从 Git 仓库克隆创建

**日期**: 2026-04-12
**状态**: 已批准
**范围**: 在 New Workspace 表单中新增「从 Git 仓库克隆」创建模式，与「空目录」「从快照」并列为三种创建来源

---

## 背景

当前 `WorkspaceCreateForm` 支持两种创建方式：
1. 空目录（默认）— 用户指定 `rootDir` 作为新 workspace 根目录
2. 从快照恢复 — 通过 `Toggle("Create from snapshot")` 切换，从已有 workspace 的快照拉起

实际工作流中，许多新项目从 `git clone` 开始：clone 一个仓库到本地，然后立即把它当作 workspace 打开。当前必须先在终端执行 `git clone`，再回到 Poltertty 手动新建 workspace 并指向 clone 后的目录。两步操作能合并为一步。

---

## 设计决策

| 问题 | 决策 |
|------|------|
| 目标目录指定方式 | A — 用户选父目录，自动用 repo 名作为子目录 |
| Clone 执行时机 | A — 表单内同步执行，成功后才创建 workspace |
| 认证策略 | A — 完全依赖系统 git 配置，零认证逻辑 |
| Clone 选项暴露 | C — URL + Branch + Shallow clone 复选框 |
| UI 形态 | A — 顶部 Segmented Picker 三选一，替换现有 Toggle |
| 取消 / 失败清理 | A1 + B1 + C1 — 取消和失败都自动清理，预检查目标路径冲突 |
| Name 联动 | A — URL 变化时自动填 Name，用户手改后不再覆盖 |
| Git 二进制 | A — 写死 `/usr/bin/git`，与现有 `GitWorktreeMonitor` 一致 |

---

## 架构

新增功能挂在现有 `WorkspaceCreateForm` 上，**不引入新窗口、新页面或新 WorkspaceManager 方法**。三个代码单元：

### 1. `GitCloner.swift`（新文件）

位置：`macos/Sources/Features/Workspace/GitCloner.swift`

纯逻辑模块，封装 git clone 子进程。**不依赖 SwiftUI、不依赖 `WorkspaceManager`**，便于单元测试。

```swift
final class GitCloner {
    enum CloneError: LocalizedError {
        case invalidURL
        case cannotExtractRepoName
        case targetExists(path: String)
        case parentNotWritable(path: String)
        case gitFailed(exitCode: Int32, stderr: String)
        case cancelled
    }

    struct Options {
        let url: String
        let parentDir: String        // 已展开 ~ 的绝对路径
        let branch: String?          // nil = 默认分支
        let shallow: Bool            // true = --depth 1
    }

    /// 从 URL 提取仓库名（去掉 .git 后缀）。
    /// 支持 https://host/foo/bar.git, git@host:foo/bar.git, ssh://...
    static func extractRepoName(from url: String) -> String?

    /// 当前是否正在 clone
    private(set) var isRunning: Bool

    /// 启动 clone。回调在主线程触发。
    /// onProgress: 每次 git stderr 有新行时调用（git 把进度写到 stderr）
    /// onComplete: 成功时携带 clone 出来的最终绝对路径
    func start(
        options: Options,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, CloneError>) -> Void
    )

    /// 中止当前 clone：SIGTERM → 250ms 宽限 → SIGKILL，然后清理目标目录。
    /// onComplete 会以 .failure(.cancelled) 触发。
    func cancel()
}
```

**预检顺序**（在 `start()` 内同步完成）：
1. URL 非空且能 `extractRepoName` → 否则 `.invalidURL` / `.cannotExtractRepoName`
2. `parentDir` 展开 `~` 后存在且可写 → 否则 `.parentNotWritable`
3. 拼出 `targetPath = parentDir/repoName`，若已存在 → `.targetExists`
4. 全部通过后启动 `Process`

**子进程管理**：
- `executableURL = /usr/bin/git`
- 参数：`["clone", "--progress", url, targetPath]`，可选 `["-b", branch]`，可选 `["--depth", "1"]`
- `environment` 注入 `HOME`、`PATH`（含 `/usr/bin:/bin:/usr/local/bin`）、`GIT_TERMINAL_PROMPT=0`（防止 git 弹交互式认证提示导致进程挂死）
- `standardError` 接 `Pipe`，用 `readabilityHandler` 异步读取行，回调到主线程
- `terminationHandler` 触发 `onComplete`

**清理逻辑**：失败、取消、或 `terminationHandler` 看到非零退出码时，删除 `targetPath` 整个子目录。**只删 `targetPath` 本身，不动 `parentDir`**——这是关键的安全边界。

### 2. `WorkspaceCreateForm.swift`（修改）

#### 新增枚举

```swift
enum WorkspaceCreateSource: String, CaseIterable, Identifiable {
    case empty       // 当前默认行为
    case snapshot    // 替换现有 createFromSnapshot Toggle
    case git         // 新增

    var id: String { rawValue }
    var label: String {
        switch self {
        case .empty: return "Empty"
        case .snapshot: return "From Snapshot"
        case .git: return "From Git"
        }
    }
}
```

#### State 变更

- 新增 `@State private var source: WorkspaceCreateSource = .empty`
- 移除 `@State private var createFromSnapshot: Bool`，所有引用改为 `source == .snapshot`
- 新增 git 模式字段：
  - `@State private var gitURL: String = ""`
  - `@State private var gitParentDir: String = "~"`
  - `@State private var gitBranch: String = ""`
  - `@State private var gitShallow: Bool = false`
- 新增联动追踪：`@State private var nameWasManuallyEdited: Bool = false`
- 新增 clone 执行态：
  - `@State private var isCloning: Bool = false`
  - `@State private var cloneProgress: String = ""`（最近一行 stderr）
  - `@StateObject private var cloner = GitClonerHolder()`（轻量持有者，避免 `GitCloner` 直接进 SwiftUI 状态）

#### 布局变更

表单顶部 Title 下方插入 Segmented Picker：

```swift
Picker("", selection: $source) {
    ForEach(WorkspaceCreateSource.allCases) { src in
        Text(src.label).tag(src)
    }
}
.pickerStyle(.segmented)
.padding(.horizontal, 24)
.padding(.bottom, 12)
.disabled(isCloning)
```

字段区域根据 `source` 切换：
- `.empty` — Name + Description + Root Directory + Color（与现状一致）
- `.snapshot` — Name + Description + Root Directory + Color + Source Workspace Picker + Snapshot Picker（保留现有逻辑，移除 Toggle）
- `.git` — Name + Description + **Git URL** + **Parent Directory** + **Branch (optional)** + **Shallow checkbox** + Color

`.git` 模式下 Root Directory 字段被 Parent Directory 替代（仅 placeholder 与 label 文案不同，实质都是 `Browse...` 选目录）。

#### Name 联动

```swift
.onChange(of: gitURL) { newURL in
    guard source == .git, !nameWasManuallyEdited else { return }
    if let repoName = GitCloner.extractRepoName(from: newURL) {
        name = repoName
    }
}
.onChange(of: name) { _ in
    errorMessage = nil
    if source == .git { nameWasManuallyEdited = true }
}
```

注意 `.onChange(of: name)` 已存在，扩展现有 closure 而不是新增第二个。

切换 `source` 时重置 `nameWasManuallyEdited = false`，让用户切回 git 模式时联动重新生效。

#### Create 按钮行为

```swift
Button(buttonTitle) {
    handleSubmit()
}
.disabled(submitDisabled)
```

- `buttonTitle`：编辑时 `"Save"`；非编辑时根据 `isCloning` 显示 `"Cloning…"` 或 `"Create"`
- `submitDisabled`：`name.isEmpty || isCloning || (source == .git && gitURL.isEmpty)`
- 编辑模式（`editing != nil`）下 Picker 隐藏，`source` 永远是 `.empty`，行为完全不变

#### Cancel 按钮行为

- `isCloning == false` 时：原行为，`onCancel()`
- `isCloning == true` 时：变成 `"Cancel Clone"`，调用 `cloner.inner.cancel()`，**不关闭表单**，让用户看到错误后可重试

#### `handleSubmit()` 分派

```swift
private func handleSubmit() {
    // 名称校验（所有模式共用）
    let existingNames = manager.workspaces
        .filter { $0.id != editing?.id }
        .map { $0.name }
    if let error = WorkspaceNameValidator.validate(name, existingNames: existingNames) {
        showError(error)
        return
    }
    errorMessage = nil

    switch source {
    case .empty, .snapshot:
        // 现有逻辑（snapshot 分支已经在 onSubmit 调用前预填 rootDir）
        finalizeCreate(rootDir: rootDir)
    case .git:
        startClone()
    }
}

private func startClone() {
    let parent = (gitParentDir as NSString).expandingTildeInPath
    let opts = GitCloner.Options(
        url: gitURL.trimmingCharacters(in: .whitespaces),
        parentDir: parent,
        branch: gitBranch.isEmpty ? nil : gitBranch,
        shallow: gitShallow
    )
    isCloning = true
    cloneProgress = ""
    cloner.inner.start(
        options: opts,
        onProgress: { line in cloneProgress = line },
        onComplete: { result in
            isCloning = false
            switch result {
            case .success(let path):
                finalizeCreate(rootDir: path)
            case .failure(let err):
                showError(err.errorDescription ?? "Clone failed")
            }
        }
    )
}

private func finalizeCreate(rootDir: String) {
    onSubmit(name, rootDir, selectedColor, description)
}
```

注意：`onSubmit` 是表单的现有出参，由 `WorkspaceCreateForm` 的调用方（`PolterttyRootView` 等）转调 `WorkspaceManager.create(...)`。**`WorkspaceManager` 完全无需修改**。

#### 进度显示

`isCloning == true` 时，在 Cancel/Create 按钮上方插入一行小字进度：

```swift
if isCloning {
    HStack(spacing: 8) {
        ProgressView().scaleEffect(0.6)
        Text(cloneProgress.isEmpty ? "Cloning…" : cloneProgress)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }
    .padding(.horizontal, 24)
    .padding(.bottom, 8)
}
```

### 3. `WorkspaceManager.swift`

**无改动**。`create(name:rootDir:colorHex:description:)` 完全够用，clone 出来的最终路径作为普通 `rootDir` 传入。

---

## 数据流

```
用户填表 → 点 Create
   ↓
handleSubmit()
   ↓
[name 校验] —— 失败 → 红字 + shake，停留
   ↓
source == .git ?
   ├─ 否 → finalizeCreate(rootDir) → onSubmit → WorkspaceManager.create → 关闭表单
   └─ 是 → startClone()
            ↓
       GitCloner.start
            ├─ 预检失败 → onComplete(.failure) → showError，停留可重试
            └─ 启动 git 子进程
                  ↓
            stderr 行流 → onProgress → cloneProgress 更新（小字）
                  ↓
            进程退出
              ├─ 0  → onComplete(.success(targetPath))
              │         → finalizeCreate(targetPath)
              │         → onSubmit → WorkspaceManager.create → 关闭表单
              └─ ≠0 → 删除 targetPath → onComplete(.failure(.gitFailed))
                        → showError，停留可重试
```

取消路径：用户点 Cancel Clone → `cloner.cancel()` → `Process.terminate()` → 250ms → 若仍存活 `kill(pid, SIGKILL)` → terminationHandler 触发 → 删除 targetPath → `onComplete(.failure(.cancelled))` → showError("Cancelled")

---

## 错误处理

| 场景 | 表现 |
|------|------|
| URL 为空 | Create 按钮 disabled |
| URL 格式无法提取 repo 名 | 红字「Cannot determine repository name from URL」+ shake |
| Parent dir 不存在或不可写 | 红字「Parent directory is not writable」 |
| Target dir 已存在 | 红字「Target already exists: /path/to/repo」 |
| Git 认证失败 / 网络错误 / repo 不存在 | 红字显示 git stderr 末尾内容（截断到合理长度），目标目录已自动清理 |
| 用户取消 | 红字「Clone cancelled」，目标目录已清理 |
| Name 校验失败 | 沿用现有 shake + 红字 |

错误发生后表单**不关闭**，用户可调整字段后重新点 Create。`isCloning` 重置为 false，`errorMessage` 清空在用户下次输入时由现有 `.onChange(of: name)` 触发。

---

## 测试策略

### 单元测试 — `GitClonerTests.swift`（新文件）

`GitCloner` 是项目里少见的可纯单元测试模块（无 SwiftUI、无 manager 依赖）。重点覆盖：

1. **`extractRepoName` 表驱动测试**：
   - `https://github.com/foo/bar.git` → `bar`
   - `https://github.com/foo/bar` → `bar`
   - `git@github.com:foo/bar.git` → `bar`
   - `ssh://git@host:22/foo/bar.git` → `bar`
   - `https://host/foo/bar/` → `bar`（trailing slash）
   - `""` → `nil`
   - `"not a url"` → `nil`（或返回 `"not a url"`，根据实现选定）

2. **预检失败用例**（不实际调用 git，构造一个临时父目录）：
   - 父目录不存在 → `.parentNotWritable`
   - 父目录存在但无写权限 → `.parentNotWritable`
   - 目标子目录已存在 → `.targetExists`

3. **取消语义**：用一个本地 bare repo（`tmp/.git`）作为 URL，启动 clone 后立即 cancel，断言：
   - `onComplete` 以 `.failure(.cancelled)` 触发
   - 目标目录不存在（清理生效）

4. **成功路径**：用本地 bare repo 测一次完整 clone，断言 `onComplete` 携带正确路径，且 `targetPath` 是合法 git 工作树（存在 `.git`）。

### 手工测试清单

构建运行后在 UI 里验证：

- [ ] 表单顶部三段 Picker 切换正常，字段区域跟随刷新
- [ ] `.empty` 模式行为与之前完全一致（回归）
- [ ] `.snapshot` 模式行为与之前完全一致（回归）— 重点：原 Toggle 已移除，从快照管理面板「从此创建」入口仍能预选并跳到 snapshot tab
- [ ] `.git` 模式输入公开仓库 URL（如 `https://github.com/octocat/Hello-World.git`），点 Create
  - [ ] Name 字段自动填 `Hello-World`
  - [ ] 进度小字滚动显示 git 输出
  - [ ] 成功后表单关闭，新 workspace 出现在侧边栏，rootDir 指向 clone 出的目录
- [ ] 输入 URL 后手改 Name，再改 URL，Name 不再被覆盖
- [ ] 输入私有仓库 URL，本地 SSH key 已配置 → 成功
- [ ] 输入不存在的仓库 URL → 红字错误，目标目录不存在，可改 URL 重试
- [ ] 输入大仓库，Clone 进行中点 Cancel Clone → 表单留住，错误显示 cancelled，目标目录不存在
- [ ] 父目录选一个已经包含同名子目录的位置 → 提交时立即报「Target already exists」，不启动 git
- [ ] 勾选 Shallow，clone 后目标目录的 `.git/shallow` 文件存在
- [ ] 填 Branch = 某个非默认分支，clone 后 `git -C target rev-parse --abbrev-ref HEAD` 等于该分支
- [ ] 编辑现有 workspace 时 Picker 隐藏，无法切到 git 模式
- [ ] Clone 进行中关闭整个 Poltertty 主窗口 / app 退出 → git 子进程被清理（验证 Activity Monitor）

---

## 安全与边界

1. **目录清理只动 `targetPath`**：`GitCloner` 内部记录启动时拼出的 `targetPath`，清理函数只 `removeItem(atPath: targetPath)`，绝不递归删除 `parentDir` 或其它兄弟目录。即便预检通过后用户在外部把 `targetPath` 替换成软链接，删除的也只是软链接本身（用 `removeItem` 而非 `trashItem` 即可）。
2. **`GIT_TERMINAL_PROMPT=0`**：必须设置，否则 git 在私有仓库认证失败时会卡在 prompt 上等用户输入，子进程永不退出，cancel 也只能强杀。
3. **stderr 行流编码**：用 `String(data:encoding:.utf8)`，遇到不可解码字节直接丢弃该行（避免崩溃）。
4. **进程生命周期**：`GitCloner.cancel()` 必须能在 `WorkspaceCreateForm` 被销毁时调用——表单 `.onDisappear` 里若 `isCloning` 则 `cloner.inner.cancel()`，避免悬挂子进程。
5. **不存任何凭据**：URL 字段就是 URL 字段，不做密码字段化处理，不做 keychain 集成。用户如果在 URL 里塞了 `https://user:token@host/...`，那是用户自己的选择。

---

## 范围之外（YAGNI）

- 不支持 clone 到非 Poltertty workspace 目录的「只 clone 不创建 workspace」模式
- 不支持 GUI 选 SSH key / 输入密码 / OAuth 流程
- 不支持 `git ls-remote` 探测远程默认分支
- 不支持 submodule 递归 clone（默认行为，用户需要时自己 `git submodule update`）
- 不支持 mirror / bare clone
- 不支持 clone 完成后自动跑 `npm install` / 任何项目初始化脚本
- 不支持后台 clone 与多 workspace 并发 clone（一次只能克隆一个）
- 不支持 clone 进度条解析为百分比（直接显示 git stderr 最近一行即可）

---

## 实现顺序（供后续 plan 参考）

1. 新建 `GitCloner.swift` 与 `GitClonerTests.swift`，先把纯逻辑跑通
2. 修改 `WorkspaceCreateForm.swift`：引入 `WorkspaceCreateSource` 枚举，把现有 `createFromSnapshot` 重构为 `source == .snapshot`，验证 empty / snapshot 回归
3. 在表单内加 `.git` 模式字段与 Picker UI
4. 接入 `GitCloner`，实现 `startClone` / 进度显示 / 取消 / 错误流程
5. 加 `.onDisappear` 兜底取消
6. 跑手工测试清单
