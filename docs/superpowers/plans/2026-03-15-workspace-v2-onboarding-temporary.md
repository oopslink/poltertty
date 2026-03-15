# Workspace V2: Onboarding, Temporary Workspaces & Sidebar Polish

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement temporary workspaces, first-launch onboarding, cold-start recovery UI, name validation, and sidebar switching animations per the product design spec.

**Architecture:** Extends existing Phase 1 workspace system. Adds `isTemporary` flag to `WorkspaceModel`, new `OnboardingView` and `RestoreView` SwiftUI views rendered inside a shell-less temporary workspace on startup, name validation in `WorkspaceCreateForm`, and `matchedGeometryEffect`-based sidebar animations. No Zig changes.

**Tech Stack:** Swift, SwiftUI, AppKit, Codable JSON

**Spec:** User-provided product design doc (2026-03-15 conversation), Phase 1 spec at `docs/superpowers/specs/2026-03-14-poltertty-workspace-design.md`

---

## File Structure

### New Files

| File | Responsibility |
|------|----------------|
| `macos/Sources/Features/Workspace/WorkspaceNameValidator.swift` | Name validation: special char filtering, length limit, uniqueness check |
| `macos/Sources/Features/Workspace/OnboardingView.swift` | First-launch guide page — name input, quick tags, create/skip |
| `macos/Sources/Features/Workspace/RestoreView.swift` | Cold-start recovery page — workspace list with checkboxes, restore/new |
| `macos/Sources/Features/Workspace/WorkspaceStartupMode.swift` | File-scope `StartupMode` enum (cannot nest inside generic `PolterttyRootView<T>`) |

### Modified Files

| File | Change |
|------|--------|
| `WorkspaceModel.swift` | Add `isTemporary` field, `WorkspaceKind` enum |
| `WorkspaceManager.swift` | Add temporary workspace CRUD, auto-naming (`scratch-N`), `convertToFormal()`, filtered lists, destroy on quit |
| `WorkspaceSidebar.swift` | Split into formal/temporary sections, add `⏱` icon, warm yellow active color, `+ New Temporary` button, sliding active indicator animation |
| `WorkspaceCreateForm.swift` | Integrate `WorkspaceNameValidator`, add shake animation + error states |
| `PolterttyRootView.swift` | Add onboarding/restore view state, keyboard ↑/↓ navigation |
| `AppDelegate.swift` | Replace auto-restore-all with restore UI flow, add Cmd+Shift+T shortcut, temporary cleanup on quit |

---

## Chunk 1: Name Validation + Model Changes

### Task 1: WorkspaceNameValidator

**Files:**
- Create: `macos/Sources/Features/Workspace/WorkspaceNameValidator.swift`

- [ ] **Step 1: Create WorkspaceNameValidator**

```swift
// macos/Sources/Features/Workspace/WorkspaceNameValidator.swift
import Foundation

struct WorkspaceNameValidator {
    /// Characters that are silently blocked during input
    static let blockedCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")

    /// Maximum name length
    static let maxLength = 32

    /// Filter blocked characters from input string (for real-time input filtering)
    static func filterInput(_ input: String) -> String {
        let filtered = input.unicodeScalars.filter { !blockedCharacters.contains($0) }
        let result = String(String.UnicodeScalarView(filtered))
        return String(result.prefix(maxLength))
    }

    /// Validate on submit — returns error message or nil if valid
    static func validate(_ name: String, existingNames: [String]) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return "请输入名称"
        }
        if existingNames.contains(where: { $0.lowercased() == trimmed.lowercased() }) {
            return "该名称已存在"
        }
        return nil
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | tail -20`

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceNameValidator.swift
git commit -m "feat(workspace): add name validator with char filtering and uniqueness check"
```

---

### Task 2: Add isTemporary to WorkspaceModel

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceModel.swift`

- [ ] **Step 1: Read current WorkspaceModel.swift**

Read `macos/Sources/Features/Workspace/WorkspaceModel.swift` to see current state.

- [ ] **Step 2: Add isTemporary field and kind computed property**

Add a new field `isTemporary: Bool` with default `false` to the `WorkspaceModel` struct. Add it after `lastActiveAt`:

```swift
var isTemporary: Bool

init(name: String, rootDir: String, colorHex: String = "#FF6B6B", icon: String? = nil, isTemporary: Bool = false) {
    // ... existing init code ...
    self.isTemporary = isTemporary
}
```

Since `WorkspaceModel` conforms to `Codable`, the new field needs a default for backward compatibility with existing JSON snapshots. Add a custom `init(from decoder:)`:

```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    colorHex = try container.decode(String.self, forKey: .colorHex)
    icon = try container.decode(String.self, forKey: .icon)
    rootDir = try container.decode(String.self, forKey: .rootDir)
    description = try container.decode(String.self, forKey: .description)
    tags = try container.decode([String].self, forKey: .tags)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    lastActiveAt = try container.decode(Date.self, forKey: .lastActiveAt)
    isTemporary = try container.decodeIfPresent(Bool.self, forKey: .isTemporary) ?? false
}
```

