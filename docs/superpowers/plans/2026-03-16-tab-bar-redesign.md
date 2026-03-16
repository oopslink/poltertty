# Tab Bar Redesign Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用自定义 SwiftUI tab bar 替代 macOS 原生 tab 机制，窗口标题只显示 workspace 名称，tab bar 在终端区域上方条件显示（多 tab 时才显示）。

**Architecture:** 新增 `TabBarViewModel`（ObservableObject）持有 `[TabItem]` 数组和 `[UUID: SurfaceView]` 字典，作为 SurfaceView 的唯一所有者。`PolterttyRootView` 保留泛型 `terminalView` 参数作为兜底，同时新增 `tabBarViewModel` 参数；在终端区域上方条件渲染 `TerminalTabBar`，切换时替换展示的 SurfaceView。每个 tab 持有独立的 `Ghostty.SurfaceView`（不含 split tree，poltertty tab 模式下每 tab 对应一个完整 terminal surface）。原生 NSWindow tab group 机制在 poltertty 模式下绕过，代码保留用于上游合并。

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit, Ghostty C ABI (surface creation via `ghostty_app`)

---

## Chunk 1: 数据模型与标题栏

### Task 1: TabItem 和 TabBarViewModel

**Files:**
- Create: `macos/Sources/Features/Workspace/TabBar/TabBarViewModel.swift`

- [ ] **Step 1: 创建 TabBar 目录并新建 TabBarViewModel.swift**

```bash
mkdir -p macos/Sources/Features/Workspace/TabBar
```

创建文件内容：

```swift
import SwiftUI

/// 代表单个 terminal tab 的数据
struct TabItem: Identifiable {
    let id: UUID
    var title: String
    var titleLocked: Bool   // true = 用户手动设置，忽略 PTY 变化
    var isActive: Bool
    let surfaceId: UUID     // 对应 surfaces 字典的 key（非强引用）

    init(title: String, surfaceId: UUID) {
        self.id = UUID()
        self.title = title
        self.titleLocked = false
        self.isActive = false
        self.surfaceId = surfaceId
    }
}

/// 管理所有 tab 状态，作为 SurfaceView 实例的唯一所有者
@MainActor
final class TabBarViewModel: ObservableObject {
    @Published var tabs: [TabItem] = []
    @Published var activeTabId: UUID?
    // @Published 确保 surfaces 变化触发 UI 更新（activeSurface 是计算属性）
    @Published private(set) var surfaces: [UUID: Ghostty.SurfaceView] = [:]

    /// 当前活跃的 SurfaceView
    var activeSurface: Ghostty.SurfaceView? {
        guard let activeTabId,
              let tab = tabs.first(where: { $0.id == activeTabId })
        else { return nil }
        return surfaces[tab.surfaceId]
    }

    // MARK: - Tab 操作

    /// 添加一个新 tab，传入已创建好的 SurfaceView
    func addTab(surface: Ghostty.SurfaceView, title: String = "Terminal") {
        let surfaceId = UUID()
        surfaces[surfaceId] = surface
        var item = TabItem(title: title, surfaceId: surfaceId)
        item.isActive = true
        for i in tabs.indices { tabs[i].isActive = false }
        tabs.append(item)
        activeTabId = item.id
    }

    /// 切换到指定 tab
    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        for i in tabs.indices {
            tabs[i].isActive = (tabs[i].id == id)
        }
        activeTabId = id
    }

    /// 关闭指定 tab，返回需要清理的 surfaceId
    @discardableResult
    func closeTab(_ id: UUID) -> UUID? {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return nil }
        let surfaceId = tabs[idx].surfaceId
        tabs.remove(at: idx)
        surfaces.removeValue(forKey: surfaceId)
        if !tabs.isEmpty {
            let newIdx = min(idx, tabs.count - 1)
            selectTab(tabs[newIdx].id)
        } else {
            activeTabId = nil
        }
        return surfaceId
    }

    /// 移动 tab（拖拽重排）
    func moveTab(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
    }

    /// 更新 PTY 标题（仅当 titleLocked == false 时生效）
    func updateTitle(forSurfaceId surfaceId: UUID, title: String) {
        guard let idx = tabs.firstIndex(where: { $0.surfaceId == surfaceId }),
              !tabs[idx].titleLocked
        else { return }
        tabs[idx].title = title
    }

    /// 手动重命名（空字符串 = 解锁，恢复 PTY 标题）
    func renameTab(_ id: UUID, title: String) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        if title.isEmpty {
            tabs[idx].titleLocked = false
        } else {
            tabs[idx].title = title
            tabs[idx].titleLocked = true
        }
    }

    // MARK: - 持久化支持

    struct PersistedTab: Codable {
        let title: String
        let titleLocked: Bool
    }

    var persistedTabs: [PersistedTab] {
        tabs.map { PersistedTab(title: $0.title, titleLocked: $0.titleLocked) }
    }

    var activeTabIndex: Int? {
        guard let activeTabId else { return nil }
        return tabs.firstIndex(where: { $0.id == activeTabId })
    }
}
```

