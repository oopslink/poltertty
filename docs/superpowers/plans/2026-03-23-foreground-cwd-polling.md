# Foreground CWD Polling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 当 AgentSession 活跃时，每 2s 轮询前台子进程 CWD，CWD 变化时更新 status bar，使 Claude Code 切换 worktree 后 status bar 实时跟进。

**Architecture:** `ProcessTreeCwd` 从 `shellPid` 遍历进程树找最深叶子进程取 CWD；`GitStatusMonitor` 在 `shellPid != 0` 时运行 2s 定时器，检测到变化则调现有 `updatePwd()`；`TerminalSplitLeafContainer` 订阅 `AgentSessionManager.$sessions` 将 `shellPid` 注入 per-surface monitor。

**Tech Stack:** Swift, Darwin (`proc_pidinfo`, `proc_listallpids`), `DispatchSourceTimer`, SwiftUI `onReceive`

**Spec:** `docs/superpowers/specs/2026-03-23-foreground-cwd-polling-design.md`

---

## 文件结构

| 文件 | 操作 | 职责 |
|------|------|------|
| `macos/Sources/Features/Terminal/ProcessTreeCwd.swift` | 新建 | 进程树遍历，返回最前台子进程 CWD |
| `macos/Sources/Features/Workspace/GitStatusMonitor.swift` | 修改 | 加 `shellPid` 属性 + 2s 轮询 timer |
| `macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift` | 修改 1 行 | `AgentSession` 初始化补传 `shellPid` |
| `macos/Sources/Features/Splits/TerminalSplitTreeView.swift` | 修改 | `onReceive($sessions)` 注入 `shellPid` |
| `macos/Ghostty.xcodeproj/project.pbxproj` | 修改 | 将新文件加入编译 target |

---

### Task 1：修复 shellPid 未赋值

**Files:**
- Modify: `macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift`（约第 191 行）

- [ ] **Step 1：找到 `AgentSession(...)` 初始化，补传 `shellPid`**

定位 `handlePrepareSession()` 中创建 `AgentSession` 的代码块（`id:`, `surfaceId:`, `definition:`, `workspaceId:`, `cwd:` 五个参数），加一行：

```swift
let agentSession = AgentSession(
    id: UUID(),
    surfaceId: surfaceUUID,
    definition: definition,
    workspaceId: workspaceUUID,
    cwd: req.cwd,
    shellPid: req.pid   // ← 新增
)
```

- [ ] **Step 2：编译验证**

```bash
cd /Users/aaronlin/works/codes/oss/poltertty
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -destination 'platform=macOS' build 2>&1 | tail -5
```

期望：`BUILD SUCCEEDED`

- [ ] **Step 3：提交**

```bash
git add macos/Sources/Features/Agent/CtrlServer/CtrlServer.swift
git commit -m "fix: populate AgentSession.shellPid from prepare-session request"
```

---

### Task 2：新建 ProcessTreeCwd 工具

**Files:**
- Create: `macos/Sources/Features/Terminal/ProcessTreeCwd.swift`

- [ ] **Step 1：创建文件**

