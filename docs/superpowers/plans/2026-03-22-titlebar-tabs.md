# Titlebar Tabs 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将现有独立 tab bar（36px）移入 macOS titlebar，与 traffic lights 共用 28px 高度行，消除多余垂直空间。

**Architecture:** 使用 `NSTitlebarAccessoryViewController`（`.trailing`）将 SwiftUI tabs 嵌入 titlebar 右侧区域；window title 改为显示 workspace 名称；从 `PolterttyRootView.terminalAreaView` 中完全移除 `TerminalTabBar`。

**Tech Stack:** SwiftUI + AppKit (`NSTitlebarAccessoryViewController`, `NSHostingView`)，现有 `TabBarViewModel` / `TerminalTabItem` 复用。

---

## 文件结构

| 操作 | 文件 | 说明 |
|------|------|------|
| 新建 | `macos/Sources/Features/Workspace/TabBar/TitlebarTabsAccessory.swift` | `NSTitlebarAccessoryViewController` 子类 + `TitlebarTabsView` SwiftUI 视图 |
| 修改 | `macos/Sources/Features/Workspace/TabBar/TerminalTabItem.swift` | 高度从 36px 改为 28px，去掉外层底部 divider |
| 修改 | `macos/Sources/Features/Workspace/PolterttyRootView.swift` | 移除 `TerminalTabBar`、`onNewTab`、`onCloseTab` 参数 |
| 修改 | `macos/Sources/Features/Terminal/TerminalController.swift` | 创建并注册 `TitlebarTabsAccessory`，设置 window title = workspace name |
| 删除 | `macos/Sources/Features/Workspace/TabBar/TerminalTabBar.swift` | 被 `TitlebarTabsView` 完全替代 |

---

### Task 1：创建 TitlebarTabsAccessory

**Files:**
- Create: `macos/Sources/Features/Workspace/TabBar/TitlebarTabsAccessory.swift`

- [ ] **Step 1：新建文件，写 `TitlebarTabsAccessory` 骨架**

```swift
// macos/Sources/Features/Workspace/TabBar/TitlebarTabsAccessory.swift
import AppKit
import SwiftUI

/// 将自定义 tab bar 嵌入 macOS titlebar 右侧区域
final class TitlebarTabsAccessory: NSTitlebarAccessoryViewController {
    private let tabBarViewModel: TabBarViewModel
    private let accentColor: Color
    private let onNewTab: () -> Void
    private let onCloseTab: (UUID) -> Void
    private let onSwitchTab: (UUID) -> Void

    init(
        tabBarViewModel: TabBarViewModel,
        accentColor: Color,
        onNewTab: @escaping () -> Void,
        onCloseTab: @escaping (UUID) -> Void,
        onSwitchTab: @escaping (UUID) -> Void
    ) {
        self.tabBarViewModel = tabBarViewModel
        self.accentColor = accentColor
        self.onNewTab = onNewTab
        self.onCloseTab = onCloseTab
        self.onSwitchTab = onSwitchTab
        super.init(nibName: nil, bundle: nil)
        self.layoutAttribute = .trailing
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let tabsView = TitlebarTabsView(
            viewModel: tabBarViewModel,
            accentColor: accentColor,
            onNewTab: onNewTab,
            onCloseTab: onCloseTab,
            onSwitchTab: onSwitchTab
        )
        let hosting = NSHostingView(rootView: tabsView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        self.view = hosting
    }
}
```

- [ ] **Step 2：在同文件内写 `TitlebarTabsView`（SwiftUI）**

```swift
/// Titlebar 内右侧 tab bar 视图（含分隔线 + underline + + 按钮）
struct TitlebarTabsView: View {
    @ObservedObject var viewModel: TabBarViewModel
    let accentColor: Color
    let onNewTab: () -> Void
    let onCloseTab: (UUID) -> Void
    let onSwitchTab: (UUID) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(viewModel.tabs) { tab in
                            TerminalTabItem(
                                tab: tab,
                                accentColor: accentColor,
                                isLastTab: viewModel.tabs.count == 1,
                                onSelect: { onSwitchTab(tab.id) },
                                onClose: { onCloseTab(tab.id) },
                                onRename: { viewModel.renameTab(tab.id, title: $0) },
                                onCloseOthers: {
                                    viewModel.tabs
                                        .filter { $0.id != tab.id }
                                        .forEach { onCloseTab($0.id) }
                                },
                                agentState: viewModel.agentState(for: tab.surfaceId)
                            )
                            .id(tab.id)
                            // 保留拖拽重排支持（与原 TerminalTabBar 一致）
                            .dropDestination(for: String.self) { items, _ in
                                guard let uuidStr = items.first,
                                      let sourceId = UUID(uuidString: uuidStr),
                                      let sourceIdx = viewModel.tabs.firstIndex(where: { $0.id == sourceId }),
                                      let targetIdx = viewModel.tabs.firstIndex(where: { $0.id == tab.id }),
                                      sourceIdx != targetIdx
                                else { return false }
                                let dest = sourceIdx < targetIdx ? targetIdx + 1 : targetIdx
                                viewModel.moveTab(from: IndexSet(integer: sourceIdx), to: dest)
                                return true
                            }
                        }
                    }
                }
                .onChange(of: viewModel.activeTabId) { id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                }
            }

            // "+" 新建 tab 按钮
            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 28)
            }
            .buttonStyle(.plain)
            .overlay(alignment: .leading) {
                Divider()
                    .frame(width: 0.5, height: 14)
                    .background(Color(nsColor: .separatorColor))
            }
        }
        .frame(height: 28)
        .background(Color.clear)
    }
}
```

