# 1.2 Yazi 替换内置文件管理器 & Git Panel — 设计文档

> **Date:** 2026-04-01
> **Status:** Approved
> **Scope:** Phase 1.2 of Poltertty roadmap

---

## 目标

用 bundled yazi（TUI 文件管理器）+ delta（diff 渲染器）替换现有 SwiftUI FileBrowser 和 Git Panel，实现：

1. 每个 Workspace 一个独立 yazi 实例，嵌入侧边面板
2. 选中有 git 变更的文件时，yazi preview 用 delta 渲染 diff
3. yazi 中打开文件 → 通过 Ctrl API 在当前 workspace 新开 tab
4. 切换 workspace / worktree 时，yazi 自动 cd 到对应目录
5. yazi/ya/delta 随 App 打包，用户无需安装

---

## 架构总览

```
Poltertty.app/Contents/Resources/
  ├── bin/
  │   ├── yazi          (universal binary)
  │   ├── ya            (yazi CLI companion)
  │   ├── delta         (git diff renderer)
  │   └── poltertty-open (shell script: 文件打开联动)
  └── yazi-config/
      ├── yazi.toml
      ├── theme.toml
      ├── keymap.toml
      └── plugins/
          └── git-diff.yazi/init.lua

YaziSurfaceStore: ObservableObject
  surfaces: [UUID: SurfaceView]
  ├── surface(for: workspaceId, app:, rootDir:) → lazy 创建
  ├── removeSurface(for: workspaceId)           → workspace 删除时调用
  └── cdToDirectory(workspaceId, path)          → Process 调 ya pub dds-cd

YaziPanelView (替代 UnifiedPanelView)
  └── panelToolbar (worktree selector + close)
  └── SurfaceWrapper(surfaceView: store.surface(...))

PolterttyRootView
  └── HStack { WorkspaceSidebar | YaziPanelView | terminalView }
```

---

## Bundled Binary 管理

### 构建流程

- `scripts/fetch-bundled-tools.sh` 从 GitHub Release 下载 yazi/ya/delta 的 macOS universal binary
- Xcode Build Phase "Copy Bundled Tools" 将二进制复制到 `$BUILT_PRODUCTS_DIR/Poltertty.app/Contents/Resources/bin/`
- `.gitignore` 加入下载缓存目录，二进制不入仓

### 运行时路径

```swift
enum BundledTool {
    static var binDir: URL {
        Bundle.main.resourceURL!.appendingPathComponent("bin")
    }
    static var yaziPath: String { binDir.appendingPathComponent("yazi").path }
    static var yaPath: String   { binDir.appendingPathComponent("ya").path }
    static var deltaPath: String { binDir.appendingPathComponent("delta").path }
    static var yaziConfigDir: String {
        Bundle.main.resourceURL!.appendingPathComponent("yazi-config").path
    }
}
```

### 代码签名

- `fetch-bundled-tools.sh` 中用 `codesign --force --sign -` 做 ad-hoc 签名
- CI 正式构建时替换为 Developer ID 签名

---

## YaziSurfaceStore 核心逻辑

```swift
class YaziSurfaceStore: ObservableObject {
    @Published private(set) var surfaces: [UUID: Ghostty.SurfaceView] = [:]

    /// 获取或创建 workspace 对应的 yazi surface
    func surface(for workspaceId: UUID, app: ghostty_app_t, rootDir: String) -> Ghostty.SurfaceView {
        if let existing = surfaces[workspaceId] { return existing }

        var config = Ghostty.SurfaceConfiguration()
        config.command = BundledTool.yaziPath
        config.workingDirectory = rootDir
        config.environmentVariables = [
            "YAZI_CONFIG_HOME": BundledTool.yaziConfigDir,
            "YAZI_DELTA_PATH": BundledTool.deltaPath,
            "PATH": BundledTool.binDir.path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? ""),
        ]

        let surface = Ghostty.SurfaceView(app, baseConfig: config)
        surfaces[workspaceId] = surface
        return surface
    }

    /// workspace 删除时清理
    func removeSurface(for workspaceId: UUID) {
        surfaces.removeValue(forKey: workspaceId)
        // SurfaceView deinit 自动调 ghostty_surface_free
    }

    /// 通过独立进程 IPC 通知 yazi cd（不依赖 surface 输入流）
    func cdToDirectory(_ workspaceId: UUID, path: String) {
        guard surfaces[workspaceId] != nil else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: BundledTool.yaPath)
        task.arguments = ["pub", "dds-cd", "--str", path]
        try? task.run()
    }
}
```

### 生命周期

