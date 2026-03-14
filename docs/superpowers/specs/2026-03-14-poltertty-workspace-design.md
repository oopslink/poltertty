# poltertty Workspace Design Spec

**Date**: 2026-03-14
**Status**: Approved
**Platform**: macOS only

---

## 1. Overview

poltertty adds **Workspace** functionality to the Ghostty terminal emulator. A Workspace is a project-scoped context container that groups tabs, file browsing, environment configuration, and AI tool access around a single project root directory.

**Core principle**: Workspace = Window (1:1 mapping). This preserves native macOS tabs, requires zero changes to Ghostty's core Zig code (Surface, PTY, Renderer), and minimizes upstream merge conflicts.

## 2. Architecture

### 2.1 Relationship to Ghostty

poltertty is a fork of Ghostty that tracks upstream. All new code lives in the Swift layer. Zig core changes are limited to at most a few new C ABI functions for PTY access from the MCP server.

**Ghostty files NOT modified**:
- `src/Surface.zig` — terminal surface
- `src/terminal/` — terminal emulation
- `src/renderer/` — Metal rendering
- `src/apprt/embedded.zig` — embedding API (may add minor additions)
- `src/config/Config.zig` — may add new config keys only

**Ghostty files with minimal modification**:
- `macos/Sources/Features/Terminal/BaseTerminalController.swift` — swap `TerminalView` for `PolterttyRootView`
- `macos/Sources/Features/Terminal/TerminalController.swift` — add Sidebar titlebar accessory
- `macos/Sources/App/macOS/AppDelegate.swift` — add Workspace menu items, WorkspaceManager init

### 2.2 Hierarchy

```
NSWindow (TerminalWindow)  ←→  Workspace (1:1)
 ├─ titlebarAccessoryViewController
 │   └─ SidebarTitlebarOverlay (covers left side of native tab bar)
 │
 └─ contentView: TerminalViewContainer
     └─ NSHostingView
         └─ PolterttyRootView (wraps TerminalView)
             └─ HStack
                 ├─ WorkspaceSidebar (200px, Cmd+B toggle)
                 └─ VStack
                     ├─ HStack
                     │   ├─ FileBrowserPanel (260px, Cmd+\ toggle)
                     │   └─ TerminalView (reused as-is, contains SplitTree + CommandPalette + UpdateOverlay)
                     └─ StatusBar
```

### 2.3 New Swift Components

| Component | Type | Responsibility |
|-----------|------|----------------|
| `WorkspaceManager` | Singleton (ObservableObject) | Global workspace registry, snapshot persistence, cross-window state sync |
| `WorkspaceModel` | Struct (Codable) | Data model: id, name, color, icon, root_dir, description, tags, context, snapshot |
| `PolterttyRootView` | SwiftUI View | Root view that **wraps** the existing `TerminalView` (which contains `TerminalSplitTreeView`, command palette, update overlay, and focus management). `PolterttyRootView` adds Sidebar, FileBrowser, and StatusBar around the unchanged `TerminalView`. All `TerminalViewDelegate` calls flow through unchanged. |
| `WorkspaceSidebar` | SwiftUI View | Left sidebar listing all workspaces with active/inactive states |
| `SidebarTitlebarOverlay` | NSView (via NSTitlebarAccessoryViewController) | Opaque overlay covering left portion of native tab bar for right-aligned tab effect |
| `FileBrowserPanel` | SwiftUI View | File tree with Git status, filtering, file operations |
| `StatusBar` | SwiftUI View | Bottom bar: root path, Git branch, Git summary, runtime versions |

## 3. Workspace Model

### 3.1 Identity

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | UUID | auto | Unique identifier |
| `name` | String | yes | Human-readable name (e.g., `pulse-dashboard`) |
| `color` | String (hex) | yes | Color tag, applied to sidebar indicator, tab underline, status bar |
| `icon` | String | auto | Emoji or initials (e.g., `PD`) |
| `root_dir` | String (path) | yes | Project root directory |
| `description` | String | no | One-line description |
| `tags` | [String] | no | Freeform tags for search/grouping |
| `created_at` | Date | auto | |
| `updated_at` | Date | auto | |

