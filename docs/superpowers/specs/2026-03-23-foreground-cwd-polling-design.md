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

### 1. ProcessTreeCwd（新建工具）

**职责**：给定 shellPid，返回当前最前台子进程的 CWD。

**算法**：
1. `proc_listallpids` 获取所有系统进程
2. 对每个 pid，`proc_pidinfo(PROC_PIDT_SHORTBSDINFO)` 取 ppid，构建后代集合
3. 从后代中找叶子节点（无子进程）
4. 多个叶子时取 `pbi_start_tvsec` 最大的（最晚启动）
5. `proc_pidinfo(pid, PROC_PIDVNODEPATHINFO)` 取叶子进程 CWD
6. 无后代时 fallback 到 shellPid 自身 CWD

**边界处理**：
- 进程已退出（ESRCH / `proc_pidinfo` 返回 ≤ 0）→ 跳过
- shellPid = 0 → 返回 nil（不轮询）

**文件**：`macos/Sources/Features/Terminal/ProcessTreeCwd.swift`

### 2. GitStatusMonitor（修改）

**新增属性**：
```swift
var shellPid: pid_t = 0 {
    didSet {
        guard shellPid != oldValue else { return }
        shellPid == 0 ? stopPwdPolling() : startPwdPolling()
    }
}
private var pwdPollTimer: DispatchSourceTimer?
```

**新增方法**：
- `startPwdPolling()`：在现有 `queue` 上创建 2s `DispatchSourceTimer`，重复触发
- `stopPwdPolling()`：cancel timer，置 nil
- 每次触发：调 `ProcessTreeCwd.foregroundCwd(shellPid:)`，结果与 `currentPwd` 不同时调 `updatePwd()`

**修改 `stopWatching()`**：补充调 `stopPwdPolling()`。

**文件**：`macos/Sources/Features/Workspace/GitStatusMonitor.swift`

### 3. TerminalSplitTreeView（修改）

通过已有的 `@EnvironmentObject` 拿到 `AgentSessionManager`，监听 `sessions` 变化，将对应 surface 的 `shellPid` 注入 `GitStatusMonitor`：

```swift
.onChange(of: agentSessionManager.sessions) { _ in
    let pid = agentSessionManager.sessions.values
        .first { $0.surfaceId == surfaceView.id }?.shellPid ?? 0
    statusMonitor.shellPid = pid_t(pid)
}
```

- Agent 启动 → shellPid 注入 → 轮询开始
- Agent 退出 → shellPid 清零 → 轮询停止

**文件**：`macos/Sources/Features/Splits/TerminalSplitTreeView.swift`

## 数据流

```
AgentSession.shellPid
    ↓ (onChange in TerminalSplitTreeView)
GitStatusMonitor.shellPid
    ↓ (2s DispatchSourceTimer on queue)
ProcessTreeCwd.foregroundCwd(shellPid)
    ↓ (若 cwd 变化)
GitStatusMonitor.updatePwd(newCwd)
    ↓ (已有链路)
detectAndSetup() → git status refresh → @Published
    ↓
BottomStatusBarView 刷新
```

## 性能

- 轮询频率：2s
- 仅在 `shellPid != 0` 时轮询（有 agent 运行才开启）
- `proc_listallpids` 开销：典型系统 ~300 进程，每 2s 一次，可忽略
- 不影响无 agent 的普通终端使用

## 不变的部分

- OSC 7 路径完全保留（shell 正常 cd 仍走原路，即时更新）
- 轮询与 OSC 7 互补，不冲突（updatePwd 有路径去重）
- GitStatusMonitor 的 FS watching 逻辑不变