- [ ] **Step 2: 构建验证**

```bash
make check 2>&1 | head -40
```

期望：无编译错误。

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/TabBar/TabBarViewModel.swift
git commit -m "feat(tab-bar): add TabItem and TabBarViewModel data models"
```

---

### Task 2: 修改窗口标题逻辑

**Files:**
- Modify: `macos/Sources/Features/Terminal/BaseTerminalController.swift`（`applyTitleToWindow()` 方法，约 843-862 行）

`WorkspaceModel.isTemporary` 字段已存在（`WorkspaceModel.swift:17`）。

- [ ] **Step 1: 修改 `applyTitleToWindow()`**

找到 `applyTitleToWindow()` 方法末尾的 workspace prefix 逻辑，替换为：

```swift
// poltertty 模式：标题只显示 workspace 名称
if let wsId = (self as? TerminalController)?.workspaceId,
   let workspace = WorkspaceManager.shared.workspace(for: wsId) {
    // 临时 workspace 或无名称时显示 "Poltertty"
    window.title = workspace.isTemporary ? "Poltertty" : workspace.name
} else if (self as? TerminalController)?.workspaceId != nil {
    // workspaceId 有值但 workspace 不存在（已被删除）
    window.title = "Poltertty"
} else {
    // 无 workspace context（非 poltertty 模式）：保留原始终端标题
    window.title = baseTitle
}
```

- [ ] **Step 2: 构建验证**

```bash
make check 2>&1 | head -40
```

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Terminal/BaseTerminalController.swift
git commit -m "feat(tab-bar): window title shows workspace name only"
```

---

## Chunk 2: Tab Bar UI 组件

### Task 3: TerminalTabItem（单个 tab 按钮）

**Files:**
- Create: `macos/Sources/Features/Workspace/TabBar/TerminalTabItem.swift`

**注意：**
- 正确的双击手势需用 `simultaneousGesture`，参考项目中 `FileNodeRow.swift` 的模式
- Escape 键取消重命名用 `.onKeyPress(.escape)`（SwiftUI macOS 13+）
- 关闭按钮只在 `isHovered && !isRenaming` 时显示

