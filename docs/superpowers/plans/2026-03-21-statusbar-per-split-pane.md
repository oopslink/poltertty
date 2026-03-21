# Status Bar Per Split Pane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `BottomStatusBarView` 从窗口级改为 split pane 级，每个 pane 底部独立显示自己的 pwd/git 状态；焦点 pane 不透明，非焦点 pane opacity 0.45。

**Architecture:** 在 `TerminalSplitTreeView.swift` 内新增 `TerminalSplitLeafContainer`（private struct），持有 `@StateObject GitStatusMonitor`，通过 `.onReceive(surfaceView.$pwd)` 驱动 monitor，用 `.safeAreaInset` 在每个 leaf 底部挂载 `BottomStatusBarView`。`showStatusBar` 改为 `PolterttyRootView` 内部计算属性，通过 `@Environment` 向下传递。`TerminalController` 完全删除 `statusMonitor` 相关代码。

**Tech Stack:** Swift 5.9、SwiftUI、`@StateObject`、`@FocusedValue`、`@Environment`、`DispatchSource`（已有 `GitStatusMonitor`）

---

## 文件清单

| 文件 | 操作 |
|------|------|
| `macos/Sources/Features/Splits/TerminalSplitTreeView.swift` | 修改：新增 `TerminalSplitLeafContainer` + `ShowStatusBarKey`；`.leaf` case 改用 container |
| `macos/Sources/Features/Workspace/BottomStatusBarView.swift` | 修改：新增 `isFocused: Bool` 参数 + `.opacity` |
| `macos/Sources/Features/Workspace/PolterttyRootView.swift` | 修改：删除 `statusMonitor`/`showStatusBar` 参数；`showStatusBar` 改计算属性；删除 `focusedPwd` + `.onChange`；`terminalAreaView` 删除 status bar 块；`.terminal` HStack 追加 `.environment` |
| `macos/Sources/Features/Terminal/TerminalController.swift` | 修改：删除 `statusMonitor` 属性、`rootDir`/monitor 初始化、传参 |

**上游文件：零修改。**

---

## Task 1：给 `BottomStatusBarView` 加 `isFocused` 参数

**Files:**
- Modify: `macos/Sources/Features/Workspace/BottomStatusBarView.swift`

- [ ] **Step 1: 阅读当前文件**

```bash
cat macos/Sources/Features/Workspace/BottomStatusBarView.swift
```

- [ ] **Step 2: 新增 `isFocused` 参数并应用 opacity**

在 `BottomStatusBarView` struct 中新增 `let isFocused: Bool`，在最外层 `VStack` 的 `.font(.system(size: 11))` 后追加 `.opacity(isFocused ? 1.0 : 0.45)`。

修改后的结构：

```swift
struct BottomStatusBarView: View {
    @ObservedObject var monitor: GitStatusMonitor
    let pwd: String
    let isFocused: Bool    // 新增

    var body: some View {
        let status = monitor.status
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 6) {
                Label(abbreviatedPwd, systemImage: "folder")
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundColor(.secondary)
                Spacer()
                if status.isGitRepo {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundColor(.secondary)
                        Text(status.branch ?? "detached")
                            .foregroundColor(.primary)
                        if status.added > 0 {
                            Text("+\(status.added)")
                                .foregroundColor(.green)
                        }
                        if status.modified > 0 {
                            Text("~\(status.modified)")
                                .foregroundColor(.yellow)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        }
        .font(.system(size: 11))
        .opacity(isFocused ? 1.0 : 0.45)    // 新增
    }

    private var abbreviatedPwd: String {
        pwd.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
```

- [ ] **Step 3: 编译检查（预期报错：现有调用方未传 isFocused）**

```bash
make check 2>&1 | grep "error:" | head -20
```

