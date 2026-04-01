# Yazi 替换内置文件管理器 & Git Panel 实现规划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用 bundled yazi + delta 替换 SwiftUI FileBrowser 和 Git Panel，每个 Workspace 一个独立 yazi 实例嵌入侧边面板。

**Architecture:** 新增 `YaziSurfaceStore`（按 workspaceId 管理 `Ghostty.SurfaceView` 池），`YaziPanelView` 替代 `UnifiedPanelView` 只渲染 yazi surface，`BundledTool` 提供 bundled binary 路径。构建时通过脚本下载 yazi/ya/delta universal binary 打包进 App Resources。删除 `FileBrowser/`、`GitPanel/`、`UnifiedPanelView.swift` 及所有旧 ViewModel 引用。

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit, GhosttyKit (SurfaceView/SurfaceConfiguration), yazi (TUI file manager), delta (diff renderer), Lua (yazi plugin)

---

## 文件变更清单

**新建：**
- `macos/Sources/Helpers/BundledTool.swift`
- `macos/Sources/Features/Workspace/Yazi/YaziSurfaceStore.swift`
- `macos/Sources/Features/Workspace/Yazi/YaziPanelView.swift`
- `macos/Sources/Features/Workspace/Yazi/YaziPanelToolbar.swift`
- `scripts/fetch-bundled-tools.sh`
- `macos/Resources/yazi-config/yazi.toml`
- `macos/Resources/yazi-config/theme.toml`
- `macos/Resources/yazi-config/keymap.toml`
- `macos/Resources/yazi-config/plugins/git-diff.yazi/init.lua`
- `macos/Resources/bin/poltertty-open`
- `macos/Tests/Workspace/YaziSurfaceStoreTests.swift`

**修改：**
- `macos/Sources/Features/Workspace/WorkspaceModel.swift` — `fileBrowserVisible` → `panelVisible`，`fileBrowserWidth` → `panelWidth`，删 `gitPanelWidth`
- `macos/Sources/Features/Workspace/WorkspaceManager.swift` — 删除 FileBrowserViewModel/GitPanelViewModel 管理方法
- `macos/Sources/Features/Workspace/PolterttyRootView.swift` — 用 `YaziPanelView` 替代 `UnifiedPanelView`，删旧 VM 引用
- `macos/Sources/Features/Terminal/TerminalController.swift` — 更新 `persistFileBrowserState`，删 VM 的 pause/resume
- `macos/Sources/App/macOS/AppDelegate.swift` — 删 Git Panel 菜单项，简化 File Browser 切换
- `macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift` — 删除 gitPanelViewModel/fileBrowserViewModel 引用，更新 show_file_browser/show_git_panel 工具
- `macos/Sources/Features/Workspace/SnapshotStore/SnapshotEntry.swift` — 如有引用 fileBrowserWidth 则更新
- `.gitignore` — 加入 bundled binary 缓存目录

**删除：**
- `macos/Sources/Features/Workspace/FileBrowser/` (13 files)
- `macos/Sources/Features/Workspace/GitPanel/` (7 files)
- `macos/Sources/Features/Workspace/UnifiedPanelView.swift`
- `macos/Tests/Workspace/FileBrowserViewModelNavigationTests.swift`

---

## Task 1: BundledTool 路径解析

**Files:**
- Create: `macos/Sources/Helpers/BundledTool.swift`

- [ ] **Step 1: 创建 BundledTool.swift**

```swift
// macos/Sources/Helpers/BundledTool.swift
import Foundation

/// Bundled binary paths for yazi, ya, and delta.
/// These binaries are packaged in Poltertty.app/Contents/Resources/bin/
enum BundledTool {
    static var binDir: URL {
        Bundle.main.resourceURL!.appendingPathComponent("bin")
    }

    static var yaziPath: String {
        binDir.appendingPathComponent("yazi").path
    }

    static var yaPath: String {
        binDir.appendingPathComponent("ya").path
    }

    static var deltaPath: String {
        binDir.appendingPathComponent("delta").path
    }

    static var yaziConfigDir: String {
        Bundle.main.resourceURL!.appendingPathComponent("yazi-config").path
    }

    static var polterttyOpenPath: String {
        binDir.appendingPathComponent("poltertty-open").path
    }

    /// PATH environment variable with bundled bin dir prepended
    static var pathWithBundledBin: String {
        binDir.path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
    }
}
```

- [ ] **Step 2: 验证编译**