```swift
import SwiftUI

struct TerminalTabItem: View {
    let tab: TabItem
    let accentColor: Color
    let isLastTab: Bool        // 最后一个 tab 时不显示关闭按钮
    let onSelect: () -> Void
    let onClose: () -> Void
    let onRename: (String) -> Void
    let onCloseOthers: () -> Void

    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 4) {
                if isRenaming {
                    TextField("", text: $renameText)
                        .font(.system(size: 12))
                        .textFieldStyle(.plain)
                        .frame(minWidth: 40, maxWidth: 120)
                        .focused($renameFocused)
                        .onSubmit { commitRename() }
                        .onKeyPress(.escape) {
                            cancelRename()
                            return .handled
                        }
                } else {
                    Text(tab.title)
                        .font(.system(size: 12))
                        .foregroundColor(tab.isActive ? .primary : .secondary)
                        .lineLimit(1)
                        // 正确的双击 + 单击共存模式（参考 FileNodeRow.swift）
                        .gesture(
                            TapGesture(count: 2).onEnded { startRename() }
                        )
                        .simultaneousGesture(
                            TapGesture(count: 1).onEnded { onSelect() }
                        )
                }

                if isHovered && !isRenaming && !isLastTab {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 14, height: 14)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Color.clear)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .contextMenu {
                Button("重命名") { startRename() }
                Divider()
                Button("关闭标签页") { onClose() }
                if !isLastTab {
                    Button("关闭其他标签页") { onCloseOthers() }
                }
            }
            .draggable(tab.id.uuidString)

            // 底部 2px 指示条（选中时显示）
            if tab.isActive {
                Rectangle()
                    .fill(accentColor)
                    .frame(height: 2)
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 60)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: tab.isActive)
    }

    private func startRename() {
        renameText = tab.title
        isRenaming = true
        renameFocused = true
    }

    private func commitRename() {
        isRenaming = false
        renameFocused = false
        onRename(renameText)
    }

    private func cancelRename() {
        isRenaming = false
        renameFocused = false
        // 不调用 onRename，保持原标题
    }
}
```

- [ ] **Step 1: 创建 TerminalTabItem.swift**（内容如上）

- [ ] **Step 2: 构建验证**

```bash
make check 2>&1 | head -40
```

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/TabBar/TerminalTabItem.swift
git commit -m "feat(tab-bar): add TerminalTabItem with underline style and hover close"
```

---

### Task 4: TerminalTabBar（整体 tab bar 容器）

**Files:**
- Create: `macos/Sources/Features/Workspace/TabBar/TerminalTabBar.swift`

**注意：** `frame(height: 36)` 只加在 `ScrollView` 上，`Divider` 在外层 `VStack`，总高约 37px（可用 `fixedSize` 处理）。

```swift
import SwiftUI

struct TerminalTabBar: View {
    @ObservedObject var viewModel: TabBarViewModel
    let accentColor: Color
    let onNewTab: () -> Void
    let onCloseTab: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(viewModel.tabs) { tab in
                            TerminalTabItem(
                                tab: tab,
                                accentColor: accentColor,
                                isLastTab: viewModel.tabs.count == 1,
                                onSelect: { viewModel.selectTab(tab.id) },
                                onClose: { onCloseTab(tab.id) },
                                onRename: { viewModel.renameTab(tab.id, title: $0) },
                                onCloseOthers: {
                                    viewModel.tabs
                                        .filter { $0.id != tab.id }
                                        .forEach { onCloseTab($0.id) }
                                }
                            )
                            .id(tab.id)
                            .dropDestination(for: String.self) { items, _ in
                                handleDrop(items: items, onto: tab)
                            }
                        }

                        Spacer(minLength: 0)

                        // "+" 新建 tab 按钮，固定在最右侧
                        Button(action: onNewTab) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(height: 36)
                .onChange(of: viewModel.activeTabId) { id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                }
            }

            Divider()
        }
        .background(.background.opacity(0.95))
    }

    private func handleDrop(items: [String], onto target: TabItem) -> Bool {
        guard let uuidStr = items.first,
              let sourceId = UUID(uuidString: uuidStr),
              let sourceIdx = viewModel.tabs.firstIndex(where: { $0.id == sourceId }),
              let targetIdx = viewModel.tabs.firstIndex(where: { $0.id == target.id }),
              sourceIdx != targetIdx
        else { return false }
        viewModel.moveTab(from: IndexSet(integer: sourceIdx), to: targetIdx)
        return true
    }
}
```

- [ ] **Step 1: 创建 TerminalTabBar.swift**（内容如上）

- [ ] **Step 2: 构建验证**

```bash
make check 2>&1 | head -40
```

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/TabBar/TerminalTabBar.swift
git commit -m "feat(tab-bar): add TerminalTabBar container with scroll and drag-reorder"
```