预期：`PolterttyRootView.swift` 报 `missing argument for parameter 'isFocused'`——这是正常的，后续任务修复。

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Workspace/BottomStatusBarView.swift
git commit -m "feat(statusbar): 给 BottomStatusBarView 加 isFocused 参数和 opacity"
```

---

## Task 2：新增 `TerminalSplitLeafContainer` 和 `ShowStatusBarKey`

**Files:**
- Modify: `macos/Sources/Features/Splits/TerminalSplitTreeView.swift`

- [ ] **Step 1: 阅读当前文件**

```bash
cat macos/Sources/Features/Splits/TerminalSplitTreeView.swift
```

- [ ] **Step 2: 在文件末尾追加 `ShowStatusBarKey` EnvironmentKey**

在文件末尾（`TerminalSplitDropZone` 定义之后）追加：

```swift
// MARK: - ShowStatusBar Environment Key

private struct ShowStatusBarKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var showStatusBar: Bool {
        get { self[ShowStatusBarKey.self] }
        set { self[ShowStatusBarKey.self] = newValue }
    }
}
```

- [ ] **Step 3: 新增 `TerminalSplitLeafContainer` private struct**

在 `TerminalSplitLeaf` struct 定义**之前**插入：

```swift
private struct TerminalSplitLeafContainer: View {
    let surfaceView: Ghostty.SurfaceView
    let isSplit: Bool
    let action: (TerminalSplitOperation) -> Void

    @StateObject private var statusMonitor = GitStatusMonitor(pwd: "")
    @Environment(\.showStatusBar) private var showStatusBar
    @FocusedValue(\.ghosttySurfaceView) private var focusedSurface

    private var isFocused: Bool {
        // focusedSurface 为 nil 时（窗口失焦），默认视为 focused，避免所有 pane 同时变半透明
        guard let focused = focusedSurface else { return true }
        return focused === surfaceView
    }

    var body: some View {
        TerminalSplitLeaf(surfaceView: surfaceView, isSplit: isSplit, action: action)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showStatusBar {
                    BottomStatusBarView(
                        monitor: statusMonitor,
                        pwd: surfaceView.pwd ?? "",
                        isFocused: isFocused
                    )
                }
            }
            .onReceive(surfaceView.$pwd.compactMap { $0 }.removeDuplicates()) { pwd in
                statusMonitor.updatePwd(pwd)
            }
    }
}
```

> **注意：** `surfaceView.$pwd` 要求 `Ghostty.SurfaceView` 是 ObservableObject 且 `pwd` 是 `@Published`。已确认 `SurfaceView_AppKit.swift` 中 `@Published var pwd: String?`。

- [ ] **Step 4: 修改 `TerminalSplitSubtreeView` 的 `.leaf` case**

找到：

```swift
case .leaf(let leafView):
    TerminalSplitLeaf(surfaceView: leafView, isSplit: !isRoot, action: action)
```

改为：

```swift
case .leaf(let leafView):
    TerminalSplitLeafContainer(surfaceView: leafView, isSplit: !isRoot, action: action)
```

- [ ] **Step 5: 编译检查**

```bash
make check 2>&1 | grep "error:" | head -20
```

预期：`TerminalSplitTreeView.swift` 无新 error；`PolterttyRootView.swift` 仍有 `isFocused` missing argument error（待 Task 3 修复）。

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Splits/TerminalSplitTreeView.swift
git commit -m "feat(statusbar): 新增 TerminalSplitLeafContainer，per-pane status bar"
```

---

## Task 3：更新 `PolterttyRootView` — 移除旧参数，改为内部计算 + Environment 传递

**Files:**
- Modify: `macos/Sources/Features/Workspace/PolterttyRootView.swift`

- [ ] **Step 1: 确认当前调用点只有一处**

```bash
grep -n "PolterttyRootView(" macos/Sources/Features/Terminal/TerminalController.swift
```

预期：只有一处调用。

- [ ] **Step 2: 删除 `statusMonitor` 和 `showStatusBar` 属性声明**

找到并删除（约第 56-57 行）：

```swift
    let statusMonitor: GitStatusMonitor
    let showStatusBar: Bool
```

- [ ] **Step 3: 删除 `init` 中对应参数和赋值**

删除 `init` 签名中的两个参数：

```swift
        statusMonitor: GitStatusMonitor,
        showStatusBar: Bool,
```

删除 `init` body 中的赋值：

```swift
        self.statusMonitor = statusMonitor
        self.showStatusBar = showStatusBar
```

