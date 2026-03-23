# Fast Split Pane Focus 设计文档

**日期**: 2026-03-23
**分支**: feature/fast-split-pane
**状态**: 待实现

---

## 功能概述

用键盘快速聚焦到任意 split pane：双击 Cmd 键后，每个 pane 右上角弹出编号浮窗（`#0`、`#1`…），用户按对应字符即可将焦点跳转到该 pane。再次双击 Cmd 或按 Esc 取消。

---

## 用户交互流程

1. 用户双击 Cmd 键（间隔 ≤ 350ms）
2. 当前 tab 所有 split pane 右上角出现编号 badge：`#0`、`#1`…`#9`、`#a`…`#z`
3. 用户按对应字符（`0`-`9` 或 `a`-`z`）→ 焦点跳转到该 pane，badge 消失
4. 取消：再次双击 Cmd，或按 Esc → badge 消失

---

## 编号规则

| pane 序号 | 显示 badge | 触发键 |
|-----------|-----------|--------|
| 0（第 1 个） | `#0` | `0` |
| 1 | `#1` | `1` |
| … | … | … |
| 9 | `#9` | `9` |
| 10 | `#a` | `a` |
| … | … | … |
| 35 | `#z` | `z` |

- 序号按可见树 `(surfaceTree.zoomed ?? surfaceTree.root)?.leaves()` DFS 顺序（从左到右、从上到下）分配
  - zoom 模式下只有 1 个可见 pane，badge 仅显示 `#0`
  - 非 zoom 模式下枚举所有 pane
- 最多支持 36 个分屏（0-9 共 10 个 + a-z 共 26 个）；超出部分（index ≥ 36）`label(for:)` 返回 `"?"` 作为占位，不注册键位
- 大小写均接受（`A` 等同 `a`）
- `Ghostty.SurfaceView.id` 为 `UUID` 类型；`assignments: [UUID: Int]` 的 key 与之直接匹配
- `TerminalSplitLeafContainer` 中的属性名为 `let surfaceView: Ghostty.SurfaceView`，overlay 代码中的 `surfaceView.id` 与此对应

---

## 架构方案

**选型：Singleton 检测器 + ObservableObject 状态 + NSEvent local monitor**

遵循现有 `ShiftDoubleTapDetector` + `TabBarViewModel` 模式。

---

## 新增文件

均位于 `macos/Sources/Features/Splits/`：

### `CmdDoubleTapDetector.swift`

单例，检测双击 Cmd，发送通知。

```
CmdDoubleTapDetector.shared.start()  // 在 AppDelegate 启动时调用
```

- 监听 `.flagsChanged`，keyCode 为 `kVK_Command` / `kVK_RightCommand`
- 只处理按下瞬间（`modifierFlags.contains(.command)`），忽略松开
- 两次按下间隔 ≤ 350ms → 双击成立
- 任何非 Cmd 修饰符变化 → 重置计时器
- 普通 keyDown → 重置计时器
- 双击时：`NotificationCenter.default.post(name: .togglePaneSelector, object: NSApp.keyWindow)`

### `PaneSelectorViewModel.swift`

`@MainActor final class PaneSelectorViewModel: ObservableObject`，全局单例。

**属性：**
```swift
@Published var isActive: Bool = false
@Published var assignments: [UUID: Int] = [:]  // surfaceId → 0-indexed pane 序号
```

**辅助函数（index 合法范围为 0…35，调用方保证非负）：**
```swift
static func label(for index: Int) -> String {
    guard index >= 0 else { return "?" }
    if index <= 9 { return "\(index)" }
    guard index <= 35 else { return "?" }  // index ≥ 36：无对应键位
    let char = Character(UnicodeScalar(Int(("a" as UnicodeScalar).value) + index - 10)!)
    return String(char)
}
```

**实例属性（必须保存 monitor 引用，供 deactivate 使用）：**
```swift
private var keyMonitor: Any?
```

**激活流程（`activate(for window: NSWindow?)`）：**
1. 从 `window?.windowController as? TerminalController` 取控制器
   - 注意：native tab 模式下每个 tab 是独立的 NSWindow，`keyWindow` 本身就是当前 tab 对应的窗口，其 `windowController` 持有当前 tab 的 `surfaceTree`，**无需额外的 tab 过滤**
2. 调用 `(controller.surfaceTree.zoomed ?? controller.surfaceTree.root)?.leaves()` 获取当前可见 pane
   - zoom 模式下返回 1 个元素；正常模式下返回全部叶节点
3. `enumerate` 建立 `[surfaceView.id: index]`（0-indexed，`surfaceView.id` 类型为 `UUID`）
4. `isActive = true`
5. 注册 local keyDown monitor，**引用存入 `keyMonitor`**