---

## Chunk 3: 集成到 PolterttyRootView

### Task 5: 修改 PolterttyRootView 支持 TabBarViewModel

**Files:**
- Modify: `macos/Sources/Features/Workspace/PolterttyRootView.swift`

**当前状态：** `PolterttyRootView<TerminalContent: View>` 是泛型 struct，通过 `terminalView: TerminalContent` 接受单个终端视图（类型为 `TerminalView<ViewModel>`，包含 split tree 逻辑）。

**改动策略：**
- 保留泛型 `terminalView: TerminalContent` 作为兜底（无 tab 时显示）
- 新增 `@ObservedObject var tabBarViewModel: TabBarViewModel` 参数
- 新增 `workspaceAccentColor: Color` 参数
- 新增 `onNewTab: () -> Void`、`onCloseTab: (UUID) -> Void` 参数
- 在终端区域外包 `VStack`，顶部条件插入 `TerminalTabBar`
- 当 `tabBarViewModel.activeSurface != nil` 时，显示 `activeSurface`；否则显示 `terminalView`

- [ ] **Step 1: 在 PolterttyRootView init 中添加新参数**

找到 init 定义（约 line 40），添加：
```swift
@ObservedObject var tabBarViewModel: TabBarViewModel
let workspaceAccentColor: Color
let onNewTab: () -> Void
let onCloseTab: (UUID) -> Void
```

在 init 参数列表中同步添加。

- [ ] **Step 2: 修改终端区域的 body**

找到 `terminalView` 的渲染位置（约 line 166），用以下代码替换：
```swift
VStack(spacing: 0) {
    // Tab bar：多 tab 且非文件预览全屏时显示
    if tabBarViewModel.tabs.count > 1 && !fileBrowserVM.isPreviewFullscreen {
        TerminalTabBar(
            viewModel: tabBarViewModel,
            accentColor: workspaceAccentColor,
            onNewTab: onNewTab,
            onCloseTab: onCloseTab
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // 终端内容：优先显示活跃的 SurfaceView，否则兜底 terminalView
    if let activeSurface = tabBarViewModel.activeSurface {
        activeSurface
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
        terminalView
    }
}
.animation(.easeInOut(duration: 0.2), value: tabBarViewModel.tabs.count > 1)
```

- [ ] **Step 3: 构建验证**

```bash
make check 2>&1 | head -80
```