### 3.2 Context (Environment)

| Field | Type | Description |
|-------|------|-------------|
| `env_vars` | [String: String] | Additional environment variables injected into new PTY sessions |
| `shell` | String? | Override shell (zsh/bash/fish) |
| `startup_commands` | [String] | Commands run on first activation (e.g., `nvm use 18`) |

Startup commands run once on first activation. Subsequent switches reuse background PTY sessions.

### 3.3 Snapshot

Captures full layout state for restoration after quit/restart.

**Contents**:
- File browser panel: visible, width, current_dir, show_hidden, sort_by, pinned_paths
- Tab list with order and labels
- Per-tab split tree topology (direction, ratio, nesting)
- Per-pane state: type (terminal/file_browser/preview), cwd, last_command
- Active tab and active pane IDs
- Window position and size

**Storage**: `~/.config/poltertty/workspaces/<id>.json`, human-readable JSON, Codable serialization. Uses a poltertty-specific directory to avoid collision if Ghostty is also installed.

**Save triggers**: tab open/close, pane create/close/resize, workspace switch, app quit, periodic (every 30s).

**Restore logic**:
- Has snapshot → rebuild tabs, splits, panes, restore cwd, set focus
- No snapshot → init with 1 tab ("main") + 1 terminal pane at root_dir
- root_dir missing → warn, fallback to `~`
- Pane cwd missing → fallback to root_dir
- Snapshot corrupted → discard, init default, notify user

### 3.4 Lifecycle

```
Created → First Activation (run startup_commands, init layout)
  → Active (auto-save snapshots)
  → Inactive (switch away; PTY keeps running, UI unloaded)
  → Active (switch back; restore from in-memory state)
  → Closed (save snapshot, terminate PTY)
  → Deleted (remove snapshot file)
```

Background PTY policy: `keep-running` (default). Max 10 background workspaces (configurable via `workspace-pty-max-background`); when exceeded, the workspace with the oldest `last_active_at` timestamp is terminated. Before auto-terminating, poltertty checks for running foreground processes in the workspace's PTYs — if any exist, the next-oldest workspace is chosen instead, and a notification is shown.

## 4. Workspace Sidebar

### 4.1 Layout

- Position: left edge of window, extends into titlebar area
- Default width: 200px, draggable, min 160px
- Toggle: `Cmd+B`
- Background: opaque, covers native tab bar on left side

### 4.2 Content

- Header: "WORKSPACES" label + "+" button
- Active workspace: filled color dot, highlighted background, left color border, tab names subtitle
- Inactive workspaces: hollow color dot, muted text, tab names subtitle
- Footer: "+ New Workspace" button

### 4.3 Interactions

| Action | Trigger |
|--------|---------|
| Switch workspace | Click inactive item → `NSWindow.makeKeyAndOrderFront` |
| Create workspace | Click "+" or `Cmd+Shift+N` |
| Edit workspace | Double-click name (inline edit) or right-click → Edit |
| Delete workspace | Right-click → Delete (with confirmation) |
| Reorder | Drag within list |
| Quick switcher | `Cmd+Ctrl+W` → modal fuzzy search panel |

### 4.4 Cross-Window Sync

`WorkspaceManager` is a singleton `ObservableObject`. All windows observe it. Changes (create, delete, rename, reorder, active state) propagate via `@Published` properties. Each window's sidebar highlights its own workspace as active.

## 5. File Browser Panel

### 5.1 Implementation Strategy

**Phase 1 (fast validation)**: Embed yazi TUI process in a terminal pane anchored to the left. Config option: `workspace-file-browser-cmd = yazi`. Minimal code change (~50 lines).