- [ ] **Step 4: 删除 `@FocusedValue(\.ghosttySurfacePwd)` 声明**

找到并删除（约第 40 行）：

```swift
    @FocusedValue(\.ghosttySurfacePwd) private var focusedPwd
```

- [ ] **Step 5: 新增 `showStatusBar` 内部计算属性**

在 `private var effectiveSidebarWidth` 计算属性之前插入：

```swift
    private var showStatusBar: Bool {
        guard let id = workspaceId,
              let ws = WorkspaceManager.shared.workspace(for: id) else { return false }
        return !ws.isTemporary
    }
```

- [ ] **Step 6: 删除 `terminalAreaView` 中的 status bar 块**

找到并删除 `terminalAreaView` 中（约第 431-437 行）：

```swift
            // Status bar 在 shell 区域正下方，与 shell 区域对齐
            if showStatusBar {
                BottomStatusBarView(
                    monitor: statusMonitor,
                    pwd: focusedPwd ?? ""
                )
            }
```

- [ ] **Step 7: 删除 `.onChange(of: focusedPwd)` 整块**

找到并删除整块（约第 261-264 行）：

```swift
                .onChange(of: focusedPwd) { newPwd in
                    // single-parameter closure, compatible with macOS 13+
                    guard let pwd = newPwd, !pwd.isEmpty else { return }
                    statusMonitor.updatePwd(pwd)
                }
```

- [ ] **Step 8: 在 `.terminal` case 的 `HStack` 上追加 `.environment`**

找到 `case .terminal:` 下的 `HStack(spacing: 0) {`，在该 HStack 的 modifier 链末尾追加（在 `.overlay` 之前或之后均可，推荐加在 `.onChange(of: manager.formalWorkspaces.count)` 前面不影响逻辑）：

实际上最简洁的方式是在整个 `.terminal` case 的顶层 view 上追加。找到：

```swift
            case .terminal:
                HStack(spacing: 0) {
```

在该 `HStack` 闭包结束的 `}` 后（紧接着的 modifier 链上）追加：

```swift
                .environment(\.showStatusBar, showStatusBar)
```

> **定位提示：** 该 HStack 结束于 `}` 后紧跟 `.overlay(alignment: .trailing) {`，在 `.overlay` 的 modifier 之后，现有 `.onChange(of: focusedPwd)` 之前追加 `.environment`。由于已删除 `.onChange(of: focusedPwd)`，直接在 `.overlay` 末尾 modifier 后追加即可。

- [ ] **Step 9: 编译检查**

```bash
make check 2>&1 | grep "error:" | head -20
```

预期：`PolterttyRootView.swift` 无 error；`TerminalController.swift` 报 `extra argument` 或 `missing argument`（传了 `statusMonitor:` 和 `showStatusBar:` 而 init 已无这两个参数）——待 Task 4 修复。

- [ ] **Step 10: Commit**

```bash
git add macos/Sources/Features/Workspace/PolterttyRootView.swift
git commit -m "refactor(statusbar): PolterttyRootView 移除 statusMonitor/showStatusBar 参数，改为内部计算 + Environment 传递"
```

---

## Task 4：更新 `TerminalController` — 移除 `statusMonitor` 相关代码

**Files:**
- Modify: `macos/Sources/Features/Terminal/TerminalController.swift`

- [ ] **Step 1: 阅读相关行**

```bash
grep -n "statusMonitor\|rootDir\|GitStatusMonitor\|showStatusBar" macos/Sources/Features/Terminal/TerminalController.swift
```

记录所有出现的行号。

- [ ] **Step 2: 删除 `statusMonitor` 属性声明**

找到并删除：

```swift
    let statusMonitor: GitStatusMonitor
```

- [ ] **Step 3: 删除 `rootDir` 变量和 monitor 初始化**

找到并整块删除（这两行专为 statusMonitor 而存在）：

```swift
        let rootDir = workspaceId
            .flatMap { WorkspaceManager.shared.workspace(for: $0) }?.rootDirExpanded
            ?? NSHomeDirectory()
        self.statusMonitor = GitStatusMonitor(pwd: rootDir)
```

- [ ] **Step 4: 删除传给 `PolterttyRootView` 的两个参数**

