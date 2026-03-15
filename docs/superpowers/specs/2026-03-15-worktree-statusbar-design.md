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

`isCurrent` is set during `refresh()` by comparing each worktree's `path` against the monitor's own `rootDir` (stored as a property, expanded via `URL(fileURLWithPath:).standardized.path`). Both sides are normalized before comparison to handle trailing slashes and symlinks. The monitor's `rootDir` — the workspace's `rootDirExpanded` — is the definition of "current"; live shell cwd is not tracked.

**Temporary workspace edge case:** If `workspaceId` refers to a temporary workspace (`isTemporary == true`), the status bar worktree area is hidden. The monitor is still created (avoids special-casing init), but `isGitRepo` will be `false` for `"~"` in typical setups.

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
    private func setupWatching()         // sets up dual-watch strategy (see below)
    private func stopWatching()          // cancels all active DispatchSources
}
```

**Lifecycle:** Created in `TerminalController.windowDidLoad` **before** the `TerminalViewContainer` closure (see Integration Points). `stopWatching()` called in `deinit`.

**`updateRootDir` contract:** Calls `stopWatching()`, clears state, re-runs git detection, calls `setupWatching()`. Not called in the current implementation (workspace switching creates a new `TerminalController` with fresh `init`). Reserved for a future workspace-rootDir-editing feature.

**Git root detection:** Run `/usr/bin/git rev-parse --show-toplevel` as a `Process` in `rootDir`. Exit non-zero → `isGitRepo = false`, no watching. Subprocess environment: `["HOME": NSHomeDirectory()]`.

**Thread safety:** `DispatchSource` event handlers fire on a background queue. All mutations of `@Published` properties happen via `DispatchQueue.main.async { }`.

### Filesystem Watching Strategy

`DispatchSource.makeFileSystemObjectSource` only fires for direct changes to the watched directory, not descendants. To correctly detect all worktree lifecycle events, a two-source strategy is used:

1. **`.git` source:** Always active (watching `<gitRoot>/.git` for `.write`). Fires when `.git/worktrees/` is first created or deleted.

2. **`.git/worktrees` source:** Active only when the directory exists. Fires when individual worktree entries are added or removed inside `.git/worktrees/`.

**File descriptor lifecycle:** Each `DispatchSource` requires an `open(2)` file descriptor. The fd is opened immediately before calling `makeFileSystemObjectSource` and closed inside the source's `setCancelHandler`. This ensures no fd leak when the source is cancelled. The `.git/worktrees` source is started and stopped dynamically; each activation opens a new fd, and cancellation closes it via the cancel handler.

`setupWatching()`:
- Always starts the `.git` source (opens fd for `.git`)
- If `<gitRoot>/.git/worktrees` exists at setup time, also starts the `.git/worktrees` source (opens fd for `.git/worktrees`)
- When the `.git` source fires and `.git/worktrees` now exists **and `worktreesSource == nil`** → open new fd, start `.git/worktrees` source; the `nil` guard prevents duplicate sources and fd leaks on rapid successive events
- When the `.git` source fires and `.git/worktrees` no longer exists **and `worktreesSource != nil`** → cancel `.git/worktrees` source (cancel handler closes its fd), set to `nil`

**Debounce:** Use a `DispatchWorkItem` stored as a property. On each source event, cancel the existing work item, create a new one that calls `refresh()`, and schedule it on `DispatchQueue.global()` after 300 ms. Storing the `DispatchWorkItem` reference and checking for nil/cancellation on the main queue before mutating state prevents races.

**`stopWatching` contract:** Cancels all active `DispatchSource`s (cancel handlers close their fds) and sets them to `nil`. Cancels any pending debounce `DispatchWorkItem`. Called in `deinit` and at the start of `updateRootDir`.

---

## Status Bar UI

New file: `macos/Sources/Features/Workspace/WorktreeStatusBarView.swift`

**Layout:** Fixed ~22 px bar at the window bottom. Embedded in `PolterttyRootView` via `VStack(spacing: 0)` with `WorktreeStatusBarView` as the final element.

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
| `isGitRepo == false` or temporary workspace | Entire worktree UI element omitted (no layout space) |
| One worktree (main only) | `⎇ branch-name`, non-interactive |
| Multiple worktrees | `⎇ branch-name`, clickable → popover |

**Popover list:**
- Each row: full relative path from repo root (e.g., `../feature-branch`) + branch name
- Main worktree: displays `.` as path label
- Current worktree: leading checkmark
- Click non-current → `onSelectWorktree(path)`, dismiss popover
- Click current → dismiss only

---

## Integration Points

### `PolterttyRootView.swift`

Add two new constructor parameters:
- `worktreeMonitor: GitWorktreeMonitor` (held as `@ObservedObject`)
- `onSelectWorktree: (String) -> Void`

`PolterttyRootView.body` is currently a `ZStack` (contains overlays like quick switcher). To add the status bar below the terminal area, wrap the entire existing `ZStack` in a `VStack(spacing: 0)` and append `WorktreeStatusBarView` after it:

```swift
var body: some View {
    VStack(spacing: 0) {
        ZStack {
            // existing body content unchanged
        }
        WorktreeStatusBarView(monitor: worktreeMonitor, onSelectWorktree: onSelectWorktree)
    }
}
```

The status bar is placed outside the `ZStack` so it is never overlaid by the terminal content.

**`worktreeMonitor` initialization ordering:** `worktreeMonitor` must be assigned **before** the `TerminalViewContainer { }` closure is constructed, because the closure captures `self` and the monitor is referenced inside it. Assigning after the closure would result in `nil` being captured.

`initialRootDir` is resolved as follows:
- If `workspaceId != nil`: look up the workspace via `WorkspaceManager.shared.workspace(for: workspaceId!)?.rootDirExpanded ?? NSHomeDirectory()`
- If `workspaceId == nil`: use `NSHomeDirectory()` — monitor will report `isGitRepo = false` and the UI will be hidden

Updated call site in `TerminalController.windowDidLoad` (~line 1145):

```swift
// Assign BEFORE TerminalViewContainer closure
let initialRootDir: String
if let wsId = self.workspaceId,
   let ws = WorkspaceManager.shared.workspace(for: wsId) {
    initialRootDir = ws.rootDirExpanded
} else {
    initialRootDir = NSHomeDirectory()
}
self.worktreeMonitor = GitWorktreeMonitor(rootDir: initialRootDir)

