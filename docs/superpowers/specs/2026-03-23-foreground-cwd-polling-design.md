# Foreground Process CWD Polling for Status Bar

**Date**: 2026-03-23
**Status**: Approved
**Branch**: fix/worktree-support

## 问题

Claude Code 在终端内部切换 worktree（`chdir()` 改变自身进程 CWD）时，status bar 不更新。原因：status bar 的 pwd 来源是 OSC 7（shell integration），而 shell 的 `precmd` hook 只在 shell prompt 出现时触发——Claude Code 运行期间不会触发。

## 目标

在不依赖 OSC 7 的情况下，让 status bar 能感知终端内子进程的 CWD 变化，延迟 ≤ 2s。

## 范围

- 仅影响有 `AgentSession` 运行的 surface（没有 agent 时零开销）
- 多 split pane 独立工作，互不干扰
- 不修改 Ghostty C 核

## 方案概述

在 `GitStatusMonitor`（per-surface，已负责 pwd → git status 刷新）里加 2s 定时轮询。轮询时遍历 `shellPid` 的子进程树，找到最前台的进程并取其 CWD，若发生变化则调现有 `updatePwd()` 触发完整刷新链。

## 组件设计

### 1. AgentSession（修改）

**问题**：`shellPid` 字段声明为 `var shellPid: Int32 = 0`，但在 `prepare-session` 时从未赋值——`req.pid` 只传给了 `HookSessionStore`，没有传给 `AgentSession`。

**修改**：在 `CtrlServer.handlePrepareSession()` 创建 `AgentSession` 时补充传入 `pid`：

```swift
let agentSession = AgentSession(
    id: UUID(),
    surfaceId: surfaceUUID,
    definition: definition,
    workspaceId: workspaceUUID,
    cwd: req.cwd,
    shellPid: req.pid   // 新增
)
```

`AgentSession` 的 `shellPid` 字段已声明，无需修改 struct 本身。

**文件**：`macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift`

---

### 2. ProcessTreeCwd（新建工具）

**职责**：给定 `shellPid`，返回当前最前台子进程的 CWD。

**算法**：
1. `proc_listallpids(nil, 0)` 获取进程总数，再分配 buffer 调一次获取所有 PID
2. 对每个 pid，`proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, ...)` 取 `pbsi_ppid`，构建 shellPid 后代集合（BFS）
3. 从后代中找叶子节点（在集合中无子进程的 pid）
4. 多个叶子时取 `proc_pidinfo(pid, PROC_PIDTBSDINFO, ...)` 的 `pbi_start_tvsec` 最大者（近似最前台；对 Claude Code 单进程场景完全准确，管道场景为近似值）
5. `proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, ...)` 取叶子进程 CWD
6. 无后代（Claude Code 已退出）→ fallback 到 shellPid 自身 CWD

**边界处理**：
- `proc_pidinfo` 返回 ≤ 0（ESRCH / EPERM）→ 跳过该进程；沙盒环境下跨 UID 进程会静默跳过，属正常行为
- `shellPid = 0` → 直接返回 nil，不做任何系统调用

**局限性说明**：用最晚启动叶子进程作为"前台进程"代理，在 shell 管道（`cmd1 | cmd2`）下不保证精确，但对 Claude Code 长进程场景完全准确。

**文件**：`macos/Sources/Features/Terminal/ProcessTreeCwd.swift`

---

### 3. GitStatusMonitor（修改）

**新增属性**（setter 必须在 MainActor 上调用，通过 `queue.async` 派发到后台队列确保线程安全）：

```swift
// Must be called on MainActor (from SwiftUI View's onReceive)
// 私有存储变量，实际 timer 操作全部派发到 queue
var shellPid: pid_t = 0 {
    didSet {
        guard shellPid != oldValue else { return }
        let pid = shellPid
        queue.async { [weak self] in
            guard let self else { return }
            pid == 0 ? self.stopPwdPolling() : self.startPwdPolling(pid: pid)
        }
    }
}
private var pwdPollTimer: DispatchSourceTimer?
```

**新增方法**（均在 `queue` 上执行）：
- `startPwdPolling(pid:)`：创建 2s `DispatchSourceTimer`（`DispatchSource.makeTimerSource(queue: queue)`），重复触发
- `stopPwdPolling()`：cancel timer，置 nil
- Timer handler：调 `ProcessTreeCwd.foregroundCwd(shellPid: pid)`，结果非 nil 且与 `currentPwd` 不同时调 `updatePwd(newCwd)`

**修改 `stopWatching()`**：补充调 `stopPwdPolling()`（已有此方法，加一行即可）。

**文件**：`macos/Sources/Features/Workspace/GitStatusMonitor.swift`

---

### 4. TerminalSplitLeafContainer（修改）

`TerminalSplitLeafContainer` 不走 `@EnvironmentObject` 注入（现有代码无此路径）。改为通过 `AgentService.shared.sessionManager` 单例直接订阅 `$sessions` publisher。

`AgentService` 是 `@MainActor` 类，SwiftUI View 本身也在 MainActor 上，直接访问合法，无需额外 `Task` 包装：

```swift
// AgentService 是 @MainActor，从 SwiftUI View 直接访问合法
.onReceive(AgentService.shared.sessionManager.$sessions) { sessions in
    let pid = sessions.values
        .first { $0.surfaceId == surfaceView.id }?.shellPid ?? 0
    statusMonitor.shellPid = pid_t(pid)  // 在 MainActor 上调用，符合 shellPid setter 约束
}
```

- Agent 启动（`prepare-session` 注册 session）→ `$sessions` 发布 → shellPid 注入 → 轮询开始
- Agent 退出（session 移除）→ `$sessions` 发布 → shellPid 清零 → 轮询停止

**文件**：`macos/Sources/Features/Splits/TerminalSplitTreeView.swift`

---

## 数据流

```
prepare-session (req.pid)
    ↓
AgentSession.shellPid = req.pid
    ↓
AgentSessionManager.$sessions 发布
    ↓ (onReceive in TerminalSplitLeafContainer)
GitStatusMonitor.shellPid = pid  [主线程 setter]
    ↓ (queue.async)
startPwdPolling(pid)  [queue]
    ↓ (2s DispatchSourceTimer)
ProcessTreeCwd.foregroundCwd(shellPid)  [queue]
    ↓ (若 cwd 变化)
GitStatusMonitor.updatePwd(newCwd)  [queue]
    ↓ (已有链路)
detectAndSetup() → git status refresh → @Published
    ↓
BottomStatusBarView 刷新
```

## 性能

- 轮询频率：2s，仅在 `shellPid != 0` 时活跃
- `proc_listallpids`：典型系统 ~300 进程，每 2s 一次，开销可忽略
- OSC 7 路径完全保留，两条路径互补不冲突（轮询侧有 `currentPwd` 去重，避免冗余 git 查询）
- 无 agent 运行时零开销

## 改动文件汇总

| 文件 | 改动类型 | 说明 |
|------|----------|------|
| `CtrlServer.swift` | 修改 1 行 | `AgentSession` 初始化补传 `shellPid: req.pid` |
| `ProcessTreeCwd.swift` | 新建 | 进程树 CWD 检测工具 |
| `GitStatusMonitor.swift` | 修改 | 加 `shellPid` 属性 + 2s 轮询 timer |
| `TerminalSplitTreeView.swift` | 修改 | `onReceive($sessions)` 注入 shellPid |
| `Ghostty.xcodeproj` | 修改 | 将 `ProcessTreeCwd.swift` 加入编译 target |
