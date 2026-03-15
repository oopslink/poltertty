# Git Worktree Status Bar — Design Spec

**Date:** 2026-03-15
**Status:** Approved

## Overview

Add a bottom status bar to each Poltertty terminal window that displays the current git worktree/branch, and lets the user navigate to other worktrees of the same repository by opening a new terminal tab.

## Goals

- Surface git worktree context directly in the terminal window UI
- Enable one-click navigation to sibling worktrees via a new tab
- Keep the workspace sidebar unchanged (no sub-items added)
- Auto-update when worktrees are added or removed (filesystem watch)

## Out of Scope

- Dirty/staged status indicators
- Fetch, pull, or other git operations from the UI
- Multi-monitor layout differences
- Collapsed sidebar mode changes

---

## Data Model

```swift
struct GitWorktree: Identifiable, Equatable {
    let id: UUID          // locally generated for SwiftUI identity
    let path: String      // absolute path to the worktree
    let branch: String?   // current branch name; nil when HEAD is detached
    let isMain: Bool      // true for the primary worktree
    let isCurrent: Bool   // true when this worktree matches the active terminal's cwd
}
```

Parsed from `git worktree list --porcelain` output. `isCurrent` is determined by comparing `path` to the terminal's current working directory (or the workspace `rootDir` as a proxy).

---

## GitWorktreeMonitor

New file: `macos/Sources/Features/Workspace/GitWorktreeMonitor.swift`

```swift
class GitWorktreeMonitor: ObservableObject {
    @Published var worktrees: [GitWorktree] = []
    @Published var isGitRepo: Bool = false

    init(rootDir: String)
    func updateRootDir(_ path: String)   // called when workspace switches
    private func refresh()               // shells out: git worktree list --porcelain
    private func startWatching()         // DispatchSource on <gitRoot>/.git/worktrees
    private func stopWatching()
}
```

**Lifecycle:** One instance per `TerminalController` (one per window). Created during controller init, destroyed when the window closes.

**Git root detection:** Run `git rev-parse --show-toplevel` in `rootDir` to find the repo root. If it fails, `isGitRepo = false` and no watching is set up.

**Filesystem watching:** Watch `<gitRoot>/.git/worktrees` for `write` events using `DispatchSource.makeFileSystemObjectSource`. If the directory does not exist (repo has no linked worktrees), skip watching and only run the initial `refresh()`. Re-evaluate watch setup whenever `updateRootDir` is called.

**Refresh debounce:** Coalesce rapid filesystem events with a 300 ms debounce before re-running `git worktree list`.

---

## Status Bar UI

New file: `macos/Sources/Features/Workspace/WorktreeStatusBarView.swift`

**Layout:** Fixed-height bar (~22 px) at the bottom of the window, below the terminal content area. Embedded in `PolterttyRootView` via a `VStack` with the status bar as the last element.

```
┌──────────────────────────────────────────────┐
│  [sidebar]   [terminal content area]         │
├──────────────────────────────────────────────┤
│  ⎇ feature/worktree-ui          [other items]│
└──────────────────────────────────────────────┘
```

**States:**

| Condition | Display |
|-----------|---------|
| Not a git repo | Status bar worktree area hidden (or "—" in muted color) |
| Git repo, no extra worktrees | `⎇ branch-name`, non-interactive |
| Git repo with linked worktrees | `⎇ branch-name`, clickable → popover |

**Popover list:**

- Each row: short relative path from repo root + branch name
- Current worktree row: highlighted (checkmark or bold)
- Clicking a non-current row calls `TerminalController.openNewTab(cdTo: path)`
- Popover dismisses after selection

---

## Integration Points

| File | Change |
|------|--------|
| `PolterttyRootView.swift` | Wrap existing content in `VStack`, append `WorktreeStatusBarView` at bottom; pass monitor instance |
| `TerminalController.swift` | Instantiate `GitWorktreeMonitor(rootDir:)` during `init`; add `openNewTab(cdTo path: String)` method; call `monitor.updateRootDir` when active workspace changes |
| `GitWorktreeMonitor.swift` | **New** — service class |
| `WorktreeStatusBarView.swift` | **New** — SwiftUI status bar view |
| `WorkspaceManager.swift` | No changes |
| `WorkspaceSidebar.swift` | No changes |

---

## openNewTab Implementation

```swift
func openNewTab(cdTo path: String) {
    // Reuse existing new-tab logic from Ghostty upstream
    // Pass `path` as the initial working directory for the new tab's shell
}
```

The exact mechanism depends on Ghostty's surface/tab creation API. If the API accepts an initial working directory, prefer that. Otherwise, send `cd <path>\n` to the new tab's PTY after creation.

---

## Error Handling

- `git` not found or not a repo → `isGitRepo = false`, no UI shown, no crash
- `git worktree list` fails (e.g., permission error) → log to stderr, keep last known state
- Watched directory deleted (all linked worktrees removed) → stop watch source, clear linked worktrees, keep main worktree entry