`Ghostty.SurfaceView` 是 `NSViewRepresentable`，可以直接作为 SwiftUI View 使用。如有类型不匹配报错，在 `activeSurface` 后加 `.frame(maxWidth: .infinity, maxHeight: .infinity)`。

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Workspace/PolterttyRootView.swift
git commit -m "feat(tab-bar): integrate TerminalTabBar into PolterttyRootView"
```

---

## Chunk 4: TerminalController 集成与键盘快捷键

### Task 6: TerminalController 创建和管理 TabBarViewModel

**Files:**
- Modify: `macos/Sources/Features/Terminal/TerminalController.swift`

**关键：** `Ghostty.SurfaceView` 构造函数需要 `ghostty_app`（`OpaquePointer?`），不是 `ghostty`（`Ghostty.App`）。参考 `BaseTerminalController.swift:245-246` 的模式：
```swift
guard let ghostty_app = ghostty.app else { return }
let surface = Ghostty.SurfaceView(ghostty_app, baseConfig: nil)
```

- [ ] **Step 1: 添加 tabBarViewModel 属性**

在 `TerminalController` 类属性区域添加：
```swift
let tabBarViewModel = TabBarViewModel()
```

- [ ] **Step 2: 在 windowDidLoad() 初始化第一个 tab**

在 `windowDidLoad()` 中，找到创建 `PolterttyRootView` 的位置（约 line 1173），在创建之前插入：
```swift
// 初始化第一个 tab（poltertty 自定义 tab bar）
if let ghostty_app = ghostty.app {
    var config = Ghostty.SurfaceConfiguration()
    if let rootDir = workspace?.rootDirExpanded {
        config.workingDirectory = rootDir
    }
    let firstSurface = Ghostty.SurfaceView(ghostty_app, baseConfig: config)
    tabBarViewModel.addTab(surface: firstSurface, title: "Terminal")
}
```

然后修改 `PolterttyRootView` 初始化，添加新参数：
```swift
PolterttyRootView(
    workspaceId: self.workspaceId,
    terminalView: TerminalView(ghostty: ghostty, viewModel: self, delegate: self),
    tabBarViewModel: tabBarViewModel,
    workspaceAccentColor: workspaceAccentColorValue,
    onNewTab: { [weak self] in self?.addNewTab() },
    onCloseTab: { [weak self] id in self?.closeTab(id) },
    // ... 现有参数保持不变 ...
)
```

其中 `workspaceAccentColorValue` 的获取：
```swift
let workspaceAccentColorValue: Color = workspaceId
    .flatMap { WorkspaceManager.shared.workspace(for: $0) }
    .map { Color(hex: $0.colorHex) ?? .blue } ?? .blue
```

- [ ] **Step 3: 添加 addNewTab() 和 closeTab() 方法**

```swift
@MainActor
func addNewTab() {
    guard let ghostty_app = ghostty.app else { return }
    var config = Ghostty.SurfaceConfiguration()
    if let rootDir = workspaceId.flatMap({ WorkspaceManager.shared.workspace(for: $0) })?.rootDirExpanded {
        config.workingDirectory = rootDir
    }
    let surface = Ghostty.SurfaceView(ghostty_app, baseConfig: config)
    tabBarViewModel.addTab(surface: surface, title: "Terminal")
}

@MainActor
func closeTab(_ id: UUID) {
    guard tabBarViewModel.tabs.count > 1 else {
        window?.close()
        return
    }
    tabBarViewModel.closeTab(id)
    // SurfaceView 被从 surfaces 字典移除后，SwiftUI 不再持有引用，ARC 自动释放
}
```

- [ ] **Step 4: 修改 @IBAction newTab 实例方法（约 line 1423）**

将当前的 `ghostty.newTab(surface:)` 调用替换为：
```swift
@IBAction func newTab(_ sender: Any?) {
    addNewTab()
}
```

> **注意：** `AppDelegate` 的 `@IBAction func newTab`（约 line 1106）调用的是 `TerminalController.newTab()` 静态方法。该静态方法会创建新 NSWindow 并加入 tab group——这是**原生路径**，在 poltertty 模式下不应走这条路。
>
> 修改策略：在 `AppDelegate.newTab` 中，优先转发到当前 key window 的 `TerminalController`：
> ```swift
> @IBAction func newTab(_ sender: Any?) {
>     if let tc = NSApp.keyWindow?.windowController as? TerminalController {
>         tc.addNewTab()
>     } else {
>         _ = TerminalController.newTab(ghostty, from: TerminalController.preferredParent?.window)
>     }
> }
> ```

- [ ] **Step 5: 构建验证**

```bash
make check 2>&1 | head -80
```

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Terminal/TerminalController.swift
git add macos/Sources/App/macOS/AppDelegate.swift
git commit -m "feat(tab-bar): TerminalController creates and owns TabBarViewModel"
```

---

### Task 7: 键盘快捷键（上一个/下一个 tab）

**Files:**
- Modify: `macos/Sources/Features/Terminal/TerminalController.swift`