Run: `cd macos && xcodebuild build -scheme Ghostty -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Helpers/BundledTool.swift
git commit -m "feat(yazi): add BundledTool path resolver for bundled binaries"
```

---

## Task 2: 构建脚本与 bundled resources

**Files:**
- Create: `scripts/fetch-bundled-tools.sh`
- Create: `macos/Resources/bin/poltertty-open`
- Create: `macos/Resources/yazi-config/yazi.toml`
- Create: `macos/Resources/yazi-config/theme.toml`
- Create: `macos/Resources/yazi-config/keymap.toml`
- Create: `macos/Resources/yazi-config/plugins/git-diff.yazi/init.lua`
- Modify: `.gitignore`

- [ ] **Step 1: 创建 fetch-bundled-tools.sh**

```bash
#!/usr/bin/env bash
# scripts/fetch-bundled-tools.sh
# Downloads yazi, ya, and delta universal binaries for macOS.
# Called by Xcode Build Phase "Copy Bundled Tools".
set -euo pipefail

YAZI_VERSION="${YAZI_VERSION:-0.4.2}"
DELTA_VERSION="${DELTA_VERSION:-0.18.2}"
CACHE_DIR="${PROJECT_DIR:-.}/.bundled-tools-cache"
OUTPUT_DIR="${1:-macos/Resources/bin}"

mkdir -p "$CACHE_DIR" "$OUTPUT_DIR"

# --- yazi + ya ---
YAZI_ARCHIVE="yazi-aarch64-apple-darwin.zip"
YAZI_URL="https://github.com/sxyazi/yazi/releases/download/v${YAZI_VERSION}/${YAZI_ARCHIVE}"
if [ ! -f "$CACHE_DIR/yazi-${YAZI_VERSION}" ]; then
    echo "Downloading yazi v${YAZI_VERSION}..."
    curl -fSL "$YAZI_URL" -o "$CACHE_DIR/${YAZI_ARCHIVE}"
    unzip -o "$CACHE_DIR/${YAZI_ARCHIVE}" -d "$CACHE_DIR/yazi-extract"
    cp "$CACHE_DIR/yazi-extract/yazi-aarch64-apple-darwin/yazi" "$OUTPUT_DIR/yazi"
    cp "$CACHE_DIR/yazi-extract/yazi-aarch64-apple-darwin/ya" "$OUTPUT_DIR/ya"
    chmod +x "$OUTPUT_DIR/yazi" "$OUTPUT_DIR/ya"
    touch "$CACHE_DIR/yazi-${YAZI_VERSION}"
fi

# --- delta ---
DELTA_ARCHIVE="delta-${DELTA_VERSION}-aarch64-apple-darwin.tar.gz"
DELTA_URL="https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/${DELTA_ARCHIVE}"
if [ ! -f "$CACHE_DIR/delta-${DELTA_VERSION}" ]; then
    echo "Downloading delta v${DELTA_VERSION}..."
    curl -fSL "$DELTA_URL" -o "$CACHE_DIR/${DELTA_ARCHIVE}"
    tar xzf "$CACHE_DIR/${DELTA_ARCHIVE}" -C "$CACHE_DIR"
    cp "$CACHE_DIR/delta-${DELTA_VERSION}-aarch64-apple-darwin/delta" "$OUTPUT_DIR/delta"
    chmod +x "$OUTPUT_DIR/delta"
    touch "$CACHE_DIR/delta-${DELTA_VERSION}"
fi

# --- ad-hoc code signing ---
for bin in "$OUTPUT_DIR/yazi" "$OUTPUT_DIR/ya" "$OUTPUT_DIR/delta"; do
    if [ -f "$bin" ]; then
        codesign --force --sign - "$bin" 2>/dev/null || true
    fi
done

echo "Bundled tools ready in $OUTPUT_DIR"
```

- [ ] **Step 2: 创建 poltertty-open 脚本**

```bash
#!/usr/bin/env bash
# macos/Resources/bin/poltertty-open
# Called by yazi when user opens a file. Opens a new tab in the current workspace
# via the Ctrl API.
set -euo pipefail

FILE_PATH="$1"

if [ -z "${POLTERTTY_CTRL_PORT:-}" ]; then
    # Fallback: open with default system app
    open "$FILE_PATH"
    exit 0
fi

curl -s -X POST "http://localhost:${POLTERTTY_CTRL_PORT}/api/new_tab" \
    -H "Content-Type: application/json" \
    -d "{\"command\": \"${EDITOR:-vim} '${FILE_PATH}'\"}" >/dev/null 2>&1 || open "$FILE_PATH"
```

