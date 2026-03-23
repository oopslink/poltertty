# Git Worktree Support — Design Spec

**Date:** 2026-03-23
**Status:** Approved
**Replaces:** 2026-03-15-worktree-statusbar-design.md (deprecated)

## Overview

Add comprehensive git worktree support to Poltertty: sidebar navigation/management + status bar awareness. Worktrees appear as collapsible children under their parent workspace in the sidebar, enabling users to navigate, create, and delete worktrees from the UI.

## Goals

- **Awareness:** Visual indicator in the bottom status bar when working in a linked worktree
- **Navigation:** Switch to sibling worktrees via sidebar (new tab or new window)
- **Management:** Create and delete worktrees from the UI (list is automatic)

## Out of Scope

- Modifying `WorkspaceModel` or `WorkspaceManager` — worktree is a git-level concept
- Git operations beyond worktree add/remove (no fetch, pull, merge, etc.)
- Worktree lock/unlock, move, repair
- Branch rename from worktree UI

---

## Data Model

```swift
struct GitWorktree: Identifiable, Equatable {
    let id: UUID
    let path: String        // absolute path to the worktree
    let branch: String?     // nil when HEAD is detached
    let isMain: Bool        // true for the primary worktree
    let isCurrent: Bool     // true when this worktree matches the monitor's rootDir
}
```

`isCurrent` is determined during `refresh()` by comparing each worktree's `path` against the monitor's `rootDir`, both normalized via `URL(fileURLWithPath:).standardized.path`.

---

## GitWorktreeMonitor

New file: `macos/Sources/Features/Workspace/GitWorktreeMonitor.swift`

```swift
class GitWorktreeMonitor: ObservableObject {
    @Published var worktrees: [GitWorktree] = []
    @Published var isGitRepo: Bool = false

    init(rootDir: String)
    func addWorktree(branch: String, path: String, baseBranch: String?, createNew: Bool) throws
    func removeWorktree(path: String, force: Bool) throws
    private func refresh()
    private func setupWatching()
    private func stopWatching()
}
```

### Lifecycle

- Owned by `TerminalController` as a `let` stored property (non-optional)
- Initialized before `super.init()`:
  ```swift
  let rootDir = workspaceId
      .flatMap { WorkspaceManager.shared.workspace(for: $0) }?.rootDirExpanded
      ?? NSHomeDirectory()
  self.worktreeMonitor = GitWorktreeMonitor(rootDir: rootDir)
  ```
- `stopWatching()` called in `deinit`

### Git Root Resolution

Run `/usr/bin/git rev-parse --show-toplevel` as a `Process` in `rootDir`. Non-zero exit → `isGitRepo = false`, no watching. Subprocess environment: `["HOME": NSHomeDirectory()]`.