- [ ] **Step 3：编译验证（不运行，只检查无语法错误）**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build 2>&1 | tail -30
```

Expected: 只会出现 "TitlebarTabsAccessory" 相关 undefined symbol 报错（因为还未注册），不出现语法错误。

- [ ] **Step 4：Commit**

```bash
git add macos/Sources/Features/Workspace/TabBar/TitlebarTabsAccessory.swift
git commit -m "feat: 新增 TitlebarTabsAccessory 和 TitlebarTabsView"
```

---

### Task 2：调整 TerminalTabItem 高度为 28px

**Files:**
- Modify: `macos/Sources/Features/Workspace/TabBar/TerminalTabItem.swift`

- [ ] **Step 1：将 `.frame(height: 36)` 改为 `.frame(height: 28)`**

在 `TerminalTabItem.swift` 找到 `body` 内的：
```swift
.frame(height: 36)
```
改为：
```swift
.frame(height: 28)
```

- [ ] **Step 2：验证 underline 指示条仍贴底部**

`ZStack(alignment: .bottom)` + `Rectangle().frame(height: 2)` 的结构不变，底部指示条自动贴到 28px 底部，无需额外修改。

- [ ] **Step 3：Commit**

```bash
git add macos/Sources/Features/Workspace/TabBar/TerminalTabItem.swift
git commit -m "feat: TerminalTabItem 高度从 36px 调整为 28px 以适配 titlebar"
```

---

### Task 3：在 TerminalController 中注册 TitlebarTabsAccessory

**Files:**
- Modify: `macos/Sources/Features/Terminal/TerminalController.swift:1504-1615`

- [ ] **Step 1：在 `windowDidLoad` 中添加 titlebar accessory**

精确位置：在第 1603 行 `window.title = "✦ Poltertty"` **之前**，第 1604 行注释之后插入（`WorkspaceManager.shared.workspace(for:)` 不依赖 `registerWindow`，可在注册前调用）：

```swift
// 注册自定义 titlebar tab bar
if workspaceId != nil {
    let accentColor: Color = {
        if let wsId = workspaceId,
           let workspace = WorkspaceManager.shared.workspace(for: wsId) {
            return Color(hex: workspace.colorHex) ?? .accentColor
        }
        return .accentColor
    }()
    let tabsAccessory = TitlebarTabsAccessory(
        tabBarViewModel: tabBarViewModel,
        accentColor: accentColor,
        onNewTab: { [weak self] in self?.addNewTab() },
        onCloseTab: { [weak self] id in self?.closePolterttyTab(id) },
        onSwitchTab: { [weak self] id in self?.switchToTab(id) }
    )
    window.addTitlebarAccessoryViewController(tabsAccessory)
}
```

- [ ] **Step 2：设置 window title 为 workspace 名称**

在同一 `windowDidLoad` 区块，找到 workspace 注册后添加：

```swift
// 设置 titlebar 显示 workspace 名称，而非终端 session 标题
if let wsId = workspaceId,
   let workspace = WorkspaceManager.shared.workspace(for: wsId) {
    window.title = workspace.name
}
```

- [ ] **Step 3：编译验证**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build 2>&1 | tail -30
```

Expected: BUILD SUCCEEDED（或仅有与 `TerminalTabBar` 移除无关的警告）。

- [ ] **Step 4：Commit**

```bash
git add macos/Sources/Features/Terminal/TerminalController.swift
git commit -m "feat: 在 TerminalController 中注册 TitlebarTabsAccessory 并显示 workspace 名称"
```

---

### Task 4：从 PolterttyRootView 移除 TerminalTabBar

**Files:**
- Modify: `macos/Sources/Features/Workspace/PolterttyRootView.swift`

- [ ] **Step 1：移除 `terminalAreaView` 中的 `TerminalTabBar` 块**