- [ ] **Step 3: 创建 yazi.toml**

```toml
# macos/Resources/yazi-config/yazi.toml
# Poltertty bundled yazi configuration

[manager]
show_hidden = false
sort_by = "natural"
sort_sensitive = false
sort_reverse = false
sort_dir_first = true

[opener]
edit = [
    { run = 'poltertty-open "$@"', desc = "Open in Poltertty tab", for = "unix" },
]
open = [
    { run = 'open "$@"', desc = "Open with system default", for = "macos" },
]

[plugin]
prepend_previewers = [
    { mime = "text/*", run = "git-diff" },
]
```

- [ ] **Step 4: 创建 theme.toml**

```toml
# macos/Resources/yazi-config/theme.toml
# Dark theme matching Poltertty's default appearance
# Inherits yazi defaults; override only what's needed for consistency

[manager]
border_style = { fg = "gray" }

[status]
separator_style = { fg = "gray" }
```

- [ ] **Step 5: 创建 keymap.toml**

```toml
# macos/Resources/yazi-config/keymap.toml
# Poltertty-specific key overrides (inherits yazi defaults)

[[manager.keymap]]
on   = [ "<Enter>" ]
run  = "open"
desc = "Open file in Poltertty tab"
```

- [ ] **Step 6: 创建 git-diff yazi 插件**

```lua
-- macos/Resources/yazi-config/plugins/git-diff.yazi/init.lua
-- Preview plugin: shows git diff with delta syntax highlighting
-- for files with uncommitted changes.

local M = {}

function M:peek()
    local url = tostring(self.file.url)

    -- Check if file has git changes
    local status = Command("git")
        :args({ "status", "--porcelain", "--", url })
        :stdout(Command.PIPED)
        :stderr(Command.NULL)
        :output()

    if not status or #status.stdout == 0 then
        -- No git changes: fall through to default previewer
        require("code"):peek(self)
        return
    end

    -- Get the diff
    local diff = Command("git")
        :args({ "diff", "HEAD", "--", url })
        :stdout(Command.PIPED)
        :stderr(Command.NULL)
        :output()

    if not diff or #diff.stdout == 0 then
        require("code"):peek(self)
        return
    end

    -- Pipe through delta for syntax highlighting
    local delta_path = os.getenv("YAZI_DELTA_PATH") or "delta"
    local colored = Command(delta_path)
        :args({ "--paging=never", "--width=" .. tostring(self.area.w) })
        :stdin(Command.PIPED)
        :stdout(Command.PIPED)
        :stderr(Command.NULL)
        :spawn()

    if colored then
        colored:write_all(diff.stdout)
        colored:flush()
        local output = colored:wait_with_output()
        if output and #output.stdout > 0 then
            ya.preview_widgets(self, { ui.Text.parse(output.stdout) })
            return
        end
    end

    -- Fallback to raw diff
    ya.preview_widgets(self, { ui.Text(diff.stdout) })
end

function M:seek(units)
    require("code"):seek(units)
end

return M
```

- [ ] **Step 7: 更新 .gitignore**

在 `.gitignore` 末尾添加：

```
# Bundled tools download cache
.bundled-tools-cache/
```

- [ ] **Step 8: 设置可执行权限并 commit**

```bash
chmod +x scripts/fetch-bundled-tools.sh
chmod +x macos/Resources/bin/poltertty-open
git add scripts/fetch-bundled-tools.sh macos/Resources/bin/poltertty-open \
    macos/Resources/yazi-config/ .gitignore
git commit -m "feat(yazi): add build script, bundled configs, and git-diff plugin"
```

---

## Task 3: YaziSurfaceStore

**Files:**
- Create: `macos/Sources/Features/Workspace/Yazi/YaziSurfaceStore.swift`
- Test: `macos/Tests/Workspace/YaziSurfaceStoreTests.swift`

- [ ] **Step 1: 创建 YaziSurfaceStore.swift**

