# macOS Titlebar 自定义开发规则

从 Poltertty titlebar tabs 功能开发中总结的经验教训。

## 1. NSTitlebarAccessoryViewController 不适合复杂布局

**结论**：`NSTitlebarAccessoryViewController` 只适合放固定尺寸的小控件（按钮、状态指示器）。

**不要用它做**：
- 填满整个 titlebar 宽度的自定义 bar
- 需要动态调整宽度的视图
- 高度与 titlebar 不匹配的视图（会产生额外的黑色空行）

**踩过的坑**：
- `.trailing` 的 clip view 只按 `intrinsicContentSize` 定宽，设 `frame` 和 `invalidateIntrinsicContentSize` 均无效
- `titleVisibility = .hidden` 对 `titlebarAppearsTransparent = true` 的窗口无效
- 28px 高度的 accessory 在 22px titlebar 上会产生顶部黑色空行

**正确方案**：使用 `NSToolbar` + `toolbarStyle = .unifiedCompact`，参考 `TitlebarTabsTahoeTerminalWindow` 的实现。

## 2. NSToolbar item 不会自动填满宽度

**结论**：无论怎么设 `contentHuggingPriority`，toolbar item 的宽度始终等于 `intrinsicContentSize`。

**正确方案**：toolbar 布局完成后，找到 `NSToolbarView` → `NSToolbarItemViewer`，用 auto layout 约束强制拉满：

```swift
DispatchQueue.main.async {
    guard let toolbarView = titlebarContainer?.firstDescendant(withClassName: "NSToolbarView"),
          let itemViewer = toolbarView.subviews.first(where: { $0.className == "NSToolbarItemViewer" })
    else { return }
    itemViewer.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        itemViewer.leadingAnchor.constraint(equalTo: toolbarView.leadingAnchor, constant: 78),
        itemViewer.trailingAnchor.constraint(equalTo: toolbarView.trailingAnchor),
        // ...
    ])
}
```

## 3. `titlebarAppearsTransparent` 与 NSToolbar 冲突

**结论**：`titlebarAppearsTransparent = true` 会在 `.unifiedCompact` toolbar 上方产生一条空行。

**正确方案**：在 `syncAppearance` 中，检测到 workspace toolbar 时跳过 `titlebarAppearsTransparent = true`。

## 4. SwiftUI 手势穿透导致 tab 关闭错乱

**结论**：`.simultaneousGesture` 会导致 overlay 中的 Button 点击同时触发底层手势。

**不要用**：
```swift
.simultaneousGesture(TapGesture(count: 1).onEnded { onSelect() })
// 点击 x 按钮时 onSelect 也会触发，切换 active tab，导致 surfaceTree 映射错乱
```

**正确方案**：用 `.onTapGesture`，overlay 中的 Button 自然拦截点击，不会穿透。

```swift
.onTapGesture(count: 2) { startRename() }
.onTapGesture { onSelect() }
.overlay(alignment: .trailing) {
    Button(action: onClose) { ... }  // Button 拦截点击，不触发 onTapGesture
}
```

## 5. Tab 关闭必须先切换 surfaceTree 再移除 tab

**结论**：`tabBarViewModel.closeTab(id)` 内部调用 `selectTab` 会触发 `$activeTabId` observer，但该 observer 只更新 `focusedSurface`，不 swap `surfaceTree`。导致 tab-pane 映射错乱。

**不要用**：
```swift
// 错误：closeTab 内部的 selectTab 不做 surfaceTree swap
tabBarViewModel.closeTab(id)
```

**正确方案**：
```swift
// 1. 如果关闭 active tab，先 switchToTab（正确 swap surfaceTree）
// 2. 用 removeTabOnly 移除 tab（不触发 selectTab）
// 3. 清理 tabSurfaceTrees[id]
```

Tab 和 pane 的关联必须基于 UUID 直接映射（`tabSurfaceTrees[tabId]`），不能依赖数组索引或隐式计算。

## 6. GeometryReader 在 NSToolbar item 中无效

**结论**：`GeometryReader` 作为 toolbar item 的根视图时，`intrinsicContentSize` 为 0，toolbar 给它零空间。

**正确方案**：从 AppKit 侧通过 `NSView.frameDidChangeNotification` 观察 hosting view 的实际渲染宽度，通过 `ObservableObject` 传给 SwiftUI。

## 7. 先验证基础方案可行再写业务逻辑

**经验**：在本次开发中，大量时间浪费在 `NSTitlebarAccessoryViewController` 方案上（尝试动态宽度、隐藏 title、修复黑色 bar），最终全部推翻改用 `NSToolbar`。

**规则**：
- 涉及 macOS 系统 UI 定制时，先写一个最小 POC 验证核心能力（能否填满宽度？能否隐藏 title？）
- 如果基础能力不满足，立即换方案，不要在错误的方向上叠加 hack
- 参考项目中已有的成功实现（如 `TitlebarTabsTahoeTerminalWindow`）

## 8. 全屏状态下红绿灯的动态处理

**规则**：
- 非全屏：左边距固定 78px（红绿灯区域）
- 全屏：初始 0px，通过 KVO 监听 `standardWindowButton(.closeButton).superview.alphaValue` 动态调整
- 进入/退出全屏：监听 `NSWindow.didEnterFullScreenNotification` / `didExitFullScreenNotification`
