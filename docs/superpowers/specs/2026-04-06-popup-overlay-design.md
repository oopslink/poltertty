# Popup Overlay 设计文档

**日期**：2026-04-06  
**功能**：3.3 Popup Overlay 窗口

---

## 概述

在当前 Workspace 窗口上方弹出浮动终端 popup，用完即隐藏，不破坏底层 pane 布局。两种预设：空 shell（⌥⌘P）和 lazygit（⌥⌘G）。两种 popup 均保留会话，关闭只是隐藏，进程继续运行。

---

## 架构

```
TerminalWindow (NSWindow)
  ├── [内容区] SplitTree / 正常终端布局
  ├── BackdropView (NSView, alpha 0.55, 点击关闭 popup)
  └── PopupOverlayWindow (NSPanel, child window)
        └── Ghostty SurfaceView
```

**新增文件**：
- `macos/Sources/Features/PopupOverlay/PopupOverlayWindow.swift` — NSPanel 子类
- `macos/Sources/Features/PopupOverlay/PopupOverlayManager.swift` — 生命周期管理

**修改文件**：
- `TerminalController.swift` — 持有 `PopupOverlayManager`，注册快捷键菜单项
- `AppDelegate.swift` — 添加 ⌥⌘P / ⌥⌘G 菜单项 outlet

---

## 生命周期

两种 popup 行为完全一致，差别仅为启动命令。

```
首次触发快捷键
  → 创建 SurfaceView（shell 或 lazygit）
  → addChildWindow(popupWindow, ordered: .above)
  → 动画显示

按 ESC / 点击 backdrop / 再次按同一快捷键
  → 动画隐藏
  → popupWindow.orderOut（进程保留）

再次触发快捷键
  → popupWindow.orderFront（复用会话，无重建开销）

进程自然退出（exit / q）
  → SurfaceView 销毁
  → 下次触发重建
```

**互斥规则**：同一时刻只显示一个 popup。触发 ⌥⌘G 时若 shell popup 已显示，先隐藏 shell 再显示 lazygit，反之亦然。

**焦点管理**：
- 打开前记录当前 focused SurfaceView
- 关闭后将焦点归还原 SurfaceView

---

## UI 规格

| 属性 | 值 |
|------|-----|
| 宽度 | 父窗口内容区宽度 × 80% |
| 高度 | 父窗口内容区高度 × 70% |
| 位置 | 相对父窗口内容区居中 |
| 圆角 | 8pt |
| 边框 | 1pt，`#4a5568` |
| 投影 | `hasShadow = true` |
| Backdrop | 半透明黑色 NSView，alpha 0.55，覆盖整个内容区 |

**父窗口 resize**：监听 `NSWindowDidResizeNotification`，重新计算 popup frame 并更新。

**动画**：
- 打开：`alphaValue` 0→1，duration 0.15s
- 关闭：`alphaValue` 1→0，duration 0.1s

---

## 快捷键

| 快捷键 | 行为 |
|--------|------|
| ⌥⌘P | 切换 shell popup（显示/隐藏） |
| ⌥⌘G | 切换 lazygit popup（显示/隐藏） |

注册方式：AppDelegate 菜单项（与 Yazi `⌥⌘Y`、Browser `⌥⌘B` 同一 Section）。

---

## ESC 处理

- **Shell popup**：`PopupOverlayWindow` 拦截 ESC keyDown，隐藏 popup，不透传给 shell 进程
- **lazygit popup**：ESC 透传给 lazygit 进程（lazygit 内部处理）；`q` 退出进程，触发 SurfaceView 销毁流程

---

## PopupOverlayManager 接口

```swift
class PopupOverlayManager {
    // 切换指定 popup（显示中则隐藏，隐藏中则显示）
    func toggle(_ type: PopupType, in window: TerminalWindow)

    // 隐藏当前显示的 popup（焦点归还）
    func dismiss()

    enum PopupType {
        case shell
        case lazygit
    }
}
```

---

## 不在本期范围内

- 自定义命名 popup（任意命令绑定快捷键）
- popup 大小可配置
- popup 内 split
