# Git Worktree Status Bar — Design Spec

**Date:** 2026-03-15
**Status:** Approved

## Overview

Add a bottom status bar to each Poltertty terminal window that displays the current git worktree/branch, and lets the user navigate to other worktrees of the same repository by opening a new terminal tab.

## Goals

- Surface git worktree context directly in the terminal window UI
- Enable one-click navigation to sibling worktrees via a new tab
- Keep the workspace sidebar unchanged
- Auto-update when worktrees are added or removed (filesystem watch)

## Out of Scope

- Dirty/staged status indicators
- Fetch, pull, or other git operations from the UI
- Multi-monitor layout differences
- Collapsed sidebar mode changes
- Workspace rootDir editing (updateRootDir is reserved for this future feature)

---

## Data Model

```swift
struct GitWorktree: Identifiable, Equatable {
    let id: UUID
    let path: String      // absolute path to the worktree
    let branch: String?   // nil when HEAD is detached
    let isMain: Bool      // true for the primary worktree
    let isCurrent: Bool   // true when this worktree is the monitor's rootDir
}
```

`isCurrent` is set during `refresh()` by comparing each worktree's `path` against the monitor's own stored `rootDir`, both normalized via `URL(fileURLWithPath:).standardized.path` to handle trailing slashes and symlinks.

---

## GitWorktreeMonitor

New file: `macos/Sources/Features/Workspace/GitWorktreeMonitor.swift`

```swift
class GitWorktreeMonitor: ObservableObject {
    @Published var worktrees: [GitWorktree] = []
    @Published var isGitRepo: Bool = false

    init(rootDir: String)
    func updateRootDir(_ path: String)   // reserved for future rootDir-editing feature
    private func refresh()
    private func setupWatching()
    private func stopWatching()
}
```

**Lifecycle:** `GitWorktreeMonitor` is always created (non-optional). Created in `TerminalController.windowDidLoad` before the `TerminalViewContainer` closure. `stopWatching()` called in `deinit`.

**`updateRootDir` contract:** Calls `stopWatching()`, clears state, re-runs git detection, calls `setupWatching()`. Not called in the current implementation. Reserved for a future workspace-rootDir-editing feature.

**Git root detection:** Run `/usr/bin/git rev-parse --show-toplevel` as a `Process` in `rootDir`. Exit non-zero → `isGitRepo = false`, no watching. Subprocess environment: `["HOME": NSHomeDirectory()]`.

**Thread safety:** `DispatchSource` event handlers fire on a background queue. All mutations of `@Published` properties happen via `DispatchQueue.main.async { }`.

### Filesystem Watching Strategy

`DispatchSource.makeFileSystemObjectSource` only fires for direct changes to the watched directory, not descendants. A two-source strategy detects all worktree lifecycle events:

1. **`.git` source:** Always active (watching `<gitRoot>/.git` for `.write`). Fires when `.git/worktrees/` is first created or deleted.

2. **`.git/worktrees` source:** Active only when the directory exists. Fires when individual worktree entries are added or removed inside `.git/worktrees/`.

**File descriptor lifecycle:** Each `DispatchSource` requires an `open(2)` fd. Open the fd immediately before `makeFileSystemObjectSource`; close it inside the source's `setCancelHandler`. The `.git/worktrees` source is started/stopped dynamically — each activation opens a new fd, cancellation closes it via the cancel handler.

`setupWatching()`:
- Always starts the `.git` source (opens fd for `.git`)
- If `<gitRoot>/.git/worktrees` exists at setup time, also starts the `.git/worktrees` source
- When `.git` source fires and `.git/worktrees` now exists **and `worktreesSource == nil`** → open fd, start `.git/worktrees` source (nil guard prevents duplicate sources on rapid events)
- When `.git` source fires and `.git/worktrees` no longer exists **and `worktreesSource != nil`** → cancel `.git/worktrees` source (cancel handler closes fd), set to `nil`

**Debounce:** Stored `DispatchWorkItem` property. On each source event: cancel existing work item, create new one calling `refresh()`, schedule on `DispatchQueue.global()` after 300 ms.

**`stopWatching` contract:** Cancel all active `DispatchSource`s (cancel handlers close fds), set to `nil`. Cancel pending `DispatchWorkItem`. Called in `deinit` and at start of `updateRootDir`.

---

## Status Bar UI

New file: `macos/Sources/Features/Workspace/WorktreeStatusBarView.swift`

**Layout:** Fixed ~22 px bar at the window bottom. Embedded in `PolterttyRootView` via `.safeAreaInset(edge: .bottom)` on the existing `ZStack` body. This preserves the ZStack's full-height overlay semantics (e.g., the quick-switcher backdrop's `.ignoresSafeArea()`) while pushing the terminal content up by the bar height:

```swift
var body: some View {
    ZStack {
        // existing body content unchanged
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
        if showWorktreeBar {
            WorktreeStatusBarView(monitor: worktreeMonitor, onSelectWorktree: onSelectWorktree)
        }
    }
}
```

`showWorktreeBar` is a computed property on `PolterttyRootView`: `!isTemporaryWorkspace`. `isTemporaryWorkspace` is resolved by looking up `workspaceId` in `WorkspaceManager.shared` and checking `isTemporary`; defaults to `false` if no workspace found. The `isGitRepo` check is handled inside `WorktreeStatusBarView` — if `isGitRepo == false`, the view renders nothing (zero height).