找到 `PolterttyRootView(` 调用处，删除：

```swift
                statusMonitor: self.statusMonitor,
                showStatusBar: showStatusBar,
```

以及计算 `showStatusBar` 的 let 声明（如果存在）：

```swift
        let showStatusBar: Bool = {
            guard let id = workspaceId,
                  let ws = WorkspaceManager.shared.workspace(for: id) else { return false }
            return !ws.isTemporary
        }()
```

- [ ] **Step 5: 确认无残留引用**

```bash
grep -n "statusMonitor\|rootDir\|showStatusBar" macos/Sources/Features/Terminal/TerminalController.swift
```

预期：无任何匹配输出。

- [ ] **Step 6: 完整编译检查**

```bash
make check 2>&1 | grep "error:"
```

预期：无任何 error 输出。

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/Features/Terminal/TerminalController.swift
git commit -m "refactor(statusbar): TerminalController 移除 statusMonitor 属性及初始化"
```

---

## Task 5：全量构建并手动验证

**Files:** 无新增/修改

- [ ] **Step 1: 全量构建**

```bash
make dev
```

预期：`BUILD SUCCEEDED`，无 warning 提升为 error。

- [ ] **Step 2: 运行并验证单 pane**

```bash
make run-dev
```

打开 App，验证：
- 单 pane 时底部有一个 status bar，不透明
- 进入 git repo 目录后显示 `⎇ branch`
- 非 git repo 时 status bar 不显示（`EmptyView`）

- [ ] **Step 3: 验证多 pane（水平分屏）**

在 Ghostty 中水平分屏（`Cmd+D` 或右键 → Split Right）：
- 两个 pane 各有独立 status bar
- 焦点 pane status bar 不透明，另一个半透明
- 切换焦点后透明度随之变化
- 两个 pane 分别 `cd` 到不同目录，各自显示自己的 pwd 和 git 状态

- [ ] **Step 4: 验证窗口失焦**

切换到其他 App，验证：
- 多 pane 时所有 status bar 保持不透明（不变暗）

- [ ] **Step 5: 验证临时 Workspace**

创建临时 Workspace，验证：
- status bar 不显示（`showStatusBar = false`）

- [ ] **Step 6: 最终 commit**

```bash
git add -A
git status  # 确认无意外改动
git commit -m "feat(statusbar): status bar 从窗口级改为 split pane 级

每个 split pane 底部独立显示 pwd/git 状态。
焦点 pane 不透明，非焦点 pane opacity 0.45。
窗口失焦时所有 pane 保持不透明。"
```

---

## Task 6：创建 Pull Request

- [ ] **Step 1: 推送分支**

```bash
git push -u origin HEAD
```

- [ ] **Step 2: 创建 PR**

```bash
gh pr create \
  --title "feat(statusbar): status bar 从窗口级改为 split pane 级" \
  --body "$(cat <<'EOF'
## Summary

- 每个 split pane 底部独立显示自己的 pwd/git 状态（`TerminalSplitLeafContainer` + `@StateObject GitStatusMonitor`）
- 焦点 pane status bar 不透明（opacity 1.0），非焦点 pane 半透明（opacity 0.45）
- 窗口失焦时所有 pane 保持不透明（`focusedSurface == nil` fallback 为 `true`）
- `showStatusBar` 改为 `PolterttyRootView` 内部计算属性，通过 `@Environment` 向下传递
- 上游文件零修改

## Test plan

- [ ] 单 pane：底部有 status bar，进入 git repo 显示分支，非 git repo 不显示
- [ ] 水平/垂直分屏：各 pane 独立 status bar，各自显示自己的 pwd/git
- [ ] 焦点切换：焦点 pane 不透明，其余半透明
- [ ] 窗口失焦：所有 pane status bar 保持不透明
- [ ] 临时 Workspace：status bar 不显示

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## 参考文档

- Spec: `docs/superpowers/specs/2026-03-21-statusbar-per-split-pane-design.md`
- Build rules: `docs/build-rules.md`（`make dev` 增量构建；构建失败时 `make dev-clean`）
- Workspace rules: `docs/workspace-rules.md`
