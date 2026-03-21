# Poltertty

> A macOS fork of the Ghostty terminal emulator, designed for AI-assisted development workflows

Poltertty is built on top of [Ghostty](https://ghostty.org), preserving all of its core terminal capabilities while adding **Workspace management**, **File Browser**, **AI Agent monitoring**, and **deep tmux integration**.

[中文 README](README.md)

---

## Features

### Workspace Management

Multi-project terminal management at its core:

- **Create & manage**: Create dedicated Workspaces per project with custom names, colors, icons, root directories, and descriptions
- **Groups**: Organize related Workspaces into groups to keep the sidebar tidy
- **Persistence**: Configuration and window snapshots are automatically saved to `~/.config/poltertty/workspaces/` and restored on restart
- **Temporary Workspaces**: Opening a directory creates a temporary Workspace that is automatically cleaned up on exit — nothing written to disk
- **Quick Switcher**: `Cmd+K` to jump between Workspaces instantly
- **Sidebar**: Expand/collapse modes; double-click empty area to quickly create a temporary Workspace; right-click menu for rename, delete (with confirmation), and more

### File Browser

A lightweight file tree panel built into the terminal — no context switching needed:

- **Tree view**: Browse the file structure under the Workspace root; single-click to expand/collapse directories
- **Multi-select**: `Cmd+A` to select all, `Shift+Click` for range selection; batch delete and move
- **Drag & drop**: Multi-file drag-and-drop for moving files across directories
- **File filter**: Real-time filename filtering via the search bar at the top
- **File preview**: Click a file to preview its content on the right; supports `.zig`, common text, and code formats
- **Git status badges**: Live git change indicators (`M`/`A`/`?`, etc.) next to files
- **Keyboard navigation**: Arrow keys to browse the tree, `Enter` to expand directories, `Space` to inject the path into the active terminal session
- **Context menu**: Show in Finder, copy path, inline rename, and more
- **Shortcut**: `Cmd+\` to toggle the panel

### AI Agent Monitor

Native management of AI coding agent sessions — no external tools required:

- **Launch panel**: One-click launch for Claude Code, Gemini CLI, OpenCode, and custom commands
- **Session monitoring**: Real-time agent status via a built-in HTTP Hook Server that receives Claude Code hook events
- **Subagent tracking**: Visualize agent call trees with real-time tracking of subagent start and completion
- **External session discovery**: Automatically discovers and displays running Claude Code (`.jsonl`), OpenCode (SQLite), and Gemini sessions on the system
- **Sidebar button**: Quick access to the monitor panel from the sidebar

### Deep tmux Integration

tmux session management brought directly into the terminal UI:

- **tmux panel**: Attach tmux sessions as tabs and manage session windows in a dedicated panel
- **Window bar**: Displays all tmux windows with switching, creating new windows, and closing windows (with confirmation)
- **Quick attach/detach**: One-click attach or detach tmux sessions — no manual commands needed

### Bottom Status Bar

Real-time context information at the bottom of the terminal:

- **Git status**: Monitors the current Workspace root for git changes; displays branch name and change count live
- **Integrated display**: Status bar aligns with the shell area, rendered below the terminal content region

---

## Relationship to Ghostty

Poltertty is a direct fork of [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) and tracks upstream continuously.

| Layer | Details |
|-------|---------|
| **Terminal core** | Terminal emulation, rendering (Metal), fonts (CoreText), keybindings, and the configuration system all come from Ghostty — untouched |
| **New features** | All additions are implemented in Swift/SwiftUI as standalone modules under `macos/Sources/Features/` |
| **Config compatibility** | All Ghostty configuration options work in Poltertty; config file path is `~/.config/poltertty/config` |

For terminal emulation documentation, refer to the [official Ghostty docs](https://ghostty.org/docs).

---

## Building

```bash
# Initialize local Git Hooks (run once after cloning)
make init-git-hooks

# Development build and run
make run-dev

# Release build
make release

# List all available commands
make help
```

See [docs/build-rules.md](docs/build-rules.md) for detailed build instructions.