`Cmd+T` / `Cmd+W` 已在 Task 6 处理。这里补充切换快捷键。

- [ ] **Step 1: 添加 selectPreviousTab / selectNextTab 方法**

```swift
@IBAction func selectPreviousTab(_ sender: Any?) {
    guard let activeId = tabBarViewModel.activeTabId,
          let idx = tabBarViewModel.tabs.firstIndex(where: { $0.id == activeId }),
          idx > 0
    else { return }
    tabBarViewModel.selectTab(tabBarViewModel.tabs[idx - 1].id)
}

@IBAction func selectNextTab(_ sender: Any?) {
    guard let activeId = tabBarViewModel.activeTabId,
          let idx = tabBarViewModel.tabs.firstIndex(where: { $0.id == activeId }),
          idx < tabBarViewModel.tabs.count - 1
    else { return }
    tabBarViewModel.selectTab(tabBarViewModel.tabs[idx + 1].id)
}
```

- [ ] **Step 2: 在 Main.storyboard / MainMenu 中绑定快捷键**

确认 `Select Previous Tab` 菜单项绑定 `selectPreviousTab:` + `Cmd+Shift+[`，`Select Next Tab` 绑定 `selectNextTab:` + `Cmd+Shift+]`。

> **Cmd+1~9 注意：** Ghostty 的 `goto_tab:N` keybinding 目前路由到 `surfaceTree` 层，与 poltertty tab bar 是两套系统。本期不实现 Cmd+数字键（避免两套系统冲突），可在后续版本统一。

- [ ] **Step 3: 构建验证**

```bash
make check 2>&1 | head -40
```

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Terminal/TerminalController.swift
git commit -m "feat(tab-bar): add previous/next tab keyboard shortcuts"
```

---

## Chunk 5: PTY 标题更新与状态持久化

### Task 8: PTY 标题变化通知 TabBarViewModel

**Files:**
- Modify: `macos/Sources/Features/Terminal/BaseTerminalController.swift`

- [ ] **Step 1: 找到 PTY 标题更新入口**

在 `BaseTerminalController.swift` 中搜索 `lastComputedTitle` 的赋值，或 `surfaceTitleDidChange` 等 delegate 回调。找到后，在标题更新时追加：

```swift
// 通知 tabBarViewModel 更新对应 tab 的标题
if let tc = self as? TerminalController,
   let surface = focusedSurface {
    // 找到当前 surface 对应的 surfaceId
    let surfaceId = tc.tabBarViewModel.surfaces.first(where: { $0.value === surface })?.key
    if let surfaceId {
        tc.tabBarViewModel.updateTitle(forSurfaceId: surfaceId, title: newTitle)
    }
}
```

其中 `newTitle` 是新的终端标题字符串（根据实际代码调整变量名）。

- [ ] **Step 2: 构建验证**

```bash
make check 2>&1 | head -40
```

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Terminal/BaseTerminalController.swift
git commit -m "feat(tab-bar): propagate PTY title changes to active tab"
```

---

### Task 9: WorkspaceSnapshot 添加 Tab 状态

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceModel.swift`（`WorkspaceSnapshot` struct，约 line 73）
- Modify: `macos/Sources/Features/Terminal/TerminalController.swift`（snapshot save/restore）

- [ ] **Step 1: 扩展 WorkspaceSnapshot（使用 decodeIfPresent 向后兼容）**

```swift
struct WorkspaceSnapshot: Codable {
    var version: Int = 2
    var workspace: WorkspaceModel
    var windowFrame: WindowFrame?
    var sidebarWidth: CGFloat
    var sidebarVisible: Bool

    // Tab 状态（version 2 新增，decodeIfPresent 向后兼容 version 1 快照）
    var tabs: [PersistedTab]?
    var activeTabIndex: Int?

    struct PersistedTab: Codable {
        let title: String
        let titleLocked: Bool
    }

