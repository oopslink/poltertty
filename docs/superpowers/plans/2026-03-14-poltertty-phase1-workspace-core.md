# poltertty Phase 1: Workspace Core Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add workspace management to Ghostty macOS — users can create, switch, and delete named workspaces, each 1:1 with a window, with layout snapshots persisted across app restarts.

**Architecture:** Workspace = Window (1:1). All new code in Swift. `PolterttyRootView` wraps the existing `TerminalView` and adds a sidebar. `WorkspaceManager` singleton manages workspace registry across windows. Snapshots stored as JSON at `~/.config/poltertty/workspaces/`.

**Tech Stack:** Swift, SwiftUI, AppKit (NSTitlebarAccessoryViewController), Codable JSON serialization

**Spec:** `docs/superpowers/specs/2026-03-14-poltertty-workspace-design.md`

---

## File Structure

### New Files

| File | Responsibility |
|------|----------------|
| `macos/Sources/Features/Workspace/WorkspaceModel.swift` | Codable data model (identity, snapshot, context) |
| `macos/Sources/Features/Workspace/WorkspaceManager.swift` | Global singleton — CRUD, persistence, cross-window sync |
| `macos/Sources/Features/Workspace/WorkspaceSidebar.swift` | SwiftUI sidebar view |
| `macos/Sources/Features/Workspace/WorkspaceQuickSwitcher.swift` | Cmd+Ctrl+W fuzzy search overlay |
| `macos/Sources/Features/Workspace/WorkspaceCreateForm.swift` | Inline creation form in sidebar |
| `macos/Sources/Features/Workspace/SidebarTitlebarOverlay.swift` | NSTitlebarAccessoryViewController overlay |
| `macos/Sources/Features/Workspace/PolterttyRootView.swift` | Root view wrapping TerminalView + Sidebar |
| `macos/Sources/Features/Workspace/PolterttyConfig.swift` | Reads `~/.config/poltertty/config` key-value file |

### Modified Files (minimal changes)

| File | Change |
|------|--------|
| `macos/Sources/Features/Terminal/TerminalController.swift` | In `windowDidLoad()` (~line 1038): wrap `TerminalView` in `PolterttyRootView`. Add sidebar titlebar overlay. |
| `macos/Sources/App/macOS/AppDelegate.swift` | Init `WorkspaceManager` on launch. Add Workspace menu items. |

---

## Chunk 1: Data Model + Config

### Task 1: PolterttyConfig — Config File Reader

**Files:**
- Create: `macos/Sources/Features/Workspace/PolterttyConfig.swift`

- [ ] **Step 1: Create PolterttyConfig struct**

```swift
// macos/Sources/Features/Workspace/PolterttyConfig.swift
import Foundation

struct PolterttyConfig {
    static let shared = PolterttyConfig()

    let workspaceDir: String
    let restoreOnLaunch: Bool
    let sidebarVisible: Bool
    let sidebarWidth: Int

    private init() {
        let values = Self.parse()
        self.workspaceDir = values["workspace-dir"]
            ?? ("~/.config/poltertty/workspaces" as NSString).expandingTildeInPath
        self.restoreOnLaunch = (values["workspace-restore-on-launch"] ?? "true") == "true"
        self.sidebarVisible = (values["workspace-sidebar-visible"] ?? "true") == "true"
        self.sidebarWidth = Int(values["workspace-sidebar-width"] ?? "200") ?? 200
    }

    private static func parse() -> [String: String] {
        let path = ("~/.config/poltertty/config" as NSString).expandingTildeInPath
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            result[key] = value
        }
        return result
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/oopslink/works/codes/oopslink/poltertty && zig build -Dapp-runtime=none 2>&1 | head -20`

If Zig build doesn't cover Swift, use: `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | tail -20`

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/PolterttyConfig.swift
git commit -m "feat(workspace): add poltertty config file reader"
```

---

### Task 2: WorkspaceModel — Data Model

**Files:**
- Create: `macos/Sources/Features/Workspace/WorkspaceModel.swift`

- [ ] **Step 1: Create WorkspaceModel**

```swift
// macos/Sources/Features/Workspace/WorkspaceModel.swift
import Foundation
import SwiftUI