```
┌──────────────────────────────────────────────┐
│  [sidebar]   [terminal content area]         │
├──────────────────────────────────────────────┤
│  ⎇ feature/worktree-ui                       │
└──────────────────────────────────────────────┘
```

**States:**

| Condition | Display |
|-----------|---------|
| `isTemporary` workspace | `WorktreeStatusBarView` not rendered (zero height, no layout space) |
| `isGitRepo == false` | View renders nothing (zero height) |
| One worktree (main only) | `⎇ branch-name`, non-interactive |
| Multiple worktrees | `⎇ branch-name`, clickable → popover |

**Popover list:**
- Each row: full relative path from repo root + branch name
- Main worktree: displays `.` as path label
- Current worktree: leading checkmark
- Click non-current → `onSelectWorktree(path)`, dismiss popover
- Click current → dismiss only

---

## Integration Points

### `PolterttyRootView.swift`

Add three new constructor parameters:
- `worktreeMonitor: GitWorktreeMonitor` (non-optional, held as `@ObservedObject`)
- `isTemporaryWorkspace: Bool`
- `onSelectWorktree: (String) -> Void`

Replace the body's outermost view with `.safeAreaInset` as shown above.

`isTemporaryWorkspace` is computed in `TerminalController` at call site:
```swift
let isTemporary = workspaceId.flatMap { WorkspaceManager.shared.workspace(for: $0) }?.isTemporary ?? false
```

### `TerminalController.swift`

- Add `let worktreeMonitor: GitWorktreeMonitor` (non-optional `let` stored property)

**Initialization placement:** Swift requires `let` stored properties on subclasses to be assigned before `super.init`. `workspaceId` is already set before `super.init` at line 71, so initialize `worktreeMonitor` there:

```swift
// In TerminalController.init, after `self.workspaceId = workspaceId`, before `super.init`
let rootDir = workspaceId
    .flatMap { WorkspaceManager.shared.workspace(for: $0) }?.rootDirExpanded
    ?? NSHomeDirectory()
self.worktreeMonitor = GitWorktreeMonitor(rootDir: rootDir)
```

**`windowDidLoad` call site:** In `windowDidLoad`, compute `isTemporary` and pass the already-initialized `worktreeMonitor` to `PolterttyRootView`. Full updated call (all 12 parameters):

```swift
let isTemporary = workspaceId
    .flatMap { WorkspaceManager.shared.workspace(for: $0) }?.isTemporary ?? false

let container = TerminalViewContainer {
    PolterttyRootView(
        workspaceId: self.workspaceId,
        terminalView: TerminalView(ghostty: ghostty, viewModel: self, delegate: self),
        worktreeMonitor: self.worktreeMonitor,          // NEW (non-optional)
        isTemporaryWorkspace: isTemporary,               // NEW
        onSwitchWorkspace: { [weak self] id in
            self?.switchToWorkspace(id)
        },
        onCloseWorkspace: { [weak self] id in
            self?.closeWorkspace(id)
        },
        initialStartupMode: self.startupMode,
        onCreateFormalWorkspace: { [weak self] name, rootDir, colorHex, description in
            self?.createFormalWorkspace(name: name, rootDir: rootDir, colorHex: colorHex, description: description)
        },
        onCreateTemporaryWorkspace: { [weak self] in
            self?.createTemporaryWorkspace()
        },
        onRestoreWorkspaces: { [weak self] ids in
            guard let self = self else { return }
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.restoreWorkspaces(ids, replacingWindow: self.window)
            }
        },
        onCreateTemporary: { [weak self] in              // existing 9th param; unchanged
            self?.createTemporaryWorkspace()
        },
        onSelectWorktree: { [weak self] path in          // NEW (10th param)
            self?.openNewTab(cdTo: path)
        }
    )
}
```

- Add `openNewTab(cdTo path: String)` instance method:

```swift
func openNewTab(cdTo path: String) {
    guard let window = self.window else { return }
    var config = Ghostty.SurfaceConfiguration()
    config.workingDirectory = path
    _ = TerminalController.newTab(ghostty, from: window, withBaseConfig: config)
}
```

`TerminalController.newTab` at line 410 already sets `controller.workspaceId = parentController.workspaceId`, so the new tab inherits the current workspace automatically. No extra propagation needed.

`ghostty` is `internal` on `BaseTerminalController`, accessible from `TerminalController` in the same module. Return value discarded (`_ =`).

### New Files

Both in `macos/Sources/Features/Workspace/` per workspace-rules.md:
- `GitWorktreeMonitor.swift`
- `WorktreeStatusBarView.swift`

### Unchanged

`WorkspaceManager.swift`, `WorkspaceSidebar.swift`

---

## Error Handling

| Scenario | Behavior |
|----------|----------|
| `/usr/bin/git` fails / not a repo | `isGitRepo = false`, worktree UI renders nothing, no crash |
| `git worktree list` exits non-zero | `NSLog` error, keep last known `worktrees` state |
| `.git` dir deleted while window open | DispatchSource fires → re-detect → `isGitRepo = false` → `stopWatching()` |
| Temporary workspace | `showWorktreeBar = false`; monitor created with `NSHomeDirectory()` but view not rendered |
| `self.window` nil in `openNewTab` | `guard` returns early, no tab opened |