- **lazy 创建**：首次打开面板时才创建 surface
- **保活**：面板关闭不销毁，再次打开时 yazi 状态保留
- **销毁**：仅在 workspace 删除时，`WorkspaceManager.deleteWorkspace()` 中调 `store.removeSurface()`
- **worktree 切换**：调 `cdToDirectory()`，通过 `ya pub dds-cd` IPC 通知 yazi

---

## YaziPanelView

替代 `UnifiedPanelView`，移除 Files/Git 双 tab，只渲染 yazi surface。

```swift
struct YaziPanelView: View {
    let workspaceId: UUID
    @EnvironmentObject var ghostty: Ghostty.App
    @ObservedObject var store: YaziSurfaceStore
    var rootDir: String

    var body: some View {
        VStack(spacing: 0) {
            panelToolbar
            Divider()
            if let app = ghostty.app {
                let surface = store.surface(for: workspaceId, app: app, rootDir: rootDir)
                Ghostty.SurfaceWrapper(surfaceView: surface)
            }
        }
    }
}
```

### 工具栏

- worktree selector（从旧 PanelTabBar 提取，切换时调 `store.cdToDirectory()`）
- close 按钮（切换面板可见性）
- 去掉 ShortcutHelpView（yazi 有自己的 `?` 帮助）

---

## yazi 内置配置

### yazi.toml

```toml
[opener]
edit = [
    { run = 'poltertty-open "$@"', desc = "Open in Poltertty tab", for = "*" }
]
```

### 文件打开联动

`Resources/bin/poltertty-open`：

```bash
#!/bin/bash
curl -s -X POST "http://localhost:${POLTERTTY_CTRL_PORT}/api/new_tab" \
  -d "{\"command\": \"${EDITOR:-vim} '$1'\"}"
```

- `POLTERTTY_CTRL_PORT` 已在 surface 环境变量中注入（现有 Ctrl API 机制）
- 复用已有 `new_tab` 接口，无需新增 API

### Git diff 预览

自定义 yazi 插件 `Resources/yazi-config/plugins/git-diff.yazi/init.lua`：

```lua
local M = {}
function M:peek()
    local child = Command("git")
        :args({"diff", "HEAD", "--", tostring(self.file.url)})
        :stdout(Command.PIPED)
        :spawn()
    local output = child:wait_with_output()
    if output and #output.stdout > 0 then
        local delta = Command(os.getenv("YAZI_DELTA_PATH") or "delta")
            :stdin(Command.PIPED):stdout(Command.PIPED):spawn()
        -- pipe diff through delta for syntax-highlighted preview
    end
end
return M
```

---

## 删除清单

### 整目录删除

```
macos/Sources/Features/Workspace/FileBrowser/   (13 files)
macos/Sources/Features/Workspace/GitPanel/      (entire directory)
```

### 单文件删除

- `UnifiedPanelView.swift`

### 修改文件（删引用）

| 文件 | 改动 |
|---|---|
| `PolterttyRootView.swift` | 删 `fileBrowserVM`/`gitPanelVM`，换成 `yaziStore`，`UnifiedPanelView` → `YaziPanelView` |
| `WorkspaceManager.swift` | `deleteWorkspace()` 中加 `yaziStore.removeSurface()` |
| `WorkspaceModel.swift` | `fileBrowserVisible` → `panelVisible`，删 `gitPanelWidth` |
| `AppDelegate.swift` | 删 Workspace 菜单中 Git Panel 相关菜单项 |
| `BottomStatusBarView.swift` | 清理 `FileBrowserViewModel`/`GitPanelViewModel` 引用 |

### 新增文件

| 文件 | 说明 |
|---|---|
| `YaziSurfaceStore.swift` | surface 池管理 |
| `YaziPanelView.swift` | 替代 UnifiedPanelView |
| `BundledTool.swift` | bundled binary 路径解析 |
| `scripts/fetch-bundled-tools.sh` | 构建时下载 yazi/ya/delta |
| `Resources/yazi-config/` | 内置 yazi 配置 + git-diff 插件 |
| `Resources/bin/poltertty-open` | 文件打开联动脚本 |

### 保留不动

- `GitWorktreeMonitor.swift` — worktree 列表
- `GitKit/` — worktree 检测
- `WorktreeListView.swift` / `WorktreeCreateForm.swift` — worktree UI

---

## 成功标准

1. 侧边面板打开后显示 yazi，文件树正常浏览，图片预览正常（Kitty 图像协议）
2. 选中有 git 变更的文件，preview 窗格显示 delta 渲染的 diff
3. yazi 中打开文件 → Poltertty 当前 workspace 新开 tab
4. 切换 workspace 后，yazi 自动 cd 到对应 workspace rootDir
5. 切换 worktree 后，yazi 自动 cd 到对应 worktree 路径
6. 每个 workspace 的 yazi 状态独立保留（关闭面板再打开，目录位置不变）
