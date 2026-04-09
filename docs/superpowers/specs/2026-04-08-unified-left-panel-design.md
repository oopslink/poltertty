# 统一左侧面板设计

**日期**: 2026-04-08  
**状态**: 已批准  
**范围**: 将 LazyGit 从浮动 Popup 迁移为左侧侧边栏，与 Yazi 文件浏览器共享同一面板位置

---

## 背景

当前 Yazi 文件浏览器是左侧可拖拽侧边栏（⌥⌘F），LazyGit 是浮动 Popup 覆盖在终端上方（⌥⌘G）。两者快捷键独立、UI 形态不一致，且同时打开时会视觉重叠。

目标：两者共享同一个左侧面板位置，快捷键保持不变，互斥显示，统一工具栏。

---

## 设计决策

| 问题 | 决策 |
|------|------|
| 交互模型 | 快捷键各自保留，面板共享（C 方案） |
| LazyGit 形态 | 变为侧边栏（A 方案） |
| 工具栏 | 共享工具栏 + Tab 指示，Yazi 专属按钮按需隐藏（A 方案） |
| 工作树选择器 | 两个工具共用 |
| 面板宽度 | 两个工具共用同一宽度 |
| 架构方案 | 扩展现有 Yazi 面板（方案 A） |

---

## 架构

### 状态层（PolterttyRootView）

新增枚举：

```swift
enum LeftPanelTool: String {
    case yazi
    case lazygit
}
```

新增状态：

```swift
@State private var leftPanelTool: LeftPanelTool = .yazi
```

现有状态复用（无需新增）：

- `panelVisible: Bool` — 面板显示/隐藏
- `panelExpanded: Bool` — 是否全屏展开
- `yaziPanelWidth: CGFloat` — 面板宽度（两个工具共用，可考虑重命名为 `leftPanelWidth`）

#### 切换逻辑

**⌥⌘F（文件浏览器）：**
- `panelVisible == false` → 打开，`leftPanelTool = .yazi`
- `panelVisible == true && leftPanelTool == .yazi` → 关闭
- `panelVisible == true && leftPanelTool == .lazygit` → 仅切换 tool，面板保持打开

**⌥⌘G（Git）：**
- `panelVisible == false` → 打开，`leftPanelTool = .lazygit`
- `panelVisible == true && leftPanelTool == .lazygit` → 关闭
- `panelVisible == true && leftPanelTool == .yazi` → 仅切换 tool，面板保持打开

#### WorkspaceModel 持久化

新增字段：

```swift
var leftPanelTool: String  // "yazi" | "lazygit"，默认 "yazi"
```

`panelWidth`、`panelVisible` 继续共用，无需拆分。

---

### LazyGitSurfaceStore

新建 `macos/Sources/Features/Workspace/LazyGit/LazyGitSurfaceStore.swift`，参照 `YaziSurfaceStore` 结构：

- 按 `workspaceId: UUID` 延迟创建 `Ghostty.SurfaceView`
- 启动命令：`BundledTool.lazygitPath`，工作目录为 worktree 根路径
- 切换 workspace 时保留进程（不销毁）
- workspace 删除时销毁对应 surface
- 注册到 `WorkspaceManager.shared`

**与 PopupOverlayManager 的关系：**
- `PopupType` 枚举移除 `.lazygit` case，只保留 `.shell`
- `TerminalController.toggleLazygitPopup()` 改为发送 `.toggleLazygitPanel` 通知
- `PopupOverlayManager` 中 `.lazygit` 相关的 `getOrCreateSurface` 逻辑移除

**工作树联动：**  
切换 worktree 时，LazyGit 无需额外处理。LazyGit 感知 git repo 根目录，新 surface 创建时传入正确 working directory 即可。

---

### 工具栏改造

**文件改动：** `YaziPanelToolbar.swift` → `LeftPanelToolbar.swift`（重命名 + 修改）

工具栏布局（从左到右）：

```
[文件浏览器] [Git]   |   [工作树选择器]   |   [布局切换*] [展开]
```

`*` 布局切换按钮（⌥⌘L）仅在 `leftPanelTool == .yazi` 时显示。

**Tab 按钮行为：**
- 点击"文件浏览器" → 等同于 ⌥⌘F 的切换逻辑
- 点击"Git" → 等同于 ⌥⌘G 的切换逻辑
- 当前激活的 Tab 高亮显示

**工作树选择器：**  
两个工具下均显示，逻辑不变：
- 切换 worktree 时对 Yazi 执行 `ya emit-to` cd
- LazyGit 无需额外操作

---

### 组件组装

**文件改动：** `YaziPanelView.swift` → `LeftPanelView.swift`（重命名 + 修改）

```
LeftPanelView
├── LeftPanelToolbar（顶部工具栏）
└── 内容区（根据 leftPanelTool 切换）
    ├── .yazi → YaziSurfaceView（现有逻辑不变）
    └── .lazygit → LazyGitSurfaceView（新建）
```

`LazyGitSurfaceView`：新建，结构参照 `YaziPanelView` 的 surface 渲染部分，从 `LazyGitSurfaceStore` 获取 surface。

**PolterttyRootView 改动：**
- 将 `YaziPanelView` 替换为 `LeftPanelView`，传入 `leftPanelTool` binding
- 面板宽度、展开状态、拖拽分隔线逻辑完全复用
- 监听 `.toggleLazygitPanel` 通知（新增），处理方式类似 `.toggleFileBrowser`

**AppDelegate 改动：**
- `toggleLazygitPopup()` 实现改为发送 `.toggleLazygitPanel` 通知，移除对 `TerminalController.toggleLazygitPopup()` 的调用
- 菜单项文字可从 "Toggle Lazygit Popup" 改为 "Toggle Git Panel"

---

## 文件变更清单

| 操作 | 文件 |
|------|------|
| 新建 | `Features/Workspace/LazyGit/LazyGitSurfaceStore.swift` |
| 新建 | `Features/Workspace/LazyGit/LazyGitSurfaceView.swift` |
| 重命名+修改 | `YaziPanelView.swift` → `LeftPanelView.swift` |
| 重命名+修改 | `YaziPanelToolbar.swift` → `LeftPanelToolbar.swift` |
| 修改 | `PolterttyRootView.swift` |
| 修改 | `AppDelegate.swift` |
| 修改 | `TerminalController.swift` |
| 修改 | `PopupOverlayManager.swift` |
| 修改 | `WorkspaceModel.swift` / `WorkspaceManager.swift` |

---

## 不在范围内

- LazyGit 的展开模式（全屏）：暂不支持，与 Yazi 保持一致即可（共用 ⌥⌘O）
- LazyGit 与 worktree 的深度联动（自动 cd）：留给后续迭代
- Browser 面板（右侧）：不受影响