```swift
// macos/Sources/Features/Terminal/ProcessTreeCwd.swift
import Foundation
import Darwin

/// 给定 shellPid，遍历进程树找到最前台子进程的 CWD。
/// 用于在 OSC 7 不可用时（如 Claude Code 运行期间）更新 status bar。
///
/// 算法：BFS 收集 shellPid 后代 → 找叶子节点（无子进程）
/// → 多叶子取最晚启动的（近似最前台，Claude Code 单进程场景完全准确）
/// → proc_pidinfo(PROC_PIDVNODEPATHINFO) 取 CWD
enum ProcessTreeCwd {

    /// 返回 shellPid 后代中最前台进程的 CWD。
    /// shellPid = 0 → nil；无后代 → fallback 到 shellPid 自身 CWD。
    static func foregroundCwd(shellPid: pid_t) -> String? {
        guard shellPid > 0 else { return nil }

        // ── 1. 拿到所有 PID ──────────────────────────────────────────────
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64) // 多分配防竞态
        let actual = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard actual > 0 else { return nil }

        // ── 2. 构建父→子映射，收集 shellPid 后代（BFS）────────────────────
        var childrenOf: [pid_t: [pid_t]] = [:]
        for i in 0..<Int(actual) {
            let pid = pids[i]
            guard pid > 0 else { continue }
            var info = proc_bsdshortinfo()
            let ret = proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0,
                                   &info, Int32(MemoryLayout<proc_bsdshortinfo>.size))
            guard ret > 0 else { continue }   // ESRCH / EPERM → 跳过
            childrenOf[pid_t(info.pbsi_ppid), default: []].append(pid)
        }

        var descendants: Set<pid_t> = []
        var bfsQueue = childrenOf[shellPid] ?? []
        var head = 0
        while head < bfsQueue.count {
            let pid = bfsQueue[head]; head += 1
            descendants.insert(pid)
            if let children = childrenOf[pid] { bfsQueue.append(contentsOf: children) }
        }

        // ── 3. 找叶子（无子进程的后代）──────────────────────────────────
        let leaves = descendants.filter { childrenOf[$0] == nil || childrenOf[$0]!.isEmpty }

        // ── 4. 确定目标进程 ────────────────────────────────────────────
        let targetPid: pid_t
        if leaves.isEmpty {
            targetPid = shellPid          // fallback：后代已全部退出
        } else if leaves.count == 1 {
            targetPid = leaves.first!
        } else {
            // 多叶子：取 pbi_start_tvsec 最大的（最晚启动 ≈ 最前台）
            targetPid = leaves.max { startTime(of: $0) < startTime(of: $1) } ?? leaves.first!
        }

        // ── 5. 取 CWD ───────────────────────────────────────────────────
        return cwd(of: targetPid) ?? (targetPid != shellPid ? cwd(of: shellPid) : nil)
    }

    // MARK: - Helpers

    private static func startTime(of pid: pid_t) -> UInt64 {
        var info = proc_bsdinfo()
        let ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0,
                               &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        return ret > 0 ? info.pbi_start_tvsec : 0
    }

    private static func cwd(of pid: pid_t) -> String? {
        var pathInfo = proc_vnodepathinfo()
        let ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0,
                               &pathInfo, Int32(MemoryLayout<proc_vnodepathinfo>.size))
        guard ret > 0 else { return nil }
        // vip_path 是 C 固定长度数组，Swift 导入为元组，用 withUnsafeBytes 安全访问
        let s = withUnsafeBytes(of: pathInfo.pvi_cdir.vip_path) { rawBuf in
            rawBuf.withMemoryRebound(to: CChar.self) { buf in
                String(cString: buf.baseAddress!)
            }
        }
        return s.isEmpty ? nil : s
    }
}
```

- [ ] **Step 2：将文件加入 Xcode 编译 target**

在 Xcode 中：右键 `Features/Terminal` group → "Add Files to Ghostty…" → 选择 `ProcessTreeCwd.swift` → 确认勾选 `Ghostty` target。

若使用命令行操作 `.pbxproj`，在 `Features/Terminal/` 对应的 `PBXGroup` 里添加 `PBXFileReference` 和 `PBXBuildFile`，并加入 `Sources` build phase。

- [ ] **Step 3：冒烟验证（临时代码，用完删除）**

在任意 Swift 文件（如 `AppDelegate.swift`）的 `applicationDidFinishLaunching` 里临时加一行：

```swift
NSLog("[ProcessTreeCwd] self cwd: \(ProcessTreeCwd.foregroundCwd(shellPid: getpid()) ?? "nil")")
```

启动 app，Console 里应打印当前进程工作目录，验证 API 可用。

- [ ] **Step 4：删除临时代码**

- [ ] **Step 5：编译验证**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -destination 'platform=macOS' build 2>&1 | tail -5
```

期望：`BUILD SUCCEEDED`

- [ ] **Step 6：提交**

```bash
git add macos/Sources/Features/Terminal/ProcessTreeCwd.swift
git add macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "feat: add ProcessTreeCwd utility for foreground subprocess CWD detection"
```

---

### Task 3：GitStatusMonitor 加轮询

**Files:**
- Modify: `macos/Sources/Features/Workspace/GitStatusMonitor.swift`

> **⚠️ Spec 偏差说明**：spec 要求在 `stopWatching()` 里调 `stopPwdPolling()`。**不要这样做。**
> 原因：`updatePwd()` 每次 CWD 变化都会调 `stopWatching()`，若 `stopWatching()` 同时停掉 poll timer，第一次 CWD 变化后轮询就永久停止了。poll timer 应独立于 FS watcher 的生命周期。

- [ ] **Step 1：在私有属性区（`debounceWork` 后）加三个新字段**

```swift
// MARK: - Foreground process polling
// shellPid 必须在 MainActor 上赋值（来自 SwiftUI onReceive）。
// timer 操作全部派发到 queue，确保线程安全。
var shellPid: pid_t = 0 {
    didSet {
        guard shellPid != oldValue else { return }
        let pid = shellPid
        queue.async { [weak self] in
            guard let self else { return }
            if pid == 0 { self.stopPwdPolling() } else { self.startPwdPolling(pid: pid) }
        }
    }
}
private var pwdPollTimer: DispatchSourceTimer?  // accessed only on queue
private var pollingPid: pid_t = 0              // queue 侧的 shellPid 副本
```

- [ ] **Step 2：在 `stopWatching()` 之后加两个 polling 方法**

```swift
// MARK: - Polling（在 queue 上执行）