- [ ] **Step 3: Verify it compiles**

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceModel.swift
git commit -m "feat(workspace): add isTemporary flag to WorkspaceModel with backward-compatible decoding"
```

---

### Task 3: Add temporary workspace support to WorkspaceManager

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceManager.swift`

- [ ] **Step 1: Read current WorkspaceManager.swift**

Read `macos/Sources/Features/Workspace/WorkspaceManager.swift`.

- [ ] **Step 2: Add computed properties for filtered lists**

Add after the `activeWindows` declaration:

```swift
/// Only formal (non-temporary) workspaces
var formalWorkspaces: [WorkspaceModel] {
    workspaces.filter { !$0.isTemporary }
}

/// Only temporary workspaces
var temporaryWorkspaces: [WorkspaceModel] {
    workspaces.filter { $0.isTemporary }
}

/// Whether any temporary workspaces exist (controls sidebar section visibility)
var hasTemporaryWorkspaces: Bool {
    workspaces.contains { $0.isTemporary }
}
```

- [ ] **Step 3: Add createTemporary method with auto-naming**

Add after the existing `create` method:

```swift
/// Create a temporary workspace with auto-generated name (scratch, scratch-2, ...)
@discardableResult
func createTemporary(rootDir: String = "~") -> WorkspaceModel {
    let name = nextScratchName()
    var workspace = WorkspaceModel(name: name, rootDir: rootDir, colorHex: "#F59E0B", isTemporary: true)
    workspace.icon = "⏱"
    workspaces.append(workspace)
    // Temporary workspaces are NOT persisted to disk
    return workspace
}

private func nextScratchName() -> String {
    let existing = temporaryWorkspaces.map { $0.name }
    if !existing.contains("scratch") { return "scratch" }
    var counter = 2
    while existing.contains("scratch-\(counter)") {
        counter += 1
    }
    return "scratch-\(counter)"
}
```

- [ ] **Step 4: Add convertToFormal method**

```swift
/// Convert a temporary workspace to formal (persistent)
func convertToFormal(id: UUID, newName: String) {
    guard let idx = workspaces.firstIndex(where: { $0.id == id && $0.isTemporary }) else { return }
    workspaces[idx].isTemporary = false
    workspaces[idx].name = newName
    workspaces[idx].updatedAt = Date()
    save(workspaces[idx])
}
```

- [ ] **Step 5: Add destroyAllTemporary method**

```swift
/// Destroy all temporary workspaces (called on app quit)
func destroyAllTemporary() {
    let tempIds = temporaryWorkspaces.map { $0.id }
    for id in tempIds {
        activeWindows.removeValue(forKey: id)
    }
    workspaces.removeAll { $0.isTemporary }
}
```

- [ ] **Step 6: Modify loadAll to skip temporary snapshots**