struct WorkspaceModel: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var colorHex: String
    var icon: String
    var rootDir: String
    var description: String
    var tags: [String]
    let createdAt: Date
    var updatedAt: Date
    var lastActiveAt: Date

    init(name: String, rootDir: String, colorHex: String = "#FF6B6B", icon: String? = nil) {
        self.id = UUID()
        self.name = name
        self.rootDir = rootDir
        self.colorHex = colorHex
        self.icon = icon ?? String(name.prefix(2).uppercased())
        self.description = ""
        self.tags = []
        self.createdAt = Date()
        self.updatedAt = Date()
        self.lastActiveAt = Date()
    }

    var color: Color {
        Color(hex: colorHex) ?? .red
    }

    var nsColor: NSColor {
        NSColor(hex: colorHex) ?? .systemRed
    }

    var rootDirExpanded: String {
        (rootDir as NSString).expandingTildeInPath
    }

    var rootDirExists: Bool {
        FileManager.default.fileExists(atPath: rootDirExpanded)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Snapshot

struct WorkspaceSnapshot: Codable {
    var version: Int = 1
    var workspace: WorkspaceModel
    var windowFrame: WindowFrame?
    var sidebarWidth: CGFloat
    var sidebarVisible: Bool

    struct WindowFrame: Codable {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat

        init(from frame: NSRect) {
            self.x = frame.origin.x
            self.y = frame.origin.y
            self.width = frame.size.width
            self.height = frame.size.height
        }

        var nsRect: NSRect {
            NSRect(x: x, y: y, width: width, height: height)
        }
    }
}

// MARK: - Color Helpers

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let int = UInt64(hex, radix: 16) else { return nil }
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let int = UInt64(hex, radix: 16) else { return nil }
        let r = CGFloat((int >> 16) & 0xFF) / 255.0
        let g = CGFloat((int >> 8) & 0xFF) / 255.0
        let b = CGFloat(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
```

- [ ] **Step 2: Verify it compiles**

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceModel.swift
git commit -m "feat(workspace): add WorkspaceModel and WorkspaceSnapshot data models"
```

---

### Task 3: WorkspaceManager — Singleton

**Files:**
- Create: `macos/Sources/Features/Workspace/WorkspaceManager.swift`

- [ ] **Step 1: Create WorkspaceManager**

```swift
// macos/Sources/Features/Workspace/WorkspaceManager.swift
import Foundation
import Combine

class WorkspaceManager: ObservableObject {
    static let shared = WorkspaceManager()

    @Published var workspaces: [WorkspaceModel] = []
    /// Maps workspace ID to its owning NSWindow (weak reference)
    @Published var activeWindows: [UUID: NSWindow] = [:]

    private let storageDir: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        self.storageDir = PolterttyConfig.shared.workspaceDir
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        ensureStorageDir()
        loadAll()
    }

    // MARK: - CRUD

    @discardableResult
    func create(name: String, rootDir: String, colorHex: String = "#FF6B6B") -> WorkspaceModel {
        let workspace = WorkspaceModel(name: name, rootDir: rootDir, colorHex: colorHex)
        workspaces.append(workspace)
        save(workspace)
        return workspace
    }

    func update(_ workspace: WorkspaceModel) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        var updated = workspace
        updated.updatedAt = Date()
        workspaces[idx] = updated
        save(updated)
    }

    func delete(id: UUID) {
        workspaces.removeAll { $0.id == id }
        activeWindows.removeValue(forKey: id)
        let path = snapshotPath(for: id)
        try? FileManager.default.removeItem(atPath: path)
    }

    func workspace(for id: UUID) -> WorkspaceModel? {
        workspaces.first { $0.id == id }
    }

    // MARK: - Window Tracking

    func registerWindow(_ window: NSWindow, for workspaceId: UUID) {
        activeWindows[workspaceId] = window
        touchLastActive(workspaceId)
    }

    func unregisterWindow(for workspaceId: UUID) {
        activeWindows.removeValue(forKey: workspaceId)
    }

    func windowForWorkspace(_ id: UUID) -> NSWindow? {
        activeWindows[id]
    }

    func workspaceId(for window: NSWindow) -> UUID? {
        activeWindows.first { $0.value === window }?.key
    }

    func touchLastActive(_ id: UUID) {
        guard let idx = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[idx].lastActiveAt = Date()
    }

    // MARK: - Snapshot Persistence

    func saveSnapshot(for workspaceId: UUID, window: NSWindow, sidebarWidth: CGFloat, sidebarVisible: Bool) {
        guard var workspace = workspace(for: workspaceId) else { return }
        workspace.updatedAt = Date()

        let snapshot = WorkspaceSnapshot(
            workspace: workspace,
            windowFrame: WorkspaceSnapshot.WindowFrame(from: window.frame),
            sidebarWidth: sidebarWidth,
            sidebarVisible: sidebarVisible
        )

        let path = snapshotPath(for: workspaceId)
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: URL(fileURLWithPath: path))
        }

        // Update in-memory model
        if let idx = workspaces.firstIndex(where: { $0.id == workspaceId }) {
            workspaces[idx] = workspace
        }
    }

    func loadSnapshot(for workspaceId: UUID) -> WorkspaceSnapshot? {
        let path = snapshotPath(for: workspaceId)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? decoder.decode(WorkspaceSnapshot.self, from: data)
    }

    // MARK: - Private

    private func snapshotPath(for id: UUID) -> String {
        (storageDir as NSString).appendingPathComponent("\(id.uuidString).json")
    }

    private func ensureStorageDir() {
        try? FileManager.default.createDirectory(
            atPath: storageDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func loadAll() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: storageDir) else { return }
        for file in files where file.hasSuffix(".json") {
            let path = (storageDir as NSString).appendingPathComponent(file)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let snapshot = try? decoder.decode(WorkspaceSnapshot.self, from: data) else { continue }
            workspaces.append(snapshot.workspace)
        }
        workspaces.sort { $0.createdAt < $1.createdAt }
    }

    private func save(_ workspace: WorkspaceModel) {
        let snapshot = WorkspaceSnapshot(
            workspace: workspace,
            sidebarWidth: CGFloat(PolterttyConfig.shared.sidebarWidth),
            sidebarVisible: PolterttyConfig.shared.sidebarVisible
        )
        let path = snapshotPath(for: workspace.id)
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceManager.swift
git commit -m "feat(workspace): add WorkspaceManager singleton with CRUD and snapshot persistence"
```

---

## Chunk 2: UI Components

### Task 4: WorkspaceSidebar — SwiftUI View

**Files:**
- Create: `macos/Sources/Features/Workspace/WorkspaceSidebar.swift`

- [ ] **Step 1: Create WorkspaceSidebar**

```swift
// macos/Sources/Features/Workspace/WorkspaceSidebar.swift
import SwiftUI

struct WorkspaceSidebar: View {
    @ObservedObject var manager = WorkspaceManager.shared
    let currentWorkspaceId: UUID?
    let onSwitch: (UUID) -> Void
    let onCreate: () -> Void

    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("WORKSPACES")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(1)
                Spacer()
                Button(action: { isCreating = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create new workspace")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Workspace list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(manager.workspaces) { workspace in
                        WorkspaceSidebarItem(
                            workspace: workspace,
                            isActive: workspace.id == currentWorkspaceId,
                            onTap: { onSwitch(workspace.id) },
                            onDelete: { manager.delete(id: workspace.id) }
                        )
                    }
                }
                .padding(.vertical, 4)
            }

            Spacer()

            Divider()

            // Footer
            Button(action: { isCreating = true }) {
                HStack {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                    Text("New Workspace")
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if isCreating {
                WorkspaceCreateForm(
                    onSubmit: { name, rootDir, color in
                        manager.create(name: name, rootDir: rootDir, colorHex: color)
                        isCreating = false
                        onCreate()
                    },
                    onCancel: { isCreating = false }
                )
            }
        }
        .frame(minWidth: 160)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
}

// MARK: - Sidebar Item

struct WorkspaceSidebarItem: View {
    let workspace: WorkspaceModel
    let isActive: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isActive ? workspace.color : .clear)
                    .overlay(
                        Circle().stroke(workspace.color, lineWidth: isActive ? 0 : 1.5)
                    )
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(workspace.name)
                        .font(.system(size: 12, weight: isActive ? .medium : .regular))
                        .foregroundColor(isActive ? .primary : .secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isActive
                    ? workspace.color.opacity(0.08)
                    : (isHovering ? Color.primary.opacity(0.04) : .clear)
            )
            .overlay(
                Rectangle()
                    .fill(isActive ? workspace.color : .clear)
                    .frame(width: 3),
                alignment: .leading
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Delete Workspace", role: .destructive) { onDelete() }
        }
        .accessibilityLabel("Workspace: \(workspace.name), \(isActive ? "active" : "inactive")")
        .accessibilityHint(isActive ? "Current workspace" : "Double tap to switch")
    }
}
```

- [ ] **Step 2: Verify it compiles**

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceSidebar.swift
git commit -m "feat(workspace): add WorkspaceSidebar SwiftUI view"
```

---

### Task 5: WorkspaceCreateForm

**Files:**
- Create: `macos/Sources/Features/Workspace/WorkspaceCreateForm.swift`

- [ ] **Step 1: Create WorkspaceCreateForm**

```swift
// macos/Sources/Features/Workspace/WorkspaceCreateForm.swift
import SwiftUI

struct WorkspaceCreateForm: View {
    let onSubmit: (_ name: String, _ rootDir: String, _ colorHex: String) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var rootDir = "~"
    @State private var selectedColor = "#FF6B6B"

    private let presetColors = [
        "#FF6B6B", "#4ECDC4", "#FFD93D", "#6BCB77",
        "#7AA2F7", "#BB9AF7", "#FF9A8B", "#A8A8A8"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Text("New Workspace")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 12)

            // Name
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .padding(.horizontal, 12)

            // Root directory
            HStack {
                TextField("Root Directory", text: $rootDir)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                Button("...") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        rootDir = url.path
                    }
                }
                .font(.system(size: 10))
            }
            .padding(.horizontal, 12)

            // Color picker
            HStack(spacing: 6) {
                ForEach(presetColors, id: \.self) { color in
                    Circle()
                        .fill(Color(hex: color) ?? .gray)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle().stroke(.white, lineWidth: selectedColor == color ? 2 : 0)
                        )
                        .onTapGesture { selectedColor = color }
                }
            }
            .padding(.horizontal, 12)

            // Buttons
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .font(.system(size: 11))
                Button("Create") {
                    guard !name.isEmpty else { return }
                    onSubmit(name, rootDir, selectedColor)
                }
                .font(.system(size: 11))
                .keyboardShortcut(.return)
                .disabled(name.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
```

- [ ] **Step 2: Verify it compiles**

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceCreateForm.swift
git commit -m "feat(workspace): add WorkspaceCreateForm with color picker and directory chooser"
```

---

### Task 6: WorkspaceQuickSwitcher

**Files:**
- Create: `macos/Sources/Features/Workspace/WorkspaceQuickSwitcher.swift`

- [ ] **Step 1: Create WorkspaceQuickSwitcher**

```swift
// macos/Sources/Features/Workspace/WorkspaceQuickSwitcher.swift
import SwiftUI

struct WorkspaceQuickSwitcher: View {
    @ObservedObject var manager = WorkspaceManager.shared
    let currentWorkspaceId: UUID?
    let onSelect: (UUID) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0

    private var filtered: [WorkspaceModel] {
        if query.isEmpty { return manager.workspaces }
        return manager.workspaces.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Switch Workspace...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .onSubmit { confirmSelection() }
            }
            .padding(12)

            Divider()

            // Results
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, workspace in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(workspace.id == currentWorkspaceId ? workspace.color : .clear)
                                .overlay(
                                    Circle().stroke(workspace.color, lineWidth: workspace.id == currentWorkspaceId ? 0 : 1.5)
                                )
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(workspace.name)
                                    .font(.system(size: 13, weight: workspace.id == currentWorkspaceId ? .semibold : .regular))
                                Text(workspace.rootDir)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(index == selectedIndex ? Color.accentColor.opacity(0.15) : .clear)
                        .cornerRadius(4)
                        .onTapGesture {
                            onSelect(workspace.id)
                            onDismiss()
                        }
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 400)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.3), radius: 20)
        .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(1); return .handled }
        .onKeyPress(.escape) { onDismiss(); return .handled }
    }

    private func moveSelection(_ delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func confirmSelection() {
        guard !filtered.isEmpty, selectedIndex < filtered.count else { return }
        onSelect(filtered[selectedIndex].id)
        onDismiss()
    }
}
```

- [ ] **Step 2: Verify it compiles**

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceQuickSwitcher.swift
git commit -m "feat(workspace): add quick switcher with fuzzy search"
```

---

## Chunk 3: Integration

### Task 7: SidebarTitlebarOverlay

**Files:**
- Create: `macos/Sources/Features/Workspace/SidebarTitlebarOverlay.swift`

- [ ] **Step 1: Create SidebarTitlebarOverlay**

This view controller renders an opaque background in the titlebar area to visually cover the left portion of the native tab bar, creating the "tabs right-aligned" effect.

```swift
// macos/Sources/Features/Workspace/SidebarTitlebarOverlay.swift
import AppKit

class SidebarTitlebarOverlay: NSTitlebarAccessoryViewController {
    private var sidebarWidth: CGFloat

    init(sidebarWidth: CGFloat) {
        self.sidebarWidth = sidebarWidth
        super.init(nibName: nil, bundle: nil)
        self.layoutAttribute = .leading
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func loadView() {
        let overlay = NSView(frame: NSRect(x: 0, y: 0, width: sidebarWidth, height: 38))
        overlay.wantsLayer = true
        // Use the window background color to blend seamlessly
        overlay.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.95).cgColor
        self.view = overlay
    }

    func updateWidth(_ width: CGFloat) {
        sidebarWidth = width
        view.frame.size.width = width
        view.needsLayout = true
    }
}
```

- [ ] **Step 2: Verify it compiles**

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/SidebarTitlebarOverlay.swift
git commit -m "feat(workspace): add SidebarTitlebarOverlay for tab right-alignment effect"
```

---

### Task 8: PolterttyRootView — Wraps TerminalView

**Files:**
- Create: `macos/Sources/Features/Workspace/PolterttyRootView.swift`

- [ ] **Step 1: Create PolterttyRootView**

This is the key integration point. It wraps the existing `TerminalView` and adds the sidebar around it. The `TerminalView` is passed in as a generic view to avoid tight coupling.

```swift
// macos/Sources/Features/Workspace/PolterttyRootView.swift
import SwiftUI

struct PolterttyRootView<TerminalContent: View>: View {
    @ObservedObject var manager = WorkspaceManager.shared
    let workspaceId: UUID?
    let terminalView: TerminalContent
    let onSwitchWorkspace: (UUID) -> Void

    @State private var sidebarVisible: Bool = PolterttyConfig.shared.sidebarVisible
    @State private var sidebarWidth: CGFloat = CGFloat(PolterttyConfig.shared.sidebarWidth)
    @State private var quickSwitcherVisible = false

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // Sidebar
                if sidebarVisible {
                    WorkspaceSidebar(
                        currentWorkspaceId: workspaceId,
                        onSwitch: { id in onSwitchWorkspace(id) },
                        onCreate: {}
                    )
                    .frame(width: sidebarWidth)

                    Divider()
                }

                // Terminal view (passed through unchanged)
                terminalView
            }

            // Quick switcher overlay
            if quickSwitcherVisible {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { quickSwitcherVisible = false }

                WorkspaceQuickSwitcher(
                    currentWorkspaceId: workspaceId,
                    onSelect: { id in
                        onSwitchWorkspace(id)
                        quickSwitcherVisible = false
                    },
                    onDismiss: { quickSwitcherVisible = false }
                )
            }
        }
        .onKeyPress(KeyEquivalent("w"), modifiers: [.command, .control]) {
            quickSwitcherVisible.toggle()
            return .handled
        }
        .onKeyPress(KeyEquivalent("b"), modifiers: .command) {
            sidebarVisible.toggle()
            return .handled
        }
    }

    // Called by TerminalController to get current sidebar state for snapshots
    var currentSidebarWidth: CGFloat { sidebarWidth }
    var currentSidebarVisible: Bool { sidebarVisible }
}
```

- [ ] **Step 2: Verify it compiles**

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/PolterttyRootView.swift
git commit -m "feat(workspace): add PolterttyRootView wrapping TerminalView with sidebar"
```

---

### Task 9: Integrate into TerminalController

**Files:**
- Modify: `macos/Sources/Features/Terminal/TerminalController.swift` (~line 1038 in `windowDidLoad()`)

- [ ] **Step 1: Read the current windowDidLoad implementation**

Read `macos/Sources/Features/Terminal/TerminalController.swift` lines 1010-1090 to see the exact current code.

- [ ] **Step 2: Modify windowDidLoad to wrap TerminalView in PolterttyRootView**

In `windowDidLoad()`, find where `TerminalViewContainer` is created (~line 1038). Change:

```swift
// BEFORE (approximately line 1038-1040):
let container = TerminalViewContainer {
    TerminalView(ghostty: ghostty, viewModel: self, delegate: self)
}

// AFTER:
let container = TerminalViewContainer {
    PolterttyRootView(
        workspaceId: self.workspaceId,
        terminalView: TerminalView(ghostty: ghostty, viewModel: self, delegate: self),
        onSwitchWorkspace: { [weak self] id in
            self?.switchToWorkspace(id)
        }
    )
}
```

- [ ] **Step 3: Add workspaceId property and switchToWorkspace method to TerminalController**

Add near the top of `TerminalController` class:

```swift
/// The workspace this window is bound to (nil = legacy non-workspace window)
var workspaceId: UUID?
```

Add a method:

```swift
func switchToWorkspace(_ targetId: UUID) {
    // Save current workspace snapshot
    if let currentId = workspaceId, let window = self.window {
        WorkspaceManager.shared.saveSnapshot(
            for: currentId,
            window: window,
            sidebarWidth: 200, // TODO: get from PolterttyRootView
            sidebarVisible: true
        )
    }

    // Activate target workspace's window
    if let targetWindow = WorkspaceManager.shared.windowForWorkspace(targetId) {
        targetWindow.makeKeyAndOrderFront(nil)
    } else {
        // Create new window for this workspace
        guard let workspace = WorkspaceManager.shared.workspace(for: targetId) else { return }
        let config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = workspace.rootDirExpanded
        let controller = TerminalController.newWindow(ghostty, withBaseConfig: config)
        controller.workspaceId = targetId
        WorkspaceManager.shared.registerWindow(controller.window!, for: targetId)
    }
}
```

- [ ] **Step 4: Add sidebar titlebar overlay in windowDidLoad**

After the `window.contentView = container` line, add:

```swift
// Add sidebar titlebar overlay for tab right-alignment
if PolterttyConfig.shared.sidebarVisible {
    let overlay = SidebarTitlebarOverlay(
        sidebarWidth: CGFloat(PolterttyConfig.shared.sidebarWidth)
    )
    window.addTitlebarAccessoryViewController(overlay)
}
```

- [ ] **Step 5: Verify it compiles**

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Terminal/TerminalController.swift
git commit -m "feat(workspace): integrate PolterttyRootView and sidebar overlay into TerminalController"
```

---

### Task 10: AppDelegate Integration

**Files:**
- Modify: `macos/Sources/App/macOS/AppDelegate.swift`

- [ ] **Step 1: Read current AppDelegate**

Read `macos/Sources/App/macOS/AppDelegate.swift` to find `applicationDidFinishLaunching` and the `newWindow` action.

- [ ] **Step 2: Add workspace restoration on launch**

In `applicationDidFinishLaunching` (or equivalent startup method), add workspace restore logic:

```swift
// After ghostty app is initialized, restore workspaces
if PolterttyConfig.shared.restoreOnLaunch {
    let manager = WorkspaceManager.shared
    for workspace in manager.workspaces {
        if let snapshot = manager.loadSnapshot(for: workspace.id) {
            let config = Ghostty.SurfaceConfiguration()
            config.workingDirectory = workspace.rootDirExpanded
            let controller = TerminalController.newWindow(ghostty, withBaseConfig: config)
            controller.workspaceId = workspace.id
            if let frame = snapshot.windowFrame {
                controller.window?.setFrame(frame.nsRect, display: true)
            }
            manager.registerWindow(controller.window!, for: workspace.id)
        }
    }
}
```

- [ ] **Step 3: Add "New Workspace" menu item**

Add a menu action:

```swift
@IBAction func newWorkspace(_ sender: Any?) {
    // For now, create a workspace from the current directory
    let name = "workspace-\(WorkspaceManager.shared.workspaces.count + 1)"
    let rootDir = FileManager.default.currentDirectoryPath
    let workspace = WorkspaceManager.shared.create(name: name, rootDir: rootDir)

    let config = Ghostty.SurfaceConfiguration()
    config.workingDirectory = workspace.rootDirExpanded
    let controller = TerminalController.newWindow(ghostty, withBaseConfig: config)
    controller.workspaceId = workspace.id
    if let window = controller.window {
        WorkspaceManager.shared.registerWindow(window, for: workspace.id)
    }
}
```

- [ ] **Step 4: Save all workspace snapshots on app termination**

In `applicationWillTerminate` or equivalent:

```swift
// Save all active workspace snapshots
let manager = WorkspaceManager.shared
for (id, window) in manager.activeWindows {
    manager.saveSnapshot(for: id, window: window, sidebarWidth: 200, sidebarVisible: true)
}
```

- [ ] **Step 5: Verify it compiles**

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/App/macOS/AppDelegate.swift
git commit -m "feat(workspace): add workspace restore on launch and save on quit"
```

---

## Chunk 4: Polish + Validation

### Task 11: Add Workspace Menu Items to XIB

**Files:**
- Modify: Xcode XIB or storyboard for menu bar

- [ ] **Step 1: Add Workspace menu**

In Xcode, open the main menu XIB. Add a new top-level menu "Workspace" between "View" and "Window". Add items:
- "New Workspace" with shortcut Cmd+Shift+N, action `newWorkspace:`
- "Quick Switch" with shortcut Cmd+Ctrl+W (handled by SwiftUI onKeyPress, menu item for discoverability)
- Separator
- "Toggle Sidebar" with shortcut Cmd+B
- "Next Workspace" with shortcut Cmd+Ctrl+→
- "Previous Workspace" with shortcut Cmd+Ctrl+←

If XIB modification is not practical from CLI, add menu items programmatically in AppDelegate:

```swift
private func setupWorkspaceMenu() {
    let workspaceMenu = NSMenu(title: "Workspace")

    let newItem = NSMenuItem(title: "New Workspace", action: #selector(newWorkspace(_:)), keyEquivalent: "N")
    newItem.keyEquivalentModifierMask = [.command, .shift]
    workspaceMenu.addItem(newItem)

    workspaceMenu.addItem(.separator())

    let toggleSidebar = NSMenuItem(title: "Toggle Sidebar", action: #selector(toggleWorkspaceSidebar(_:)), keyEquivalent: "b")
    toggleSidebar.keyEquivalentModifierMask = .command
    workspaceMenu.addItem(toggleSidebar)

    let menuItem = NSMenuItem(title: "Workspace", action: nil, keyEquivalent: "")
    menuItem.submenu = workspaceMenu

    // Insert before "Window" menu
    if let mainMenu = NSApp.mainMenu,
       let windowMenuIndex = mainMenu.items.firstIndex(where: { $0.title == "Window" }) {
        mainMenu.insertItem(menuItem, at: windowMenuIndex)
    }
}
```

- [ ] **Step 2: Call setupWorkspaceMenu() in applicationDidFinishLaunching**

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/App/macOS/AppDelegate.swift
git commit -m "feat(workspace): add Workspace menu with keyboard shortcuts"
```

---

### Task 12: End-to-End Validation

- [ ] **Step 1: Build the project**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty
make -j$(sysctl -n hw.ncpu)
```

Or via Xcode:
```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | tail -30
```

- [ ] **Step 2: Fix any compilation errors**

Address any type mismatches, missing imports, or API compatibility issues.

- [ ] **Step 3: Manual smoke test**

Launch poltertty and verify:
1. Sidebar appears on the left side of the window
2. "WORKSPACES" header is visible
3. Clicking "+" or "New Workspace" creates a workspace entry
4. Creating a second workspace opens a new window
5. Clicking a workspace in the sidebar switches to that window
6. Cmd+B toggles the sidebar
7. Cmd+Ctrl+W shows the quick switcher
8. Quitting and relaunching restores workspace windows

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat(workspace): Phase 1 complete — workspace core with sidebar, switching, and snapshots"
```

---

## Summary

| Task | Component | Status |
|------|-----------|--------|
| 1 | PolterttyConfig | `- [ ]` |
| 2 | WorkspaceModel | `- [ ]` |
| 3 | WorkspaceManager | `- [ ]` |
| 4 | WorkspaceSidebar | `- [ ]` |
| 5 | WorkspaceCreateForm | `- [ ]` |
| 6 | WorkspaceQuickSwitcher | `- [ ]` |
| 7 | SidebarTitlebarOverlay | `- [ ]` |
| 8 | PolterttyRootView | `- [ ]` |
| 9 | TerminalController integration | `- [ ]` |
| 10 | AppDelegate integration | `- [ ]` |
| 11 | Workspace menu | `- [ ]` |
| 12 | Build + validation | `- [ ]` |