```swift
// macos/Sources/Features/Workspace/Yazi/YaziSurfaceStore.swift
import Foundation
import GhosttyKit

/// Manages one yazi terminal surface per workspace.
/// Surfaces are lazily created on first panel open and kept alive
/// until the workspace is deleted.
class YaziSurfaceStore: ObservableObject {
    @Published private(set) var surfaces: [UUID: Ghostty.SurfaceView] = [:]

    /// Get or create the yazi surface for a workspace.
    /// - Parameters:
    ///   - workspaceId: The workspace UUID
    ///   - app: The Ghostty app instance for creating surfaces
    ///   - rootDir: The workspace root directory (expanded path)
    /// - Returns: The existing or newly created SurfaceView running yazi
    @MainActor
    func surface(for workspaceId: UUID, app: ghostty_app_t, rootDir: String) -> Ghostty.SurfaceView {
        if let existing = surfaces[workspaceId] {
            return existing
        }

        var config = Ghostty.SurfaceConfiguration()
        config.command = BundledTool.yaziPath
        config.workingDirectory = rootDir
        config.environmentVariables = [
            "YAZI_CONFIG_HOME": BundledTool.yaziConfigDir,
            "YAZI_DELTA_PATH": BundledTool.deltaPath,
            "PATH": BundledTool.pathWithBundledBin,
        ]

        let surface = Ghostty.SurfaceView(app, baseConfig: config)
        surfaces[workspaceId] = surface
        return surface
    }

    /// Remove and destroy the yazi surface for a workspace.
    /// Called when a workspace is deleted.
    func removeSurface(for workspaceId: UUID) {
        surfaces.removeValue(forKey: workspaceId)
        // SurfaceView.deinit calls ghostty_surface_free automatically
    }

    /// Notify yazi to change directory via ya pub-sub IPC.
    /// Uses a separate Process instead of sendText to avoid
    /// interfering with yazi's TUI input.
    func cdToDirectory(_ workspaceId: UUID, path: String) {
        guard surfaces[workspaceId] != nil else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: BundledTool.yaPath)
        task.arguments = ["pub", "dds-cd", "--str", path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    /// Check if a surface exists for the given workspace.
    func hasSurface(for workspaceId: UUID) -> Bool {
        surfaces[workspaceId] != nil
    }
}
```

- [ ] **Step 2: 验证编译**

Run: `cd macos && xcodebuild build -scheme Ghostty -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/Yazi/YaziSurfaceStore.swift
git commit -m "feat(yazi): add YaziSurfaceStore for per-workspace surface management"
```

---

## Task 4: YaziPanelView 和工具栏

**Files:**
- Create: `macos/Sources/Features/Workspace/Yazi/YaziPanelToolbar.swift`
- Create: `macos/Sources/Features/Workspace/Yazi/YaziPanelView.swift`

- [ ] **Step 1: 创建 YaziPanelToolbar.swift**

从 `UnifiedPanelView.swift` 的 `PanelTabBar` 提取 worktree selector 和 close 按钮，去掉 tab 切换逻辑。

```swift
// macos/Sources/Features/Workspace/Yazi/YaziPanelToolbar.swift
import SwiftUI

struct YaziPanelToolbar: View {
    @ObservedObject var yaziStore: YaziSurfaceStore
    var workspaceId: UUID?
    var worktreeMonitor: GitWorktreeMonitor?
    var currentRootDir: String
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "folder")
                .font(.system(size: 14))
                .foregroundStyle(Color(nsColor: .controlAccentColor))
                .frame(width: 28, height: 28)
                .background(Color(nsColor: .controlAccentColor).opacity(0.15))
                .cornerRadius(5)

            // Worktree selector
            if let monitor = worktreeMonitor, !monitor.worktrees.isEmpty {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1, height: 14)
                    .padding(.horizontal, 4)
                worktreeSelector(monitor: monitor)
            }

            Spacer()

            // Close panel button
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Close Panel")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func worktreeSelector(monitor: GitWorktreeMonitor) -> some View {
        let effectivePath = URL(fileURLWithPath: currentRootDir).standardized.path
        let worktrees = monitor.worktrees
        let currentWTPath = worktrees.first {
            URL(fileURLWithPath: $0.path).standardized.path == effectivePath
        }?.path

        let branchLabel: String = {
            guard let path = currentWTPath,
                  let wt = worktrees.first(where: { $0.path == path }) else {
                return URL(fileURLWithPath: currentRootDir).lastPathComponent
            }
            if wt.isMain { return "Main" }
            return wt.branch ?? URL(fileURLWithPath: wt.path).lastPathComponent
        }()

        if worktrees.count > 1 {
            Menu {
                ForEach(worktrees) { wt in
                    let isActive = wt.path == currentWTPath
                    Button {
                        let targetPath = wt.isMain
                            ? (worktrees.first(where: { $0.isMain })?.path ?? currentRootDir)
                            : wt.path
                        if let wsId = workspaceId {
                            yaziStore.cdToDirectory(wsId, path: targetPath)
                        }
                    } label: {
                        Label {
                            Text(wt.isMain ? "Main" : (wt.branch ?? URL(fileURLWithPath: wt.path).lastPathComponent))
                        } icon: {
                            if isActive { Image(systemName: "checkmark") }
                        }
                    }
                    .disabled(isActive)
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10))
                    Text(branchLabel)
                        .font(.system(size: 11))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Switch Worktree")
        } else {
            HStack(spacing: 2) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10))
                Text(branchLabel)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 2: 创建 YaziPanelView.swift**

```swift
// macos/Sources/Features/Workspace/Yazi/YaziPanelView.swift
import SwiftUI
import GhosttyKit