In the existing `loadAll()` method, temporary workspaces should never be loaded from disk (they're not saved). No change needed here since `save()` is never called for temporary workspaces. But add a guard in `save()`:

```swift
private func save(_ workspace: WorkspaceModel) {
    // Temporary workspaces are not persisted
    guard !workspace.isTemporary else { return }
    // ... existing save logic ...
}
```

Also guard `saveSnapshot`:

In `saveSnapshot(for:window:sidebarWidth:sidebarVisible:)`, add at the top:

```swift
guard let workspace = workspace(for: workspaceId), !workspace.isTemporary else {
    // Still update in-memory model for non-temporary
    if let ws = workspace(for: workspaceId), !ws.isTemporary {
        // existing logic
    }
    return
}
```

Actually, simpler approach — just guard the file write part. Keep the in-memory update. Change the existing `saveSnapshot` method to:

```swift
func saveSnapshot(for workspaceId: UUID, window: NSWindow, sidebarWidth: CGFloat, sidebarVisible: Bool) {
    guard var workspace = workspace(for: workspaceId) else { return }
    workspace.updatedAt = Date()

    // Update in-memory model
    if let idx = workspaces.firstIndex(where: { $0.id == workspaceId }) {
        workspaces[idx] = workspace
    }

    // Temporary workspaces are not persisted to disk
    guard !workspace.isTemporary else { return }

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
}
```

- [ ] **Step 7: Verify it compiles**

- [ ] **Step 8: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceManager.swift
git commit -m "feat(workspace): add temporary workspace support — create, convert, destroy, auto-naming"
```

---

### Task 4: Integrate name validation into WorkspaceCreateForm

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceCreateForm.swift`

- [ ] **Step 1: Read current WorkspaceCreateForm.swift**

Read `macos/Sources/Features/Workspace/WorkspaceCreateForm.swift`.

- [ ] **Step 2: Add validation state and real-time filtering**

Add new state variables:

```swift
@State private var errorMessage: String?
@State private var isShaking = false
@ObservedObject var manager = WorkspaceManager.shared
```

- [ ] **Step 3: Replace the Name TextField with a filtered version**

Replace the name `TextField` and its container with:

```swift
// Name
VStack(alignment: .leading, spacing: 4) {
    Text("Name")
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.secondary)
    TextField("My Project", text: Binding(
        get: { name },
        set: { name = WorkspaceNameValidator.filterInput($0) }
    ))
    .textFieldStyle(.roundedBorder)
    .font(.system(size: 13))
    .overlay(
        RoundedRectangle(cornerRadius: 4)
            .stroke(errorMessage != nil ? Color.red : Color.clear, lineWidth: 1.5)
    )
    .modifier(ShakeEffect(shakes: isShaking ? 6 : 0))

    if let error = errorMessage {
        Text(error)
            .font(.system(size: 10))
            .foregroundColor(.red)
    }
}
```

Also create a `ShakeEffect` modifier (add to `WorkspaceNameValidator.swift` or a shared location):

```swift
struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = sin(shakes * .pi * 2) * 5
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}
```

- [ ] **Step 4: Update the Create button action with submit validation**

Replace the Create button action:

```swift
Button("Create") {
    let existingNames = manager.workspaces.map { $0.name }
    if let error = WorkspaceNameValidator.validate(name, existingNames: existingNames) {
        errorMessage = error
        // Shake animation (multiple oscillations via ShakeEffect)
        withAnimation(.linear(duration: 0.4)) { isShaking = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { isShaking = false }
        return
    }
    errorMessage = nil
    onSubmit(name, rootDir, selectedColor, description)
}
.keyboardShortcut(.return)
.disabled(name.isEmpty)
```

- [ ] **Step 5: Clear error on typing**

Add `.onChange(of: name)` modifier to the form VStack:

```swift
.onChange(of: name) { _ in
    errorMessage = nil
}
```

- [ ] **Step 6: Verify it compiles**

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceCreateForm.swift
git commit -m "feat(workspace): add name validation with char filtering, shake animation, and error states"
```

---

## Chunk 2: Onboarding & Restore Views

### Task 5: OnboardingView — First Launch Guide

**Files:**
- Create: `macos/Sources/Features/Workspace/OnboardingView.swift`

- [ ] **Step 1: Create OnboardingView**

```swift
// macos/Sources/Features/Workspace/OnboardingView.swift
import SwiftUI

struct OnboardingView: View {
    let onCreateFormal: (String) -> Void
    let onCreateTemporary: () -> Void

    @ObservedObject var manager = WorkspaceManager.shared
    @State private var name = "dev"
    @State private var errorMessage: String?
    @State private var isShaking = false

    private let quickTags = ["home", "dev", "work", "tmp"]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo area
            VStack(spacing: 16) {
                Text("✦ Ghostty")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)

                Text("给你的第一个 Workspace 起个名字")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            Spacer().frame(height: 32)

            // Name input
            VStack(spacing: 12) {
                TextField("", text: Binding(
                    get: { name },
                    set: { name = WorkspaceNameValidator.filterInput($0) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 16))
                .multilineTextAlignment(.center)
                .frame(width: 280)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(errorMessage != nil ? Color.red : Color.clear, lineWidth: 1.5)
                )
                .modifier(ShakeEffect(shakes: isShaking ? 6 : 0))
                .onAppear {
                    // Auto-select all text on appear
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NSApp.keyWindow?.fieldEditor(true, for: nil)?.selectAll(nil)
                    }
                }
                .onSubmit { submitName() }

                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }

                // Quick tags
                HStack(spacing: 8) {
                    ForEach(quickTags, id: \.self) { tag in
                        Button(tag) {
                            name = tag
                            errorMessage = nil
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(6)
                        .buttonStyle(.plain)
                    }
                }
                .foregroundColor(.secondary)
            }

            Spacer().frame(height: 24)

            // Create button
            Button(action: submitName) {
                Text("创建 →")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Spacer().frame(height: 16)

            // Temporary option
            Button(action: onCreateTemporary) {
                Text("新建临时 Workspace")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: name) { _ in errorMessage = nil }
    }

    private func submitName() {
        let existingNames = manager.workspaces.map { $0.name }
        if let error = WorkspaceNameValidator.validate(name, existingNames: existingNames) {
            errorMessage = error
            withAnimation(.default) { isShaking = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.default) { isShaking = false }
            }
            return
        }
        onCreateFormal(name)
    }
}
```

- [ ] **Step 2: Verify it compiles**

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/OnboardingView.swift
git commit -m "feat(workspace): add first-launch onboarding view with name input and quick tags"
```

---

### Task 6: RestoreView — Cold Start Recovery

**Files:**
- Create: `macos/Sources/Features/Workspace/RestoreView.swift`

- [ ] **Step 1: Create RestoreView**