**keyDown monitor 逻辑：**
- `event.charactersIgnoringModifiers?.lowercased()` 取首字符
- `"0"`…`"9"` → 计算 index（`"0"` → 0，`"1"` → 1…`"9"` → 9）
- `"a"`…`"z"` → index = ascii(`char`) - ascii(`"a"`) + 10
- 找到对应 surfaceId → `Ghostty.moveFocus(to: surface)` → `deactivate()`，返回 `nil`（消费事件）
- `Esc`（keyCode 53）→ `deactivate()`，返回 `nil`（**有意消费**：选择模式激活期间 Esc 不透传给终端，为预期行为）
- 其他键 → 透传，返回 event

**deactivate()：**
- `isActive = false`，`assignments = [:]`
- `NSEvent.removeMonitor(keyMonitor)`，`keyMonitor = nil`

**通知监听：**
- `.togglePaneSelector`：若未激活 → `activate(for: notification.object as? NSWindow)`；若已激活 → `deactivate()`
- `NSWindow.didResignKeyNotification`：若激活中 → `deactivate()`（窗口失焦自动取消）

### `PaneBadgeView.swift`

```swift
struct PaneBadgeView: View {
    let label: String  // "0"…"9", "a"…"z"

    var body: some View {
        Text("#\(label)")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
    }
}
```

出现/消失：`.transition(.opacity.animation(.easeInOut(duration: 0.15)))`

---

## 修改文件

### `TerminalSplitTreeView.swift` — `TerminalSplitLeafContainer`

注意：badge overlay 修改在 **`TerminalSplitLeafContainer`**（struct，第 96 行附近），而非内层的 `TerminalSplitLeaf`（关闭按钮所在 struct）。`TerminalSplitLeafContainer` 包裹 `TerminalSplitLeaf`，在其 `.overlay` 链末尾追加 badge 层即可。

新增 `@EnvironmentObject var paneSelectorVM: PaneSelectorViewModel`

在 `TerminalSplitLeafContainer.body` 的 overlay 链末尾追加：

```swift
.overlay(alignment: .topTrailing) {
    if paneSelectorVM.isActive,
       let idx = paneSelectorVM.assignments[surfaceView.id] {
        PaneBadgeView(label: PaneSelectorViewModel.label(for: idx))
            .padding(6)
            .transition(.opacity.animation(.easeInOut(duration: 0.15)))
    }
}
```

- 单 pane（无分屏）时 badge 同样正常显示（`isSplit` 为 false），行为与多 pane 一致，逻辑简单统一
- 选择模式激活期间鼠标悬停触发关闭按钮的场景属极端情况，不做特殊处理

### `TerminalView.swift`

在 `TerminalSplitTreeView(...)` 调用处追加：

```swift
.environmentObject(PaneSelectorViewModel.shared)
```

### `AppDelegate.swift`（或启动入口）

在 `applicationDidFinishLaunching` 中追加：

```swift
CmdDoubleTapDetector.shared.start()
```

---

## 边界情况

| 场景 | 处理 |
|------|------|
| 单 pane（无分屏） | 正常显示 `#0`，按 `0` 聚焦，无副作用；逻辑与多 pane 完全一致 |
| zoom 模式 | 只对可见节点调用 `leaves()`，仅显示 `#0` |
| pane 数 > 36 | 超出部分 `label` 为 `"?"`，不响应键盘 |
| 选择模式中窗口失焦 | 监听 `didResignKeyNotification` 自动 deactivate |
| 多窗口 | 只响应 `keyWindow` 对应控制器，其他窗口 badge 不出现 |
| Cmd 与系统快捷键 | Cmd+C 等：local keyDown 触发计时器重置；Cmd+Tab 等系统级快捷键不产生 local keyDown，但双击 350ms 阈值极短，Cmd 按下到 Tab 切换完成再回到 App 所需时间远超阈值，实际不会误触发 |
| focus 路径兼容 | 使用已有 `Ghostty.moveFocus(to:)`，不触碰 `syncFocusToSurfaceTree` |
| 上下分屏 focus 兼容 | 不引入新的 hit test / mouse event，无回归风险 |

---

## 文件清单

**新增（3 个）：**
- `macos/Sources/Features/Splits/CmdDoubleTapDetector.swift`
- `macos/Sources/Features/Splits/PaneSelectorViewModel.swift`
- `macos/Sources/Features/Splits/PaneBadgeView.swift`

**修改（3 个）：**
- `macos/Sources/Features/Splits/TerminalSplitTreeView.swift`
- `macos/Sources/Features/Terminal/TerminalView.swift`
- `macos/Sources/App/macOS/AppDelegate.swift`
