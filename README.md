# Poltertty

**An agent-friendly terminal for the AI-native development era.**

Poltertty is a macOS fork of [Ghostty](https://ghostty.org) that adds first-class support for AI agent workflows — workspace management, a built-in file browser, a full Git panel, live agent session monitoring, an embedded MCP server, and deep tmux integration — while staying fully compatible with Ghostty's configuration and terminal core.

[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)](https://github.com/oopslink/poltertty)
[![Swift](https://img.shields.io/badge/language-Swift%2FSwiftUI-orange)](https://github.com/oopslink/poltertty)
[![Based on Ghostty](https://img.shields.io/badge/based%20on-Ghostty-purple)](https://ghostty.org)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

[中文文档](README.zh.md)

---

## Why Poltertty?

Modern AI coding agents — Claude Code, Gemini CLI, OpenCode — run inside terminals. But terminals were designed for humans, not agents. Poltertty bridges that gap:

- **Agents need project context.** Workspaces give every project its own isolated terminal environment, with persisted layout and configuration.
- **Agents need visibility.** The built-in Agent Monitor tracks running sessions, subagent call trees, and real-time status — no external dashboard needed.
- **Agents need control.** The embedded MCP server exposes terminal operations (send text, split panes, take screenshots) directly to any MCP-aware agent.
- **Humans need to stay in flow.** The file browser, Git panel, tmux integration, and per-pane status bar keep everything visible without leaving the terminal.

---

## Features

### Workspace Management

Persistent, per-project terminal environments:

- **Opt-in mode** — Workspace mode is disabled by default; enable it via the menu or press `⌥⌘P` to toggle the sidebar
- **Create & manage** — each Workspace has a name, color, icon, root directory, and description
- **Groups** — organize Workspaces into collapsible groups in the sidebar; drag-and-drop to reorganize
- **Persistence** — configuration and window snapshots saved to `~/.config/poltertty/workspaces/`, restored automatically on restart
- **Temporary Workspaces** — opening a directory creates a transient Workspace that is cleaned up on exit, nothing written to disk
- **Quick Switcher** — `Cmd+K` to jump between Workspaces instantly
- **Sidebar** — right-click to rename, delete, or move to group; double-click empty area to create a temporary Workspace
- **Single-window constraint** — when Workspace mode is active, only one Poltertty window is allowed; open a new Workspace to get a new window

### Git Worktree Management

First-class `git worktree` support surfaced directly in the sidebar:

- **Worktree list** — all linked worktrees shown under the Workspace entry, with real-time filesystem monitoring
- **Create & delete** — create worktrees with branch selection from a sheet; delete with confirmation
- **Missing worktree detection** — worktrees deleted outside the app are visually marked
- **File browser follows worktree** — switch the file browser root to any worktree with one click

### Git Panel

A full Git interface embedded in the terminal sidebar (`f`/`g` to toggle):

- **Changes view** — staged and unstaged file lists; stage, unstage, and discard individual files
- **Commit history** — browse commits with author, date, and message
- **Diff viewer** — inline diff with syntax highlighting; fullscreen mode keeps the commit sidebar visible
- **File history** — per-file commit history in a sheet
- **Follows worktree** — automatically reflects the active worktree's Git state

### AI Agent Monitor

Native visibility into AI coding agent sessions (`Cmd+Opt+M`):

- **Launch panel** — one-click launch for Claude Code, Gemini CLI, OpenCode, and custom commands; supports all 6 Claude permission modes
- **Session monitoring** — real-time agent status via a built-in Hook Server that receives Claude Code lifecycle events
- **Subagent tracking** — visualize agent call trees with a horizontal graph view; live tracking of tool calls, start/end times, and token usage
- **Session history** — persisted sessions shown in a History section; token billing aggregated per session
- **Notifications** — three-tier notification system (waiting / error / done); suppressed automatically when the target pane is in focus
- **External session discovery** — automatically discovers running Claude Code (`.jsonl`), OpenCode (SQLite), and Gemini sessions on the system

### Agent Dashboard

Global view across all sessions, all workspaces (`Cmd+Opt+D`):

- **Table & card modes** — switch between a compact table and a card grid
- **Cross-workspace aggregation** — all active and historical sessions in one place
- **Jump to pane** — double-click any row to navigate to and pulse-highlight the target pane

### Ctrl API — Terminal MCP Server

An embedded MCP HTTP server that lets AI agents control the terminal programmatically:

- **MCP tools** — `list_panes`, `focus_pane`, `split_pane`, `send_text`, `new_tab`, `screenshot`, `set_pane_annotation`, `get_pane_annotation`
- **Auto-configuration** — `SettingsMerger` automatically injects the MCP server URL into Claude Code settings on launch; no manual setup
- **SSE event stream** — agents can subscribe to real-time terminal events via Server-Sent Events
- **REST API** — versioned routes under `/v1/`, semantic HTTP status codes
- **Ctrl API Monitor** — a built-in panel (`Opt+Cmd+C`) showing all API calls with JSON syntax highlighting and a resizable detail pane

### Pane Annotations

Attach labels to split panes for agent situational awareness:

- **Inline editing** — click the annotation button in the status bar to open a popover editor
- **Floating card** — a subtle overlay card shows the annotation on top of the terminal content
- **MCP-accessible** — agents can read and write annotations via `get/set_pane_annotation`

### Fast Split Pane Focus

Keyboard-first navigation across split panes:

- **Double-tap Cmd** — triggers a pane selector overlay; press a number key to jump to that pane instantly
- **Numbered badges** — each pane shows its number badge with a brief flash animation when the selector is active

### File Browser

A lightweight file tree panel, integrated directly into the terminal (`Cmd+\`):

- **Tree view** — browse the Workspace root; single-click to expand/collapse directories
- **Multi-select** — `Cmd+A` to select all, `Shift+Click` for range selection; batch delete and move
- **Drag & drop** — drag multiple files across directories
- **Smart filters** — filter chips for quick views (e.g. "uncommitted files only"); breadcrumb navigation
- **File preview** — click any file to preview its contents with syntax highlighting and line numbers
- **Git status badges** — live change indicators (`M`/`A`/`?`) next to each file; stage/unstage/diff directly from the file browser
- **Keyboard navigation** — arrow keys to browse, `Enter` to expand, `Space` to inject the path into the active terminal, `?` for shortcut help
- **Context menu** — Show in Finder, copy path, inline rename, Open file history, Discard changes

### App Launcher

A fuzzy command palette triggered by double-tapping `Shift`:

- **Levenshtein ranking** — edit-distance search over all menu items and Poltertty-specific actions
- **Menu path subtitles** — shows the full menu path for each result so you know where the command lives
- **Per-window** — scoped to the key window; won't interfere with other Poltertty windows

### tmux Integration

tmux session management surfaced directly in the terminal UI:

- **Session panel** — browse and manage sessions, windows, and panes in a dedicated panel (`Cmd+Shift+X`)
- **Tab attach** — attach a tmux session as a terminal tab (`Cmd+Opt+T`); a window bar inside the tab lets you switch tmux windows, create new ones, and detach
- **Status bar button** — attach tmux directly from the split pane status bar
- **Confirmation on close** — closing a tab with an attached tmux session asks for confirmation

### Bottom Status Bar

Context at a glance, always visible, per split pane:

- **Git status** — branch name and change count, updated live; tracks the foreground process's CWD so the status follows `cd` commands
- **Agent status** — per-pane agent indicator; click to view session details or pick a different session
- **Worktree badge** — shows when the pane is inside a linked worktree
- **tmux attach button** — one-click tmux attach
- **Focus-aware** — dimmed when the pane is not focused

---

## Relationship to Ghostty

Poltertty is a direct fork of [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) and tracks upstream continuously.

| Layer | Details |
|-------|---------|
| **Terminal core** | Terminal emulation, Metal rendering, CoreText fonts, keybindings, and the configuration system come from Ghostty — untouched |
| **New features** | All additions are implemented in Swift/SwiftUI as standalone modules under `macos/Sources/Features/` |
| **Config compatibility** | All Ghostty configuration options work in Poltertty; config file path is `~/.config/poltertty/config` |

For terminal emulation documentation, refer to the [official Ghostty docs](https://ghostty.org/docs).

---

## Getting Started

### Prerequisites

- macOS 14 (Sonoma) or later
- Xcode 15 or later
- [Zig](https://ziglang.org/) (see [build-rules.md](docs/build-rules.md) for the required version)

### Build

```bash
# Clone the repository
git clone https://github.com/oopslink/poltertty.git
cd poltertty

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

---

## Contributing

Poltertty follows a branch-protection workflow:

1. All feature work is developed in git worktrees under `.worktrees/`
2. Changes land on `main` via Pull Request only — no direct pushes

See [docs/development-rules.md](docs/development-rules.md) for the full contribution workflow.

---

## License

Poltertty inherits Ghostty's [MIT License](LICENSE). New code added by this project is also MIT-licensed.