struct YaziPanelView: View {
    let workspaceId: UUID?
    @EnvironmentObject var ghostty: Ghostty.App
    @ObservedObject var yaziStore: YaziSurfaceStore
    var rootDir: String
    var worktreeMonitor: GitWorktreeMonitor?
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            YaziPanelToolbar(
                yaziStore: yaziStore,
                workspaceId: workspaceId,
                worktreeMonitor: worktreeMonitor,
                currentRootDir: rootDir,
                onClose: onClose
            )
            Divider()

            if let wsId = workspaceId, let app = ghostty.app {
                let surface = yaziStore.surface(for: wsId, app: app, rootDir: rootDir)
                Ghostty.SurfaceWrapper(surfaceView: surface)
            } else {
                noWorkspaceView
            }
        }
    }

    private var noWorkspaceView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "folder")
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No workspace selected")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
```

- [ ] **Step 3: 验证编译**

Run: `cd macos && xcodebuild build -scheme Ghostty -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Workspace/Yazi/YaziPanelToolbar.swift \
    macos/Sources/Features/Workspace/Yazi/YaziPanelView.swift
git commit -m "feat(yazi): add YaziPanelView and YaziPanelToolbar"
```

---

## Task 5: WorkspaceModel 字段迁移

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceModel.swift`

- [ ] **Step 1: 重命名字段**

在 `WorkspaceModel.swift` 中：

1. `fileBrowserVisible: Bool` → `panelVisible: Bool`（保留默认值 `false`）
2. `fileBrowserWidth: CGFloat` → `panelWidth: CGFloat`（保留默认值 `260`）
3. 删除 `gitPanelWidth: CGFloat = 600`

更新 `CodingKeys`：
- `case fileBrowserVisible` → `case panelVisible = "fileBrowserVisible"`（保持 JSON key 向后兼容）
- `case fileBrowserWidth` → `case panelWidth = "fileBrowserWidth"`（保持 JSON key 向后兼容）
- 删除 `case gitPanelWidth`

更新 `init(from decoder:)`：
- `fileBrowserVisible = ...` → `panelVisible = try container.decodeIfPresent(Bool.self, forKey: .panelVisible) ?? false`
- `fileBrowserWidth = ...` → `panelWidth = try container.decodeIfPresent(CGFloat.self, forKey: .panelWidth) ?? 260`
- 删除 `gitPanelWidth = ...`

- [ ] **Step 2: Commit（此时可能不编译，和 Task 6 一起修复）**

不单独 commit，继续 Task 6。

---

## Task 6: WorkspaceManager 迁移

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceManager.swift`

- [ ] **Step 1: 删除 FileBrowserViewModel/GitPanelViewModel 管理代码**

删除以下内容（约 lines 14-47）：

```swift
// 删除这些：
private var fileBrowserViewModels: [UUID: FileBrowserViewModel] = [:]
private var gitPanelViewModels: [UUID: GitPanelViewModel] = [:]