**Phase 2 (deep integration)**: Native SwiftUI tree view. Config option: `workspace-file-browser-cmd = native`. Features: Git status annotations, drag-and-drop, filtering, file operations, MCP addressability.

### 5.2 Phase 2 Spec (Native)

- Position: between Sidebar and Terminal area
- Default width: 260px, draggable
- Toggle: `Cmd+\`
- Root: workspace root_dir

**File tree features**:
- Expand/collapse directories
- Git status annotations: M (yellow), A (green), D (red), ? (gray)
- Directory inherits highest-priority child status (D > M > A > ?)
- Filter bar at top (type to filter current view, `Cmd+F` for recursive search)
- Hidden files toggle (`.` key), default hidden
- Sort by name/size/modified/kind
- Pinned directories
- Bottom summary: "3 Modified · 2 Untracked"

**File operations**: New file (N), New dir (Shift+N), Rename (R), Delete (Cmd+Delete, moves to trash), Copy/Paste/Cut, Drag to move, Multi-select.

**Cross-pane**: Right-click → Open in Terminal (T), Preview file (Space), Drag path to terminal, Open in $EDITOR (E), Copy path (Cmd+Shift+C).

**FS monitoring**: macOS FSEvents on root_dir, refresh within 300ms, pause when workspace is background, refresh on reactivation.

## 6. Status Bar

- Position: bottom of window, full width
- Content (left to right): root_dir path, Git branch, Git status summary (nM n?), runtime versions (Node/Python/Go)
- Interactions: click path → reveal in Finder, click branch → copy to clipboard

## 7. Tab Behavior

- Uses native macOS `NSWindow.tabGroup` — no custom tab bar
- Tab underline color matches workspace color tag (existing Ghostty `TerminalTabColor` mechanism)
- Sidebar titlebar overlay creates visual effect of tabs appearing only above terminal area
- All existing tab features preserved: drag to reorder, drag to new window, title editing

## 8. MCP Server

### 8.1 Architecture

Built into the poltertty process. Uses **Unix domain socket** transport — poltertty listens on a per-instance socket at `$TMPDIR/poltertty-<pid>.sock`. AI agents discover the socket via the `POLTERTTY_MCP_SOCKET` environment variable injected into every PTY session.

**Why not stdio**: PTY stdin/stdout carries the shell session's I/O. MCP JSON-RPC cannot be multiplexed on the same stream without a framing protocol. A Unix socket provides a clean out-of-band channel.

**Multi-instance handling**: Each poltertty process listens on its own socket (keyed by PID). AI agents inside a terminal pane connect to the socket advertised in their environment, which always routes to the correct poltertty instance.

**Stale socket cleanup**: On startup, poltertty checks for existing `poltertty-*.sock` files in `$TMPDIR`. For each, it verifies whether the owning PID is still running. Stale sockets (dead PID) are removed before the new socket is created. This handles crash/force-kill scenarios.

Workspace context injected as environment variables into every PTY session:
- `POLTERTTY_MCP_SOCKET` — path to the Unix domain socket
- `POLTERTTY_WORKSPACE_ID` — UUID
- `POLTERTTY_WORKSPACE_NAME` — human-readable name
- `POLTERTTY_ROOT_DIR` — absolute path to workspace root

### 8.2 Tools

**Workspace operations**:

| Tool | Params | Returns |
|------|--------|---------|
| `workspace_list` | — | Workspace[] |
| `workspace_create` | name, root_dir, color? | Workspace |
| `workspace_switch` | id | void |

**File operations** (paths relative to root_dir):

| Tool | Params | Returns |
|------|--------|---------|
| `file_list` | path, show_hidden?, git_status? | FileEntry[] |
| `file_read` | path, max_bytes? | string |
| `file_write` | path, content | void |
| `file_create` | path, is_dir? | void |
| `file_rename` | from, to | void |
| `file_delete` | path, trash? | void |
| `file_move` | from, to | void |
| `file_search` | query, max_results? | FileEntry[] |

**Terminal operations** (via C ABI bridge to Zig):

| Tool | Params | Returns |
|------|--------|---------|
| `terminal_run` | command, pane_id? | void |
| `terminal_read` | pane_id, lines? | string |
| `pane_list` | — | Pane[] |
| `pane_split` | direction, type? | Pane |
| `pane_close` | pane_id | void |

### 8.3 Security

| Operation | Approval |
|-----------|----------|
| file_read, file_list, file_search | No approval needed |
| file_create (new) | No approval needed |
| file_write (overwrite existing) | User approval dialog |
| file_delete | User approval dialog |
| file_move, file_rename | User approval dialog |
| terminal_run | Existing Ghostty approval mechanism |

Approval dialog shows: operation type, target path, agent name. Options: Allow / Deny / Allow all this session.

**Path security**: All file operation paths are resolved relative to `root_dir` and then canonicalized. Path traversal attempts (e.g., `../../etc/passwd`) that resolve outside `root_dir` are rejected with an error. Symlinks are followed only if the resolved target remains within `root_dir`.

## 9. Configuration

New config keys stored in a **poltertty-specific config file** (`~/.config/poltertty/config`) parsed in Swift, separate from Ghostty's `Config.zig`. This avoids modifying the Zig config parser and eliminates merge conflicts on config changes. Ghostty's own config keys remain unchanged.

**Format**: Same key-value format as Ghostty's config (`key = value`, one per line, `#` comments) for user familiarity. Parsed by a lightweight Swift config reader.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `workspace-dir` | path | `~/.config/poltertty/workspaces/` | Snapshot storage directory |
| `workspace-restore-on-launch` | bool | `true` | Restore last workspaces on startup |
| `workspace-file-browser-visible` | bool | `true` | Show file browser panel by default |
| `workspace-file-browser-width` | int | `260` | File browser panel width (px) |
| `workspace-file-browser-cmd` | string | `native` | File browser implementation (`native` or `yazi`) |
| `workspace-pty-background` | enum | `keep-running` | Background PTY policy |
| `workspace-pty-max-background` | int | `10` | Max background workspaces |
| `workspace-snapshot-interval` | int | `30` | Auto-save interval (seconds, 0 = disabled) |
| `workspace-sidebar-visible` | bool | `true` | Show workspace sidebar |
| `workspace-sidebar-width` | int | `200` | Sidebar width (px) |
| `workspace-mcp-approval` | enum | `per-action` | MCP write approval granularity |

