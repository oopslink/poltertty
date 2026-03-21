# Poltertty

**An agent-friendly terminal for the AI-native development era.**

Poltertty is a macOS fork of [Ghostty](https://ghostty.org) that adds first-class support for AI agent workflows — workspace management, a built-in file browser, live agent session monitoring, and deep tmux integration — while staying fully compatible with Ghostty's configuration and terminal core.

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
- **Agents need hooks.** The embedded HTTP Hook Server receives Claude Code lifecycle events directly, enabling reactive workflows without any glue code.
- **Humans need to stay in flow.** The file browser, tmux integration, and status bar keep everything visible without leaving the terminal.

---

## Features

### Workspace Management

Persistent, per-project terminal environments:

- **Create & manage** — each Workspace has a name, color, icon, root directory, and description
- **Groups** — organize Workspaces into collapsible groups in the sidebar
- **Persistence** — configuration and window snapshots saved to `~/.config/poltertty/workspaces/`, restored automatically on restart
- **Temporary Workspaces** — opening a directory creates a transient Workspace that is cleaned up on exit, nothing written to disk
- **Quick Switcher** — `Cmd+K` to jump between Workspaces instantly
- **Sidebar** — right-click to rename or delete; double-click empty area to create a temporary Workspace

### AI Agent Monitor

Native visibility into AI coding agent sessions:

- **Launch panel** — one-click launch for Claude Code, Gemini CLI, OpenCode, and custom commands
- **Session monitoring** — real-time agent status via a built-in HTTP Hook Server that receives Claude Code hook events
- **Subagent tracking** — visualize agent call trees with live tracking of subagent start and completion
- **External session discovery** — automatically discovers running Claude Code (`.jsonl`), OpenCode (SQLite), and Gemini sessions on the system
- **Sidebar integration** — dedicated sidebar button for quick access

### File Browser

A lightweight file tree panel, integrated directly into the terminal:

- **Tree view** — browse the Workspace root; single-click to expand/collapse directories
- **Multi-select** — `Cmd+A` to select all, `Shift+Click` for range selection; batch delete and move
- **Drag & drop** — drag multiple files across directories
- **Real-time filter** — search bar at the top for instant filename filtering
- **File preview** — click any file to preview its contents; supports `.zig`, common text, and code formats
- **Git status badges** — live change indicators (`M`/`A`/`?`) next to each file
- **Keyboard navigation** — arrow keys to browse, `Enter` to expand, `Space` to inject the path into the active terminal
- **Context menu** — Show in Finder, copy path, inline rename
- **Toggle** — `Cmd+\`

### tmux Integration

tmux session management surfaced directly in the terminal UI:

- **Session panel** — attach tmux sessions as tabs; manage windows in a dedicated panel
- **Window bar** — displays all tmux windows; create, switch, and close with confirmation
- **Quick attach/detach** — one click, no commands to type

### Bottom Status Bar

Context at a glance, always visible:

- **Git status** — branch name and change count for the current Workspace root, updated live
- **Inline rendering** — aligned with the shell area, rendered below the terminal content region

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