**Linked worktree handling:** If `rootDir` is inside a linked worktree (where `.git` is a file, not a directory), `--show-toplevel` still returns the linked worktree's root. To find the main repo's `.git` directory for filesystem watching, additionally run `git rev-parse --git-common-dir` and resolve it to an absolute path. The filesystem watchers always operate on this resolved `.git` directory (which is the main worktree's `.git`), regardless of whether the monitor was initialized from a main or linked worktree.

### Worktree Listing

Run `git worktree list --porcelain` and parse output. Blocks are separated by blank lines. Each block starts with `worktree <path>`:

```
worktree /path/to/main
HEAD abc123
branch refs/heads/main

worktree /path/to/.worktrees/feature-auth
HEAD def456
branch refs/heads/feature/auth

worktree /path/to/.worktrees/detached-work
HEAD 789abc
detached
```

**Parsing rules:**
- `worktree <path>` → absolute path; first block is always the main worktree (`isMain = true`)
- `branch refs/heads/<name>` → extract `<name>` as `branch`
- `detached` (no value) → `branch = nil`
- `bare` → skip (bare worktrees not supported in UI)

### Branch Listing

`func listBranches() -> [String]` — runs `git branch -a --format='%(refname:short)'`. Used by `WorktreeCreateForm` when loading the branch picker. Excludes branches that already have a worktree (by comparing against `self.worktrees`).

### Filesystem Watching Strategy

`DispatchSource.makeFileSystemObjectSource` — two-source strategy:

1. **`.git` source:** Always active, watches `<gitRoot>/.git` for `.write`. Fires when `.git/worktrees/` is created or deleted.
2. **`.git/worktrees` source:** Active only when directory exists. Fires when worktree entries are added/removed.

File descriptor lifecycle: `open(2)` fd before `makeFileSystemObjectSource`; close in `setCancelHandler`. The `.git/worktrees` source is started/stopped dynamically.

`setupWatching()`:
- Always starts `.git` source
- If `.git/worktrees` exists, also starts `.git/worktrees` source
- `.git` source fires + `.git/worktrees` now exists + `worktreesSource == nil` → start `.git/worktrees` source
- `.git` source fires + `.git/worktrees` gone + `worktreesSource != nil` → cancel `.git/worktrees` source

**Debounce:** `DispatchWorkItem` property. On each event: cancel existing, create new calling `refresh()`, schedule on `DispatchQueue.global()` after 300ms.

**Thread safety:** Source event handlers fire on background queue. All `@Published` mutations via `DispatchQueue.main.async { }`.

### Worktree Operations

**`addWorktree(branch:path:baseBranch:createNew:)`:**
- Executes `git worktree add [-b <branch>] <path> [baseBranch]`
- `-b` flag used when `createNew == true`
- On success: `refresh()` auto-triggered by filesystem watcher
- On failure: throws error with git stderr message

**`removeWorktree(path:force:)`:**
- Executes `git worktree remove <path>` (add `--force` when `force == true`)
- On success: `refresh()` auto-triggered
- On failure: throws error with git stderr message

---

## Sidebar Integration

### Expanded Mode

New file: `macos/Sources/Features/Workspace/WorktreeListView.swift`

Embedded below the **current workspace's** `ExpandedWorkspaceItem` only. Other workspaces in the sidebar do not show worktree children (each window has its own `GitWorktreeMonitor` for its own workspace; showing worktrees for non-current workspaces would require additional monitors with no clear benefit).

- **Visibility:** Only shown when `worktrees.count > 1` (single worktree = main only, nothing to show)
- **Collapse control:** ▶/▼ button on the workspace row; defaults to expanded
- **Collapsed state:** Workspace row shows worktree count badge (e.g., `3 worktrees`)
- **Expanded state:** Indented list of worktree rows, each showing `⎇ branch-name`; current worktree marked with ✓
- **Footer:** `+ Add Worktree` button at bottom of expanded list

**Worktree row interactions:**

| Action | Behavior |
|--------|----------|
| Single click | Open new tab in current window, cd to worktree path |
| Double click | Open new window, cd to worktree path |
| Right-click | Context menu: Open in New Tab / Open in New Window / Delete Worktree |

**Delete Worktree** is disabled for the main worktree and the current worktree.

### Collapsed Mode

- `CollapsedWorkspaceIcon` unchanged visually — no space for worktree children
- Right-click context menu gains a `Worktrees` submenu listing all worktrees with the same actions (Open in New Tab / Open in New Window / Delete)

### Data Flow

`GitWorktreeMonitor` is owned by `TerminalController`, passed to `PolterttyRootView` and then to `WorkspaceSidebar` via constructor parameter. Sidebar only renders and triggers callbacks; actual operations are handled by `TerminalController`.

**New callbacks on `WorkspaceSidebar`:**

```swift
let onOpenWorktreeInTab: (String) -> Void      // path → open new tab with cd
let onOpenWorktreeInWindow: (String) -> Void    // path → open new window with cd
let onCreateWorktree: (String, String, String?, Bool) -> Void  // branch, path, baseBranch, createNew
let onDeleteWorktree: (String, Bool) -> Void    // path, force
```

**Tab/window behavior:**
- `openNewTab(cdTo:)`: Creates a new tab in the current window via `TerminalController.newTab(ghostty, from: window, withBaseConfig: config)`. The new tab inherits `workspaceId` from the parent controller automatically (existing behavior at line 410).
- `openNewWindow(cdTo:)`: Creates a new `TerminalController` with the same `workspaceId`, sets `config.workingDirectory = path`, and shows the window.

---

## Create Worktree Form

New file: `macos/Sources/Features/Workspace/WorktreeCreateForm.swift`

Triggered by `+ Add Worktree` button. Presented as a `.sheet`.

### Form Fields

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| Branch name | TextField (createNew=true) / Picker (createNew=false) | empty / first item | Required |
| Path | TextField | `.worktrees/<branch-name>` (auto-generated) | Relative to repo root, user can override |
| Base branch | Picker | Current branch | Which branch/commit to branch from |
| Create new branch | Toggle | true | When false, shows Picker with existing branches |

**Auto-generated path rule:** Replace `/` in branch name with `-`. Example: `feature/auth` → `.worktrees/feature-auth`. Consistent with `development-rules.md` conventions.

**Path validation:** Before submission, check if the auto-generated (or user-overridden) path already exists. If so, show inline error: "Directory already exists". The `.worktrees/` parent directory is created by `git worktree add` automatically if it doesn't exist.

**Branch picker (createNew=false):** Calls `GitWorktreeMonitor.listBranches()` once when form appears. Excludes branches that already have a worktree.

**Error handling:** On git command failure, display error message inline in the form. Form stays open for user to correct and retry.

---

## Delete Worktree Confirmation

Triggered by right-click → `Delete Worktree` on a worktree row.

### Confirmation Dialog

**Clean worktree:**
```
Delete worktree "feature/auth"?

Path: /Users/xxx/poltertty/.worktrees/feature-auth

[Cancel]  [Delete]
```

**Dirty worktree:**
```
Delete worktree "feature/auth"?

Path: /Users/xxx/poltertty/.worktrees/feature-auth
⚠ 3 uncommitted changes will be lost

[Cancel]  [Force Delete]
```

### Behavior

- Before showing dialog: run `git -C <worktree-path> status --porcelain` to count uncommitted changes (total line count, no need to distinguish staged/modified)
- Clean worktree: show path only, button text is "Delete" (`role: .destructive`)
- Dirty worktree: show warning with change count, button text is **"Force Delete"** (`role: .destructive`) to make the destructive nature explicit
- Main worktree: delete option disabled/hidden
- Current worktree: delete option disabled/hidden
- Execution: clean → `git worktree remove <path>`; dirty → `git worktree remove --force <path>`

---

## Status Bar Visual Indicator

### Modified File: `BottomStatusBarView.swift`

When the current pane's working directory is inside a linked worktree (not the main worktree), display a colored `worktree` badge before the branch name:

```
Main worktree:     📁 ~/poltertty         | ⎇ main +2 ~1
Linked worktree:   📁 .worktrees/feat     | ⎇ [worktree] feature/auth +2
```

**Badge styling:** Background uses workspace theme color at 15% opacity, text in workspace theme color. Fallback color: `#cba6f7` (purple).

### Modified File: `GitStatusMonitor.swift`

Add `@Published var isLinkedWorktree: Bool = false` to `GitRepoStatus` or as a separate published property.

**Detection logic:** During `refresh()`, run `git rev-parse --git-common-dir`. If the result is not `.git` (i.e., it's a relative/absolute path like `../../.git`), the current directory is a linked worktree.

---

## File Summary

### New Files (all in `macos/Sources/Features/Workspace/`)

| File | Purpose |
|------|---------|
| `GitWorktreeMonitor.swift` | Worktree list management, filesystem watching, git command execution |
| `WorktreeListView.swift` | Collapsible worktree child list in sidebar |
| `WorktreeCreateForm.swift` | Create worktree sheet form |

### Modified Files

| File | Changes |
|------|---------|
| `WorkspaceSidebar.swift` | Embed `WorktreeListView` under `ExpandedWorkspaceItem`; add worktree submenu to `CollapsedWorkspaceIcon` context menu |
| `BottomStatusBarView.swift` | Add worktree badge in git status area |
| `GitStatusMonitor.swift` | Add `isLinkedWorktree` detection |
| `TerminalController.swift` | Own `GitWorktreeMonitor`; add `openNewTab(cdTo:)` and `openNewWindow(cdTo:)` methods |
| `PolterttyRootView.swift` | Pass `GitWorktreeMonitor` and worktree action callbacks to sidebar |

### Unchanged

`WorkspaceManager.swift`, `WorkspaceModel.swift` — worktree is a git-level concept, no changes to workspace data model.

---

## Error Handling

| Scenario | Behavior |
|----------|----------|
| `/usr/bin/git` fails / not a repo | `isGitRepo = false`, no worktree UI shown |
| `git worktree list` fails | `NSLog` error, keep last known state |
| `git worktree add` fails | Show git stderr in create form |
| `git worktree remove` fails | Show git stderr in alert |
| `.git` dir deleted while watching | DispatchSource fires → re-detect → `isGitRepo = false` → `stopWatching()` |
| Temporary workspace | Worktree list not shown (no git repo at temp dir) |
| Path already exists on create | Inline error in form: "Directory already exists" |

---

## Localization

All user-facing strings use `String(localized:)` with the existing localization pattern in the codebase. Key strings:

- `"worktree.badge"` → "worktree"
- `"worktree.add"` → "Add Worktree"
- `"worktree.delete.title"` → "Delete worktree \"%@\"?"
- `"worktree.delete.warning"` → "%d uncommitted changes will be lost"
- `"worktree.delete.confirm"` → "Delete"
- `"worktree.delete.force"` → "Force Delete"
- `"worktree.openInTab"` → "Open in New Tab"
- `"worktree.openInWindow"` → "Open in New Window"