func fileBrowserViewModel(for workspaceId: UUID) -> FileBrowserViewModel { ... }
func removeFileBrowserViewModel(for workspaceId: UUID) { ... }
@MainActor func gitPanelViewModel(for workspaceId: UUID) -> GitPanelViewModel { ... }
func removeGitPanelViewModel(for workspaceId: UUID) { ... }
```

- [ ] **Step 2: 更新 delete(id:) 方法**

在 `delete(id:)` 方法中（约 line 212-213），将：

```swift
removeFileBrowserViewModel(for: id)
removeGitPanelViewModel(for: id)
```

替换为：

```swift
yaziSurfaceStore?.removeSurface(for: id)
```

并在 `WorkspaceManager` 类中添加 store 引用：

```swift
/// Set by PolterttyRootView when the store is created
weak var yaziSurfaceStore: YaziSurfaceStore?
```

- [ ] **Step 3: 验证编译状态**

此时 PolterttyRootView、TerminalController、CtrlToolHandler、AppDelegate 中仍有旧引用，编译会报错。继续 Task 7-9 修复。

---

## Task 7: PolterttyRootView 大迁移

**Files:**
- Modify: `macos/Sources/Features/Workspace/PolterttyRootView.swift`

- [ ] **Step 1: 替换 ViewModel 声明**

在属性声明区域（约 lines 58-61），将：

```swift
@ObservedObject private var fileBrowserVM: FileBrowserViewModel
@ObservedObject private var gitPanelVM: GitPanelViewModel
```

替换为：

```swift
@StateObject private var yaziStore = YaziSurfaceStore()
```

- [ ] **Step 2: 删除旧 state 变量**

删除这些 `@State` 变量（约 lines 51, 53）：

```swift
@State private var activePanelTab: PanelTab = .files
```

- [ ] **Step 3: 更新 init()**

删除 init 中的 fileBrowserVM 和 gitPanelVM 初始化代码（约 lines 103-129 的两个 if-else 块）。

在 init 末尾添加：

```swift
// Wire up yaziStore reference for WorkspaceManager cleanup
WorkspaceManager.shared.yaziSurfaceStore = yaziStore
```

注意：由于 `yaziStore` 是 `@StateObject`，它在 init 中还不可用。改为在 `.onAppear` 中设置。

- [ ] **Step 4: 替换面板可见性逻辑**

当前面板可见性用 `fileBrowserVM.isVisible`。需要替换为本地 state 绑定到 WorkspaceModel：

添加：

```swift
@State private var panelVisible: Bool = false
```

并在 `.onAppear` 中从 workspace 读取初始值：

```swift
if let wsId = workspaceId, let ws = WorkspaceManager.shared.workspace(for: wsId) {
    panelVisible = ws.panelVisible
}
WorkspaceManager.shared.yaziSurfaceStore = yaziStore
```

- [ ] **Step 5: 替换 unifiedPanelWidth 计算属性**

将：

```swift
private var unifiedPanelWidth: CGFloat {
    switch activePanelTab {
    case .git:
        return gitPanelVM.gitPanelWidth
    case .files:
        if fileBrowserVM.showPreviewPanel {
            return fileBrowserVM.previewTotalWidth
        }
        return fileBrowserVM.panelWidth
    }
}
```

替换为：

```swift
@State private var yaziPanelWidth: CGFloat = 260