```swift
// macos/Sources/Features/Workspace/RestoreView.swift
import SwiftUI

struct RestoreView: View {
    let workspaces: [WorkspaceModel]
    let onRestore: ([UUID]) -> Void
    let onCreateNew: () -> Void

    @State private var selected: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Title
            VStack(spacing: 8) {
                Text("📂 恢复 Workspaces")
                    .font(.system(size: 20, weight: .bold))
            }

            Spacer().frame(height: 24)

            // Workspace list
            VStack(spacing: 0) {
                ForEach(workspaces) { workspace in
                    Button(action: { toggleSelection(workspace.id) }) {
                        HStack(spacing: 12) {
                            Image(systemName: selected.contains(workspace.id) ? "checkmark.square.fill" : "square")
                                .font(.system(size: 16))
                                .foregroundColor(selected.contains(workspace.id) ? .accentColor : .secondary)

                            Text(workspace.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)

                            Spacer()

                            Text(relativeTime(workspace.lastActiveAt))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            selected.contains(workspace.id)
                                ? Color.accentColor.opacity(0.06)
                                : Color.clear
                        )
                    }
                    .buttonStyle(.plain)

                    if workspace.id != workspaces.last?.id {
                        Divider().padding(.horizontal, 16)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(10)
            .frame(width: 400)

            Spacer().frame(height: 24)

            // Main restore button
            Button(action: {
                onRestore(Array(selected))
            }) {
                Text("恢复选中的 (\(selected.count))")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(selected.isEmpty ? Color.gray : Color.accentColor)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(selected.isEmpty)

            Spacer().frame(height: 12)

            // Quick actions
            HStack(spacing: 16) {
                Button("只恢复最近一个") {
                    if let first = workspaces.first {
                        onRestore([first.id])
                    }
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .buttonStyle(.plain)

                Text("|").foregroundColor(.secondary.opacity(0.3))

                Button("全部恢复") {
                    onRestore(workspaces.map { $0.id })
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
            }

            Spacer().frame(height: 20)

            // New workspace option
            Button(action: onCreateNew) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                    Text("新建 Workspace")
                        .font(.system(size: 12))
                }
                .foregroundColor(selected.isEmpty ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { preselectRecent() }
    }

    private func toggleSelection(_ id: UUID) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    /// Default: select the 2 most recently active workspaces
    private func preselectRecent() {
        let recent = workspaces.prefix(2)
        selected = Set(recent.map { $0.id })
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
```

- [ ] **Step 2: Verify it compiles**

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/RestoreView.swift
git commit -m "feat(workspace): add cold-start restore view with checkboxes and quick actions"
```

---

## Chunk 3: Sidebar Redesign

### Task 7: Sidebar — Temporary section + animations

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceSidebar.swift`

- [ ] **Step 1: Read current WorkspaceSidebar.swift**

Read `macos/Sources/Features/Workspace/WorkspaceSidebar.swift`.

- [ ] **Step 2: Update expanded view to split formal/temporary sections**

Replace the workspace list `ScrollView` in `expandedContent` with two sections:

```swift
// Workspace list
ScrollView {
    LazyVStack(spacing: 2) {
        // Formal workspaces
        ForEach(manager.formalWorkspaces) { workspace in
            ExpandedWorkspaceItem(
                workspace: workspace,
                isActive: workspace.id == currentWorkspaceId,
                isOpen: manager.windowForWorkspace(workspace.id) != nil,
                onTap: { onSwitch(workspace.id) },
                onClose: { onClose(workspace.id) },
                onDelete: { manager.delete(id: workspace.id) }
            )
        }

        // Temporary section — only shown when temporary workspaces exist
        if manager.hasTemporaryWorkspaces {
            HStack {
                Text("Temporary")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.6))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)

            ForEach(manager.temporaryWorkspaces) { workspace in
                ExpandedWorkspaceItem(
                    workspace: workspace,
                    isActive: workspace.id == currentWorkspaceId,
                    isOpen: manager.windowForWorkspace(workspace.id) != nil,
                    onTap: { onSwitch(workspace.id) },
                    onClose: { onClose(workspace.id) },
                    onDelete: { manager.delete(id: workspace.id) }
                )
            }
        }
    }
    .padding(.vertical, 4)
}
```

- [ ] **Step 3: Update footer to add "+ New Temporary" button**

Replace the footer section with:

```swift
// Footer
VStack(spacing: 4) {
    Button(action: { isCreating = true }) {
        HStack {
            Image(systemName: "plus")
                .font(.system(size: 10))
            Text("New")
                .font(.system(size: 11))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
    .buttonStyle(.plain)

    Button(action: onCreateTemporary) {
        HStack {
            Image(systemName: "plus")
                .font(.system(size: 10))
            Text("New Temporary")
                .font(.system(size: 11))
        }
        .foregroundColor(.secondary.opacity(0.7))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
    .buttonStyle(.plain)
}
```

Add `onCreateTemporary` and `onConvert` to the `WorkspaceSidebar` callback parameters:

```swift
let onCreateTemporary: () -> Void
let onConvert: (WorkspaceModel) -> Void
```

**IMPORTANT — Pass `onConvert` and `animationNamespace` to all `ExpandedWorkspaceItem` call sites.** Every `ExpandedWorkspaceItem(...)` in the formal and temporary `ForEach` loops must include:

```swift
ExpandedWorkspaceItem(
    workspace: workspace,
    isActive: workspace.id == currentWorkspaceId,
    isOpen: manager.windowForWorkspace(workspace.id) != nil,
    animationNamespace: sidebarAnimation,
    onTap: { onSwitch(workspace.id) },
    onClose: { onClose(workspace.id) },
    onDelete: { manager.delete(id: workspace.id) },
    onConvert: { onConvert(workspace) }
)
```

Similarly update all `CollapsedWorkspaceIcon` call sites to pass `onConvert`.

- [ ] **Step 4: Update ExpandedWorkspaceItem for temporary visual distinction**

In `ExpandedWorkspaceItem`, modify the left color indicator and active background:

```swift
// Color indicator — warm yellow for temporary
private var indicatorColor: Color {
    workspace.isTemporary ? Color(hex: "#F59E0B")! : workspace.color
}

private var activeBackground: Color {
    workspace.isTemporary
        ? Color(hex: "#F59E0B")!.opacity(0.08)
        : workspace.color.opacity(0.08)
}
```

Update the `RoundedRectangle` fill to use `indicatorColor` and the background to use `activeBackground`.

Add the `⏱` icon before the workspace name for temporary workspaces:

```swift
HStack(spacing: 4) {
    if workspace.isTemporary {
        Text("⏱")
            .font(.system(size: 10))
    }
    Text(workspace.name)
        .font(.system(size: 12, weight: isActive ? .semibold : .medium))
        .foregroundColor(isActive ? .primary : .secondary)
        .lineLimit(1)
    // ... green dot ...
}
```

- [ ] **Step 5: Add context menu "Convert to Formal" for temporary workspaces**

In the `.contextMenu` of `ExpandedWorkspaceItem`, add:

```swift
.contextMenu {
    if workspace.isTemporary {
        Button("转为正式 Workspace") { onConvert() }
        Divider()
    }
    if isOpen {
        Button("Close Workspace") { onClose() }
        Divider()
    }
    Button("Delete Workspace", role: .destructive) { onDelete() }
}
```

Add `onConvert` callback to `ExpandedWorkspaceItem` parameters:

```swift
let onConvert: () -> Void
```

- [ ] **Step 6: Add sliding active indicator animation**

Add a `@Namespace` for matched geometry in `WorkspaceSidebar`:

```swift
@Namespace private var sidebarAnimation
```

In `ExpandedWorkspaceItem`, replace the static left indicator overlay with a `matchedGeometryEffect`:

```swift
.overlay(alignment: .leading) {
    if isActive {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(indicatorColor)
            .frame(width: 3, height: 36)
            .matchedGeometryEffect(id: "activeIndicator", in: animationNamespace)
    }
}
```

Pass the namespace down from `WorkspaceSidebar`:

```swift
let animationNamespace: Namespace.ID
```

Wrap the workspace list changes in `withAnimation(.easeOut(duration: 0.12))` when switching.

- [ ] **Step 7: Add click scale animation to workspace items**

In `ExpandedWorkspaceItem`, add:

```swift
@State private var isPressed = false
```

Replace `Button(action: onTap)` wrapper with a gesture-based approach or add `.scaleEffect(isPressed ? 0.97 : 1.0)` with `onTapGesture`:

```swift
.scaleEffect(isPressed ? 0.97 : 1.0)
.onTapGesture {
    withAnimation(.easeOut(duration: 0.08)) { isPressed = true }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
        withAnimation(.easeOut(duration: 0.08)) { isPressed = false }
        onTap()
    }
}
```

- [ ] **Step 8: Update collapsed sidebar similarly**

Apply the same formal/temporary split and visual changes to `collapsedContent`:
- Show temporary icons with warm yellow tint
- Add a divider between formal and temporary sections

- [ ] **Step 9: Verify it compiles**

- [ ] **Step 10: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceSidebar.swift
git commit -m "feat(workspace): sidebar redesign — temporary section, warm yellow theme, sliding indicator, scale animation"
```

---

### Task 8: Update PolterttyRootView for onboarding/restore + keyboard nav

**Files:**
- Modify: `macos/Sources/Features/Workspace/PolterttyRootView.swift`

- [ ] **Step 1: Read current PolterttyRootView.swift**

Read `macos/Sources/Features/Workspace/PolterttyRootView.swift`.

- [ ] **Step 2: Create WorkspaceStartupMode enum (file-scope, NOT nested in generic view)**

Create `macos/Sources/Features/Workspace/WorkspaceStartupMode.swift`:

```swift
// macos/Sources/Features/Workspace/WorkspaceStartupMode.swift
import Foundation