## 10. Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+Ctrl+W` | Quick workspace switcher (fuzzy search) |
| `Cmd+Shift+N` | Create new workspace |
| `Cmd+Ctrl+→/←` | Next/previous workspace |
| `Cmd+B` | Toggle workspace sidebar |
| `Cmd+\` | Toggle file browser panel |

File browser shortcuts (when focused): N (new file), Shift+N (new dir), R (rename), T (open in terminal), Space (preview), `.` (toggle hidden), Cmd+Delete (delete), Cmd+F (search), Cmd+R (refresh).

## 11. Phased Implementation

### Phase 1: Workspace Core (3-4 weeks)

- `WorkspaceManager` singleton + `WorkspaceModel` (Codable)
- `WorkspaceSidebar` (SwiftUI)
- `SidebarTitlebarOverlay` (NSTitlebarAccessoryViewController)
- `PolterttyRootView` (replaces TerminalView, wraps Sidebar + existing SplitTree)
- Snapshot save/restore (terminal panes only)
- Create / switch / delete workspace
- Quick switcher panel (`Cmd+Ctrl+W`)
- Config keys: workspace-dir, workspace-restore-on-launch, workspace-sidebar-visible, workspace-sidebar-width

**Validation**: User can create 3 workspaces, split terminals in each, switch between them with layout preserved across app restart.

### Phase 2: File Browser + Status Bar (2-3 weeks)

- `FileBrowserPanel` — yazi embed first, then native SwiftUI
- `StatusBar` — Git branch, status summary, runtime versions
- Context: env_vars, startup_commands
- FSEvents file watching
- Git status annotations
- Config keys: workspace-file-browser-*, workspace-pty-*, workspace-snapshot-interval

**Validation**: File browser shows project tree with Git status, status bar shows branch info, environment auto-configured on activation.

### Phase 3: MCP + AI Integration (3-4 weeks)

- MCP server (Unix domain socket, Swift implementation)
- File operation tools (file_list, file_read, file_write, etc.)
- Terminal operation tools (via C ABI bridge)
- Workspace operation tools
- Security approval dialogs
- Environment variable injection (POLTERTTY_*)
- Config keys: workspace-mcp-approval

**Validation**: Claude Code running in a terminal pane can list files, read content, write changes (with approval), and run commands via MCP.

## 12. Performance Targets

| Metric | Target |
|--------|--------|
| Workspace switch (window activation) | < 300ms |
| File browser initial render (1000 files) | < 100ms |
| File browser large dir (10,000 files) | < 500ms (virtualized) |
| FSEvents to UI update | < 300ms |
| MCP file read response | < 200ms |
| MCP file write response | < 500ms |
| Snapshot save | < 50ms |
| Snapshot restore | < 200ms |

## 13. Open Decisions

| # | Question | Decision |
|---|----------|----------|
| 1 | Workspace list scope | Global (shared across windows via WorkspaceManager singleton) |
| 2 | Same workspace in multiple windows | Disallowed in v1. Uses `flock()` advisory lock on snapshot file (auto-releases on crash). Second open attempt shows alert and focuses existing window. |
| 3 | File Preview in v1 | No, text-only code highlighting if added |
| 4 | Templates | Deferred to v1.1 |
| 5 | auto-suspend idle detection | Deferred, only keep-running and terminate for now |
| 6 | iCloud/dotfiles sync | Deferred to v1.1 |
| 7 | Windows/Linux | Not planned |

## 14. Additional Specifications

### 14.1 Titlebar Style Compatibility

Ghostty supports multiple titlebar styles: `native`, `hidden`, `transparent`, `tabs` (Ventura/Tahoe). The sidebar titlebar overlay behavior varies:

| Titlebar style | Sidebar overlay behavior |
|----------------|------------------------|
| `native` | Full support — overlay covers left portion of tab bar |
| `tabs` (Ventura/Tahoe) | Full support — overlay covers left portion of custom tab bar |
| `transparent` | Overlay uses matching transparency; sidebar background extends into titlebar |
| `hidden` | No titlebar overlay needed — sidebar simply extends to window top edge |

### 14.2 Git Status Detection

Git information (branch, status) is obtained by shelling out to `git` CLI:
- Branch: `git -C <root_dir> rev-parse --abbrev-ref HEAD`
- Status: `git -C <root_dir> status --porcelain`

Runs asynchronously on a background queue. Results cached and refreshed on FSEvents trigger or manual refresh (`Cmd+R`). If `git` is not installed or `root_dir` is not a Git repo, Git UI elements are hidden gracefully.

### 14.3 Window Restoration

poltertty's workspace snapshot system **replaces** Ghostty's native `NSWindowRestoration` (`TerminalRestorableState`) for workspace-managed windows. On app launch:
1. If `workspace-restore-on-launch = true`, WorkspaceManager restores all previously-open workspaces from snapshots
2. Ghostty's `TerminalWindowRestoration` is skipped for these windows
3. Non-workspace windows (if any) still use Ghostty's native restoration

### 14.4 Accessibility

All workspace UI components include VoiceOver support:
- Sidebar items: `.accessibilityLabel("Workspace: <name>, <active/inactive>")`, `.accessibilityHint("Double tap to switch")`
- File browser entries: `.accessibilityLabel("<filename>, <git status>")`
- Status bar elements: `.accessibilityLabel` for each segment
- Full keyboard navigation within sidebar (`↑↓` to navigate, `Enter` to activate, `Delete` to remove)