    // 其余代码不变（WindowFrame struct 等）
}
```

- [ ] **Step 2: 在保存 snapshot 时写入 tab 状态**

在 `TerminalController` 中找到构建 `WorkspaceSnapshot` 的位置，添加：
```swift
snapshot.tabs = tabBarViewModel.persistedTabs.map {
    WorkspaceSnapshot.PersistedTab(title: $0.title, titleLocked: $0.titleLocked)
}
snapshot.activeTabIndex = tabBarViewModel.activeTabIndex
```

- [ ] **Step 3: 恢复时应用 tab 标题**

在恢复 snapshot 时，对每个 tab 应用标题和锁定状态：
```swift
if let savedTabs = snapshot.tabs, !savedTabs.isEmpty {
    // 第一个 tab 已在 windowDidLoad 中创建，应用标题
    for (i, saved) in savedTabs.enumerated() {
        if i == 0, let firstId = tabBarViewModel.tabs.first?.id {
            if saved.titleLocked {
                tabBarViewModel.renameTab(firstId, title: saved.title)
            }
        } else {
            // 后续 tab 需要新建 surface + 恢复标题
            addNewTab()
            if saved.titleLocked, let lastId = tabBarViewModel.tabs.last?.id {
                tabBarViewModel.renameTab(lastId, title: saved.title)
            }
        }
    }
    // 恢复选中的 tab
    if let activeIdx = snapshot.activeTabIndex,
       activeIdx < tabBarViewModel.tabs.count {
        tabBarViewModel.selectTab(tabBarViewModel.tabs[activeIdx].id)
    }
}
```

- [ ] **Step 4: 构建验证**

```bash
make check 2>&1 | head -40
```

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceModel.swift
git add macos/Sources/Features/Terminal/TerminalController.swift
git commit -m "feat(tab-bar): persist and restore tab state in WorkspaceSnapshot"
```

---

## Chunk 6: 手动测试清单与收尾

### Task 10: 构建 Dev 版本并手动测试

- [ ] **Step 1: 清理构建并运行**

```bash
make run-dev
```

- [ ] **Step 2: 手动验证清单**

**基本功能：**
- [ ] 单个 tab 时，tab bar 不可见
- [ ] 按 `Cmd+T` 新建第二个 tab，tab bar 出现（有滑入动画）
- [ ] tab bar 仅在 sidebar 右侧，不横跨 sidebar
- [ ] 选中 tab 底部有彩色指示条（workspace 颜色）
- [ ] 点击 tab 可切换终端内容
- [ ] hover tab 时出现关闭按钮（×），最后一个 tab 无关闭按钮
- [ ] 关闭 tab 到只剩一个时，tab bar 消失（有滑出动画）
- [ ] 关闭最后一个 tab 时，窗口关闭

**标题栏：**
- [ ] 正式 workspace 窗口标题只显示 workspace 名称
- [ ] 临时 workspace 显示 "Poltertty"

**重命名：**
- [ ] 双击 tab 进入重命名模式
- [ ] Enter 确认，Escape 取消（恢复原名）
- [ ] 清空内容后 Enter，恢复 PTY 标题（解锁）
- [ ] PTY 标题变化（如 cd）更新未锁定的 tab 标题

**键盘：**
- [ ] `Cmd+Shift+[` / `]` 切换 tab
- [ ] `Cmd+W` 关闭当前 tab，最后一个时关闭窗口
- [ ] 菜单栏 "New Tab" 在已有 workspace 窗口中新增 tab（不新开窗口）

**溢出：**
- [ ] 打开 10+ 个 tab，tab bar 可水平滚动

**FileBrowser：**
- [ ] 文件预览全屏时 tab bar 隐藏

- [ ] **Step 3: 最终 Commit**

```bash
git add -A
git commit -m "feat(tab-bar): complete custom SwiftUI tab bar implementation"
```