/// Defines what PolterttyRootView should display on startup.
/// Defined at file scope because it must be referenced from TerminalController,
/// and Swift does not allow referencing types nested inside a generic struct
/// (PolterttyRootView<T>) from non-generic contexts.
enum WorkspaceStartupMode {
    case terminal       // Normal workspace with terminal
    case onboarding     // First launch, no workspaces
    case restore        // Cold start with existing workspaces
}
```

Then in `PolterttyRootView.swift`, add state:

```swift
@State private var startupMode: WorkspaceStartupMode = .terminal
```

And add an `initialStartupMode` parameter to the init so `TerminalController` can set it:

```swift
let initialStartupMode: WorkspaceStartupMode
// In body's .onAppear:
.onAppear { startupMode = initialStartupMode }
```

- [ ] **Step 3: Conditionally show onboarding/restore instead of terminal**

Wrap the body content to show different views based on `startupMode`:

```swift
var body: some View {
    ZStack {
        switch startupMode {
        case .onboarding:
            OnboardingView(
                onCreateFormal: { name in
                    onCreateFormalWorkspace?(name)
                    startupMode = .terminal
                },
                onCreateTemporary: {
                    onCreateTemporaryWorkspace?()
                    startupMode = .terminal
                }
            )

        case .restore:
            RestoreView(
                workspaces: manager.formalWorkspaces.sorted { $0.lastActiveAt > $1.lastActiveAt },
                onRestore: { ids in
                    onRestoreWorkspaces?(ids)
                    startupMode = .terminal
                },
                onCreateNew: {
                    startupMode = .onboarding
                }
            )

        case .terminal:
            // Existing HStack with sidebar + terminal
            HStack(spacing: 0) {
                if sidebarVisible {
                    WorkspaceSidebar(
                        currentWorkspaceId: workspaceId,
                        onSwitch: { id in onSwitchWorkspace(id) },
                        onClose: { id in onCloseWorkspace(id) },
                        onCreate: {},
                        onCreateTemporary: { onCreateTemporaryWorkspace?() },
                        isCollapsed: $sidebarCollapsed
                    )
                    .frame(width: effectiveSidebarWidth)
                    Divider()
                }
                terminalView
            }
        }

        // Quick switcher overlay (always available)
        if quickSwitcherVisible {
            // ... existing quick switcher code ...
        }
    }
    // ... existing notification receivers ...
}
```

Add new callback properties:

```swift
let onCreateFormalWorkspace: ((String) -> Void)?
let onCreateTemporaryWorkspace: (() -> Void)?
let onRestoreWorkspaces: (([UUID]) -> Void)?
```

**IMPORTANT — Wire these at the call site in TerminalController.swift (~line 1091):**

The existing `PolterttyRootView(...)` construction in `TerminalController.windowDidLoad()` must be updated to pass all new parameters:

```swift
PolterttyRootView(
    workspaceId: self.workspaceId,
    terminalView: TerminalView(ghostty: ghostty, viewModel: self, delegate: self),
    initialStartupMode: self.startupMode,
    onSwitchWorkspace: { [weak self] id in self?.switchToWorkspace(id) },
    onCloseWorkspace: { [weak self] id in self?.closeWorkspace(id) },
    onCreateFormalWorkspace: { [weak self] name in
        self?.createFormalWorkspace(name: name)
    },
    onCreateTemporaryWorkspace: { [weak self] in
        self?.createTemporaryWorkspace()
    },
    onRestoreWorkspaces: { [weak self] ids in
        self?.restoreWorkspaces(ids)
    }
)
```

Add the corresponding methods to `TerminalController`:

```swift
private func createFormalWorkspace(name: String) {
    let workspace = WorkspaceManager.shared.create(name: name, rootDir: "~")
    switchToWorkspace(workspace.id)
}

private func createTemporaryWorkspace() {
    let workspace = WorkspaceManager.shared.createTemporary()
    switchToWorkspace(workspace.id)
}

private func restoreWorkspaces(_ ids: [UUID]) {
    // Delegate to AppDelegate's restoreWorkspaces method
    if let appDelegate = NSApp.delegate as? AppDelegate {
        appDelegate.restoreWorkspaces(ids, replacingWindow: self.window)
    }
}
```

- [ ] **Step 4: Add sidebar keyboard navigation (↑/↓)**

Add to the `.terminal` case `HStack`, a `.onReceive` for sidebar keyboard events, or use `.onKeyPress`:

```swift
.onReceive(NotificationCenter.default.publisher(for: .workspaceSidebarNavigateUp)) { _ in
    navigateWorkspace(direction: -1)
}
.onReceive(NotificationCenter.default.publisher(for: .workspaceSidebarNavigateDown)) { _ in
    navigateWorkspace(direction: 1)
}
```

Add the method:

```swift
private func navigateWorkspace(direction: Int) {
    let allWorkspaces = manager.workspaces
    guard !allWorkspaces.isEmpty else { return }
    guard let currentId = workspaceId,
          let currentIndex = allWorkspaces.firstIndex(where: { $0.id == currentId }) else {
        // No current workspace, select first
        if let first = allWorkspaces.first {
            onSwitchWorkspace(first.id)
        }
        return
    }
    let newIndex = (currentIndex + direction + allWorkspaces.count) % allWorkspaces.count
    onSwitchWorkspace(allWorkspaces[newIndex].id)
}
```

Add notification names:

```swift
extension Notification.Name {
    static let workspaceSidebarNavigateUp = Notification.Name("poltertty.workspaceSidebarNavigateUp")
    static let workspaceSidebarNavigateDown = Notification.Name("poltertty.workspaceSidebarNavigateDown")
}
```

- [ ] **Step 5: Verify it compiles**

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Workspace/PolterttyRootView.swift
git commit -m "feat(workspace): add onboarding/restore startup modes and sidebar keyboard navigation"
```

---

## Chunk 4: AppDelegate Integration + Lifecycle

### Task 9: AppDelegate — Startup flow + temporary cleanup

**Files:**
- Modify: `macos/Sources/App/macOS/AppDelegate.swift`

- [ ] **Step 1: Read current AppDelegate startup logic**

Read `macos/Sources/App/macOS/AppDelegate.swift` lines 330-370 (workspace restoration area) and lines 440-470 (quit area).

- [ ] **Step 2: Replace auto-restore-all with startup mode detection**

Replace the current workspace restoration block with startup mode detection:

```swift
// Determine startup mode
let manager = WorkspaceManager.shared
let hasWorkspaces = !manager.formalWorkspaces.isEmpty

if hasWorkspaces {
    // Cold start with existing workspaces → show restore UI
    // Create a temporary workspace to host the restore view
    let tempWorkspace = manager.createTemporary()
    let controller = TerminalController.newWindow(ghostty, withBaseConfig: Ghostty.SurfaceConfiguration())
    controller.workspaceId = tempWorkspace.id
    controller.startupMode = .restore
    if let window = controller.window {
        manager.registerWindow(window, for: tempWorkspace.id)
    }
} else {
    // First launch → show onboarding
    let tempWorkspace = manager.createTemporary()
    let controller = TerminalController.newWindow(ghostty, withBaseConfig: Ghostty.SurfaceConfiguration())
    controller.workspaceId = tempWorkspace.id
    controller.startupMode = .onboarding
    if let window = controller.window {
        manager.registerWindow(window, for: tempWorkspace.id)
    }
}
```

Note: This requires `TerminalController` to have a `startupMode` property that gets passed to `PolterttyRootView`. Add this property to `TerminalController`:

```swift
var startupMode: WorkspaceStartupMode = .terminal
```

This uses the file-scope `WorkspaceStartupMode` enum created in Task 8, Step 2 (in `WorkspaceStartupMode.swift`). Pass it when creating `PolterttyRootView` in `windowDidLoad()` via the `initialStartupMode` parameter.

- [ ] **Step 3: Add restore callback implementation**

Add a method to AppDelegate (or TerminalController) that handles the restore action:

```swift
func restoreWorkspaces(_ ids: [UUID], replacingWindow: NSWindow?) {
    let manager = WorkspaceManager.shared

    // Destroy the temporary workspace hosting the restore view
    if let window = replacingWindow,
       let tempId = manager.workspaceId(for: window) {
        manager.delete(id: tempId)
        window.close()
    }

    // Restore selected workspaces
    var isFirst = true
    for id in ids {
        guard let workspace = manager.workspace(for: id) else { continue }
        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = workspace.rootDirExpanded

        let controller = TerminalController.newWindow(ghostty, withBaseConfig: config)
        controller.workspaceId = id

        if let snapshot = manager.loadSnapshot(for: id),
           let frame = snapshot.windowFrame {
            controller.window?.setFrame(frame.nsRect, display: true)
        }

        if let window = controller.window {
            manager.registerWindow(window, for: id)
            if isFirst {
                window.makeKeyAndOrderFront(nil)
                isFirst = false
            }
        }
    }
}
```

- [ ] **Step 4: Add Cmd+Shift+T menu item for temporary workspace**

In the `setupWorkspaceMenu()` method (or wherever workspace menu items are added):

```swift
let newTemp = NSMenuItem(title: "New Temporary Workspace", action: #selector(newTemporaryWorkspace(_:)), keyEquivalent: "T")
newTemp.keyEquivalentModifierMask = [.command, .shift]
workspaceMenu.addItem(newTemp)
```

Add the action:

```swift
@IBAction func newTemporaryWorkspace(_ sender: Any?) {
    let manager = WorkspaceManager.shared
    let workspace = manager.createTemporary()

    var config = Ghostty.SurfaceConfiguration()
    config.workingDirectory = workspace.rootDirExpanded
    let controller = TerminalController.newWindow(ghostty, withBaseConfig: config)
    controller.workspaceId = workspace.id
    if let window = controller.window {
        manager.registerWindow(window, for: workspace.id)
    }
}
```

- [ ] **Step 5: Add temporary workspace cleanup on quit**

In `applicationWillTerminate` (AppDelegate.swift, currently around line 451), insert **before** the existing snapshot save loop (the `for (id, window) in manager.activeWindows` block at ~line 454):

```swift
// Destroy all temporary workspaces BEFORE saving snapshots
// This ensures temporary workspaces are not iterated in the save loop
WorkspaceManager.shared.destroyAllTemporary()
```

- [ ] **Step 6: Add temporary workspace close confirmation**

In the window close delegate method (likely `windowShouldClose` or `windowWillClose` in TerminalController), add check for temporary workspace with running processes:

```swift
// In TerminalController's window close handling
if let wsId = workspaceId,
   let workspace = WorkspaceManager.shared.workspace(for: wsId),
   workspace.isTemporary {
    // Check if any process is running (check if terminal has active child process)
    // If process is running, show confirmation alert
    if hasRunningProcesses() {
        let alert = NSAlert()
        alert.messageText = "有进程正在运行"
        alert.informativeText = "确认关闭临时 Workspace？"
        alert.addButton(withTitle: "关闭")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        if alert.runModal() == .alertSecondButtonReturn {
            return // Cancel close
        }
    }
    // Destroy temporary workspace
    WorkspaceManager.shared.delete(id: wsId)
}
```

- [ ] **Step 7: Verify it compiles**

- [ ] **Step 8: Commit**

```bash
git add macos/Sources/App/macOS/AppDelegate.swift macos/Sources/Features/Terminal/TerminalController.swift
git commit -m "feat(workspace): startup flow with onboarding/restore, temporary cleanup, Cmd+Shift+T"
```

---