private var effectivePanelWidth: CGFloat {
    yaziPanelWidth
}
```

初始值在 `.onAppear` 中从 workspace 加载：

```swift
if let wsId = workspaceId, let ws = WorkspaceManager.shared.workspace(for: wsId) {
    panelVisible = ws.panelVisible
    yaziPanelWidth = ws.panelWidth
}
```

- [ ] **Step 6: 替换 body 中的 UnifiedPanelView**

将 body 中的整个 UnifiedPanelView 区域（约 lines 214-259）：

```swift
// Unified Panel (File Browser + Git Tab)
if fileBrowserVM.isVisible {
    if fileBrowserVM.isPreviewFullscreen {
        UnifiedPanelView(...)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
        UnifiedPanelView(...)
            .frame(width: unifiedPanelWidth)
        unifiedPanelDivider
        terminalAreaView
    }
} else {
    terminalAreaView
}
```

替换为：

```swift
// Yazi Panel
if panelVisible {
    YaziPanelView(
        workspaceId: workspaceId,
        yaziStore: yaziStore,
        rootDir: currentWorkspaceRootDir,
        worktreeMonitor: worktreeMonitor,
        onClose: { panelVisible = false }
    )
    .frame(width: effectivePanelWidth)

    yaziPanelDivider

    terminalAreaView
} else {
    terminalAreaView
}
```

其中 `currentWorkspaceRootDir` 是：

```swift
private var currentWorkspaceRootDir: String {
    guard let wsId = workspaceId,
          let ws = WorkspaceManager.shared.workspace(for: wsId) else { return "" }
    return ws.rootDirExpanded
}
```

- [ ] **Step 7: 替换面板 divider**

将 `unifiedPanelDivider`（约 lines 484-511）中引用 `fileBrowserVM` 的部分改为操作 `yaziPanelWidth`：

```swift
private var yaziPanelDivider: some View {
    Rectangle()
        .fill(Color(nsColor: .separatorColor))
        .frame(width: 1)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle().inset(by: -4))
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let newWidth = yaziPanelWidth + value.translation.width
                    yaziPanelWidth = max(160, min(600, newWidth))
                }
        )
}
```

- [ ] **Step 8: 替换通知处理**

将 `.toggleFileBrowser` 处理（约 lines 336-343）：

```swift
.onReceive(NotificationCenter.default.publisher(for: .toggleFileBrowser)) { _ in
    panelVisible.toggle()
}
```

删除 `.toggleGitPanel` 处理（约 lines 344-361，整块删掉）。

删除 `.task(id: fileBrowserVM.effectiveRootDir)` 块（约 lines 363-368，不再需要加载 git repo）。

- [ ] **Step 9: 更新 snapshot 属性**

将（约 lines 516-517）：

```swift
var currentFileBrowserVisible: Bool { fileBrowserVM.isVisible }
var currentFileBrowserWidth: CGFloat { fileBrowserVM.panelWidth }
```

替换为：

```swift
var currentFileBrowserVisible: Bool { panelVisible }
var currentFileBrowserWidth: CGFloat { yaziPanelWidth }
```

- [ ] **Step 10: 删除旧 Notification.Name**

在文件顶部的 `Notification.Name` 扩展中，删除：

```swift
static let toggleGitPanel = Notification.Name("poltertty.toggleGitPanel")
```

保留 `toggleFileBrowser`（用于切换 yazi 面板）。

- [ ] **Step 11: Commit（和 Task 5-6 一起）**

不单独 commit，继续 Task 8。

---

## Task 8: TerminalController 迁移

**Files:**
- Modify: `macos/Sources/Features/Terminal/TerminalController.swift`

- [ ] **Step 1: 更新 persistFileBrowserState**

将 `persistFileBrowserState(for:)` 方法（约 line 721-729）改为直接操作 WorkspaceModel 字段：

```swift
private func persistPanelState(for workspaceId: UUID) {
    guard var ws = WorkspaceManager.shared.workspace(for: workspaceId) else { return }
    // Panel state is managed by PolterttyRootView via @State.
    // Read from the root view's exposed properties.
    if let rootView = findPolterttyRootView() {
        ws.panelVisible = rootView.currentFileBrowserVisible
        ws.panelWidth = rootView.currentFileBrowserWidth
    }
    WorkspaceManager.shared.update(ws)
}
```

更新所有调用处将 `persistFileBrowserState` 改为 `persistPanelState`（约 lines 627, 1940）。

- [ ] **Step 2: 删除 windowDidBecomeKey/windowDidResignKey 中的 VM 引用**

在 `windowDidBecomeKey`（约 lines 2006-2012），删除：

```swift
if let wsId = workspaceId {
    let vm = WorkspaceManager.shared.fileBrowserViewModel(for: wsId)
    vm.resume()
    vm.objectWillChange.send()
}
```

在 `windowDidResignKey`（约 lines 2018-2020），删除：

```swift
if let wsId = workspaceId {
    WorkspaceManager.shared.fileBrowserViewModel(for: wsId).pause()
}
```

- [ ] **Step 3: Commit（和 Task 5-7 一起）**

不单独 commit，继续 Task 9。

---

## Task 9: AppDelegate 和 CtrlToolHandler 迁移

**Files:**
- Modify: `macos/Sources/App/macOS/AppDelegate.swift`
- Modify: `macos/Sources/Features/Agent/CtrlServer/CtrlToolHandler.swift`

- [ ] **Step 1: 更新 AppDelegate 菜单**

删除 Git Panel 菜单项（约 lines 1205-1207）：

```swift
// 删除这三行：
let toggleGitPanel = NSMenuItem(title: "Toggle Git Tab", action: #selector(toggleGitPanel(_:)), keyEquivalent: "g")
toggleGitPanel.keyEquivalentModifierMask = [.command, .option]
workspaceMenu.addItem(toggleGitPanel)
```

更新 `toggleFileBrowser(_:)` 方法（约 lines 1298-1303），不再用 FileBrowserViewModel：

```swift
@objc func toggleFileBrowser(_ sender: Any?) {
    NotificationCenter.default.post(name: .toggleFileBrowser, object: nil)
}
```

删除 `toggleGitPanel(_:)` 方法（约 lines 1315-1317）。

- [ ] **Step 2: 更新 CtrlToolHandler**

在 `CtrlToolHandler.swift` 中：

1. 删除引用 `fileBrowserViewModel(for:)` 和 `gitPanelViewModel(for:)` 的诊断代码（约 lines 516-524）。替换为简单的 workspace 状态：

```swift
var panelState = "no_wsId"
if let id = wsId, let ws = WorkspaceManager.shared.workspace(for: id) {
    panelState = "{\"panelVisible\":\(ws.panelVisible)}"
}
```

2. 更新 `callShowFileBrowser` / `callShowGitPanel` 方法（约 lines 768-784）。`callShowGitPanel` 直接调 `callShowFileBrowser`（因为只有一个面板了）：

```swift
private func callShowFileBrowser(arguments: [String: Any]) async throws -> String {
    await MainActor.run {
        NotificationCenter.default.post(name: .toggleFileBrowser, object: nil)
    }
    return #"{"ok":true}"#
}

private func callShowGitPanel(arguments: [String: Any]) async throws -> String {
    // Git panel merged into yazi; toggle the same panel
    return try await callShowFileBrowser(arguments: arguments)
}
```

3. 删除约 lines 552-579 中对 `fileBrowserVM` 和 `gitPanelVM` 的操作代码。

- [ ] **Step 3: Commit（和 Task 5-8 一起，做为一次大 commit）**

不单独 commit，继续 Task 10。

---

## Task 10: 删除旧文件并验证编译

**Files:**
- Delete: `macos/Sources/Features/Workspace/FileBrowser/` (entire directory, 13 files)
- Delete: `macos/Sources/Features/Workspace/GitPanel/` (entire directory, 7 files)
- Delete: `macos/Sources/Features/Workspace/UnifiedPanelView.swift`
- Delete: `macos/Tests/Workspace/FileBrowserViewModelNavigationTests.swift`

- [ ] **Step 1: 删除旧目录和文件**

```bash
rm -rf macos/Sources/Features/Workspace/FileBrowser/
rm -rf macos/Sources/Features/Workspace/GitPanel/
rm macos/Sources/Features/Workspace/UnifiedPanelView.swift
rm macos/Tests/Workspace/FileBrowserViewModelNavigationTests.swift
```

- [ ] **Step 2: 从 Xcode project 文件中移除引用**

如果使用 Xcode project file（`.xcodeproj`），需要手动打开 Xcode 删除对应文件引用。如果使用 Swift Package Manager，文件系统删除即可。

检查是否有 Xcode project：

```bash
ls macos/*.xcodeproj 2>/dev/null || echo "No xcodeproj, using SPM"
```

- [ ] **Step 3: 验证编译**

```bash
cd macos && xcodebuild build -scheme Ghostty -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED

如果编译失败，根据错误信息逐一修复漏掉的引用。常见的漏引用点：
- `PanelTab` enum（定义在 `UnifiedPanelView.swift` 中，已随文件删除）
- `FileBrowserViewModel` 类型引用
- `GitPanelViewModel` 类型引用
- `.toggleGitPanel` notification name

- [ ] **Step 4: Commit 全部迁移**

```bash
git add -A
git commit -m "feat(yazi): replace FileBrowser and GitPanel with bundled yazi + delta

- Add YaziSurfaceStore for per-workspace yazi surface management
- Add YaziPanelView replacing UnifiedPanelView
- Remove FileBrowser/ (13 files), GitPanel/ (7 files), UnifiedPanelView
- Update WorkspaceModel: fileBrowserVisible → panelVisible, remove gitPanelWidth
- Update WorkspaceManager, PolterttyRootView, TerminalController, AppDelegate
- Update CtrlToolHandler to remove old VM references"
```

---

## Task 11: 手动测试验证

- [ ] **Step 1: 下载 bundled tools**

```bash
./scripts/fetch-bundled-tools.sh macos/Resources/bin
```

- [ ] **Step 2: 启动 App 并验证以下场景**

1. 创建一个 Workspace，点击 File Browser 按钮 → 面板打开，显示 yazi 文件树
2. 在 yazi 中浏览文件，图片文件能预览（Kitty 图像协议）
3. 修改一个有 git 变更的文件，选中后 preview 显示 delta 渲染的 diff
4. 在 yazi 中按 Enter 打开文件 → Poltertty 新开 tab
5. 切换到另一个 Workspace → yazi 自动 cd 到新 Workspace 目录
6. 关闭面板再打开 → yazi 状态保留（目录位置不变）
7. 如果有多个 worktree，通过面板工具栏切换 → yazi 自动 cd 到 worktree 路径
8. 删除一个 Workspace → 对应的 yazi surface 被清理
9. `Cmd+Option+F` 快捷键切换面板可见性

- [ ] **Step 3: Commit 任何修复**

```bash
git add -A
git commit -m "fix(yazi): address issues found during manual testing"
```