let container = TerminalViewContainer {
    PolterttyRootView(
        workspaceId: self.workspaceId,
        terminalView: TerminalView(ghostty: ghostty, viewModel: self, delegate: self),
        worktreeMonitor: self.worktreeMonitor!,        // NEW; non-nil guaranteed by assignment above
        onSwitchWorkspace: { [weak self] id in ... },
        onCloseWorkspace: { [weak self] id in ... },
        initialStartupMode: self.startupMode,
        onCreateFormalWorkspace: { ... },
        onCreateTemporaryWorkspace: { ... },
        onRestoreWorkspaces: { ... },
        onSelectWorktree: { [weak self] path in        // NEW
            self?.openNewTab(cdTo: path)
        }
    )
}
```

### `TerminalController.swift`

- Add `var worktreeMonitor: GitWorktreeMonitor?` stored property
- Create monitor at `windowDidLoad` (see above)
- Add `openNewTab(cdTo path: String)` instance method

```swift
func openNewTab(cdTo path: String) {
    guard let window = self.window else { return }
    var config = Ghostty.SurfaceConfiguration()
    config.workingDirectory = path
    TerminalController.newTab(ghostty, from: window, withBaseConfig: config)
}
```

`ghostty` is `internal` on `BaseTerminalController`; accessible from `TerminalController` within the same module.

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
| `/usr/bin/git` fails / not a repo | `isGitRepo = false`, worktree UI hidden, no crash |
| `git worktree list` exits non-zero | `NSLog` error, keep last known `worktrees` state |
| `.git` dir deleted while window open | DispatchSource fires → re-detect → `isGitRepo = false` → `stopWatching()` |
| Temporary workspace | Monitor created; `isGitRepo` typically `false`; UI hidden |
| `self.window` is nil in `openNewTab` | `guard` returns early, no tab opened |