### Task 10: Convert-to-formal flow

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceSidebar.swift` (wire up convert callback)
- Modify: `macos/Sources/Features/Workspace/PolterttyRootView.swift` (add convert alert)

- [ ] **Step 1: Add convert-to-formal alert in PolterttyRootView**

Add state for the convert flow:

```swift
@State private var showConvertAlert = false
@State private var convertTargetId: UUID?
@State private var convertName = ""
```

Add an `.alert` or `.sheet` modifier for the conversion:

```swift
.sheet(isPresented: $showConvertAlert) {
    VStack(spacing: 16) {
        Text("转为正式 Workspace")
            .font(.system(size: 14, weight: .semibold))

        TextField("名称", text: Binding(
            get: { convertName },
            set: { convertName = WorkspaceNameValidator.filterInput($0) }
        ))
        .textFieldStyle(.roundedBorder)
        .frame(width: 240)

        HStack {
            Button("取消") { showConvertAlert = false }
            Button("确认") {
                if let id = convertTargetId {
                    manager.convertToFormal(id: id, newName: convertName)
                }
                showConvertAlert = false
            }
            .disabled(convertName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
    .padding(24)
}
```

- [ ] **Step 2: Wire up the convert callback through the sidebar**

In the `WorkspaceSidebar` onConvert handler, set:

```swift
onConvert: { workspace in
    convertTargetId = workspace.id
    convertName = workspace.name
    showConvertAlert = true
}
```

- [ ] **Step 3: Verify it compiles**

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceSidebar.swift macos/Sources/Features/Workspace/PolterttyRootView.swift
git commit -m "feat(workspace): add convert-to-formal flow with name input sheet"
```

---

## Chunk 5: Build + Validation

### Task 11: Build and fix compilation errors

- [ ] **Step 1: Build the project**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty && xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | tail -40
```

- [ ] **Step 2: Fix any compilation errors**

Address type mismatches, missing parameters in call sites, protocol conformance issues. Common issues to watch for:
- `WorkspaceSidebar` init call sites need new `onCreateTemporary` and `onConvert` parameters
- `PolterttyRootView` init call sites need new callback parameters
- `ExpandedWorkspaceItem` init call sites need `onConvert` and `animationNamespace` parameters
- Ensure `StartupMode` enum is accessible from both `PolterttyRootView` and `TerminalController`

- [ ] **Step 3: Iteratively fix and rebuild until clean**

- [ ] **Step 4: Commit fixes**

```bash
git add -A
git commit -m "fix(workspace): resolve compilation errors from V2 integration"
```

---

### Task 12: Manual smoke test checklist

- [ ] **Step 1: First launch (delete workspaces dir to simulate)**

```bash
# Backup and clear
mv ~/.config/poltertty/workspaces ~/.config/poltertty/workspaces.bak
```

Launch poltertty. Verify:
1. Onboarding page appears (not terminal)
2. "dev" is pre-filled and selected
3. Quick tags (home/dev/work/tmp) are clickable
4. Special characters can't be typed (`/\:*?"<>|`)
5. Name truncates at 32 characters
6. Empty name shows error with red border + shake
7. Clicking "创建" creates workspace and shows terminal
8. Clicking "新建临时 Workspace" creates scratch workspace

- [ ] **Step 2: Cold start restore**

```bash
# Restore backup
mv ~/.config/poltertty/workspaces.bak ~/.config/poltertty/workspaces
```

Launch poltertty. Verify:
1. Restore view appears with workspace list
2. Most recent 2 are pre-checked
3. Checkboxes toggle correctly
4. "恢复选中的 (N)" button text updates
5. "只恢复最近一个" works
6. "全部恢复" works
7. "+ 新建 Workspace" switches to onboarding view

- [ ] **Step 3: Temporary workspace lifecycle**

1. Create temporary via Cmd+Shift+T → sidebar shows "⏱ scratch"
2. Create another → "⏱ scratch-2"
3. Sidebar shows "Temporary" section divider
4. Right-click → "转为正式 Workspace" → enter name → moves to formal section
5. Close window with running process → confirmation dialog
6. Close window without process → instant close
7. Quit and relaunch → temporary workspaces are gone

- [ ] **Step 4: Sidebar visual polish**

1. Active workspace shows left color bar + filled indicator + highlighted background
2. Temporary active shows warm yellow instead of workspace color
3. Clicking workspace has brief scale-down effect
4. Active indicator slides between items (if matchedGeometryEffect works)
5. ↑/↓ keyboard navigation works when sidebar is focused

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "feat(workspace): V2 complete — onboarding, restore, temporary workspaces, sidebar polish"
```

---

## Summary

| Task | Component | Chunk |
|------|-----------|-------|
| 1 | WorkspaceNameValidator | 1 |
| 2 | WorkspaceModel — isTemporary | 1 |
| 3 | WorkspaceManager — temporary CRUD | 1 |
| 4 | WorkspaceCreateForm — validation | 1 |
| 5 | OnboardingView | 2 |
| 6 | RestoreView | 2 |
| 7 | WorkspaceSidebar — redesign | 3 |
| 8 | PolterttyRootView — startup modes + keyboard nav | 3 |
| 9 | AppDelegate — startup flow + lifecycle | 4 |
| 10 | Convert-to-formal flow | 4 |
| 11 | Build + fix | 5 |
| 12 | Smoke test | 5 |