找到并删除：
```swift
// Tab bar：多 tab 且非全屏预览时显示
if tabBarViewModel.tabs.count > 1 {
    TerminalTabBar(
        viewModel: tabBarViewModel,
        accentColor: workspaceAccentColor,
        onNewTab: onNewTab,
        onCloseTab: onCloseTab,
        onSwitchTab: onSwitchTab
    )
    .transition(.move(edge: .top).combined(with: .opacity))
}
```

以及末尾的：
```swift
.animation(.easeInOut(duration: 0.2), value: tabBarViewModel.tabs.count > 1)
```

- [ ] **Step 2：移除 `PolterttyRootView` 中 `onNewTab` 和 `onCloseTab` 参数**

从 `PolterttyRootView` 的 `init` 和 `let` 声明中移除：
- `let onNewTab: () -> Void`
- `let onCloseTab: (UUID) -> Void`

注意：`onSwitchTab` 仍保留，因为 `NotificationCenterPanel.onJumpToSurface` 使用了它。

- [ ] **Step 3：修复 TerminalController 中的调用**

`TerminalController.windowDidLoad` 内 `PolterttyRootView(...)` 的初始化调用，移除已删除的参数：
```swift
// 删除这两行
onNewTab: { [weak self] in self?.addNewTab() },
onCloseTab: { [weak self] id in self?.closePolterttyTab(id) },
```

- [ ] **Step 4：编译验证**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build 2>&1 | tail -30
```

Expected: BUILD SUCCEEDED，无 `TerminalTabBar` 相关错误。

- [ ] **Step 5：Commit**

```bash
git add macos/Sources/Features/Workspace/PolterttyRootView.swift \
        macos/Sources/Features/Terminal/TerminalController.swift
git commit -m "feat: 从 PolterttyRootView 移除 TerminalTabBar，清理相关参数"
```

---

### Task 5：删除 TerminalTabBar.swift

**Files:**
- Delete: `macos/Sources/Features/Workspace/TabBar/TerminalTabBar.swift`

- [ ] **Step 1：确认无其他引用**

```bash
grep -r "TerminalTabBar" macos/Sources/ --include="*.swift"
```

Expected: 无任何引用输出。

- [ ] **Step 2：删除文件并从 Xcode project 中移除**

```bash
rm macos/Sources/Features/Workspace/TabBar/TerminalTabBar.swift
```

然后在 `macos/Ghostty.xcodeproj` 中找到对该文件的引用并删除（通过编辑 project.pbxproj 或 Xcode GUI）：

```bash
# 确认 pbxproj 中有引用
grep -n "TerminalTabBar" macos/Ghostty.xcodeproj/project.pbxproj
```

若有引用，手动编辑 `project.pbxproj` 删除对应行（PBXFileReference + PBXBuildFile + Sources 引用）。

- [ ] **Step 3：编译验证**

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -destination 'platform=macOS' build 2>&1 | tail -30
```

Expected: BUILD SUCCEEDED。

- [ ] **Step 4：Commit**

```bash
git add -A
git commit -m "chore: 删除已废弃的 TerminalTabBar.swift"
```

---

### Task 6：视觉验证与收尾

**Files:**
- No new files

- [ ] **Step 1：手动启动应用，验证以下行为**

| 场景 | 预期 |
|------|------|
| 单个 tab | Tab 显示在 titlebar 右侧，无 x 按钮 |
| 新建第 2 个 tab | Tabs 自动出现在 titlebar，x 按钮 hover 可见 |
| 点击 x | 正确关闭对应 tab（确认 dialog 弹出） |
| 拖拽重排 tab | Tab 顺序更新 |
| 切换 tab | 终端内容正确切换，active underline 移动 |
| Workspace 名称 | Titlebar 显示 workspace name 而非终端标题 |
| 侧边栏展开/折叠 | 不影响 titlebar tabs |

- [ ] **Step 2：若 tab 视觉异常（高度超出 titlebar），在 `TerminalTabItem` 增加 clip**

```swift
.frame(height: 28)
.clipped()
```

- [ ] **Step 3：最终 commit**

```bash
git add -A
git commit -m "feat: titlebar 集成 tab bar 完成，视觉验证通过"
```

---

## 注意事项

1. **`NSTitlebarAccessoryViewController` 与 `TransparentTitlebarTerminalWindow`**：accessory 视图背景必须透明（`Color.clear`），否则会遮挡 titlebar 透明效果。
2. **`onSwitchTab` 仍在 `PolterttyRootView`**：用于 `NotificationCenterPanel.onJumpToSurface`，不要删除。
3. **非 workspace 窗口**（`workspaceId == nil`）：`TitlebarTabsAccessory` 不注册，行为与上游 Ghostty 一致。
4. **全屏模式**：`NSTitlebarAccessoryViewController` 在全屏时会自动隐藏，无需额外处理。