private func startPwdPolling(pid: pid_t) {
    stopPwdPolling()
    pollingPid = pid
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + 2.0, repeating: 2.0, leeway: .milliseconds(200))
    timer.setEventHandler { [weak self] in
        guard let self, self.pollingPid > 0 else { return }
        guard let newCwd = ProcessTreeCwd.foregroundCwd(shellPid: self.pollingPid),
              newCwd != self.currentPwd else { return }
        self.updatePwd(newCwd)
    }
    pwdPollTimer = timer
    timer.resume()
}

private func stopPwdPolling() {
    pwdPollTimer?.cancel()
    pwdPollTimer = nil
    pollingPid = 0
}
```

- [ ] **Step 3：在 `deinit` 里加 timer cancel**

在现有的 `deinit` 末尾加一行：

```swift
deinit {
    headSource?.cancel()
    indexSource?.cancel()
    debounceWork?.cancel()
    pwdPollTimer?.cancel()   // ← 新增
}
```

- [ ] **Step 4：编译验证**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -destination 'platform=macOS' build 2>&1 | tail -5
```

期望：`BUILD SUCCEEDED`

- [ ] **Step 5：提交**

```bash
git add macos/Sources/Features/Workspace/GitStatusMonitor.swift
git commit -m "feat: add 2s foreground CWD polling to GitStatusMonitor"
```

---

### Task 4：TerminalSplitLeafContainer 注入 shellPid

**Files:**
- Modify: `macos/Sources/Features/Splits/TerminalSplitTreeView.swift`（约第 133 行）

- [ ] **Step 1：在现有 `onReceive(surfaceView.$pwd...)` 之后加新的 onReceive**

当前代码（约 133-135 行）：

```swift
.onReceive(surfaceView.$pwd.compactMap { $0 }.removeDuplicates()) { pwd in
    statusMonitor.updatePwd(pwd)
}
```

在其后紧接着加：

```swift
.onReceive(AgentService.shared.sessionManager.$sessions) { sessions in
    // AgentService 是 @MainActor，SwiftUI onReceive 也在 MainActor 执行，直接访问合法
    // sessions 的 key 就是 surfaceId（[UUID: AgentSession]），直接下标 O(1)
    let pid = sessions[surfaceView.id]?.shellPid ?? 0
    statusMonitor.shellPid = pid_t(pid)
}
```

- [ ] **Step 2：编译验证**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -destination 'platform=macOS' build 2>&1 | tail -5
```

期望：`BUILD SUCCEEDED`

- [ ] **Step 3：提交**

```bash
git add macos/Sources/Features/Splits/TerminalSplitTreeView.swift
git commit -m "feat: subscribe to AgentSession changes to drive CWD polling in GitStatusMonitor"
```

---

### Task 5：集成验证

- [ ] **Step 1：启动 Poltertty，打开一个 workspace**

- [ ] **Step 2：在终端里启动 Claude Code**

`prepare-session` 请求触发，`AgentSession.shellPid` 应被设为 Claude Code 的 shell PID（非零）。

验证方式：在 `startPwdPolling(pid:)` 里临时加 `NSLog("[Poll] start pid=\(pid)")` 确认 timer 启动。

- [ ] **Step 3：让 Claude Code 切换 worktree**

例如 "请切换到 .worktrees/fix/worktree-support 工作"，Claude Code 执行 cd 后，最多 2s 内 status bar 的 branch 显示应切换到对应分支。

- [ ] **Step 4：验证退出后轮询停止**

退出 Claude Code，确认 `NSLog("[Poll] start ...")` 不再出现（session 移除 → `shellPid = 0` → `stopPwdPolling()`）。

- [ ] **Step 5：验证 split pane 隔离**

打开两个 split pane，在 pane A 启动 Claude Code，仅 pane A 的 status bar 应跟随变化，pane B 不受影响。

- [ ] **Step 6：删除临时 NSLog，最终提交**

```bash
git add -u
git commit -m "feat: foreground CWD polling - status bar follows Claude Code worktree switches"
```
