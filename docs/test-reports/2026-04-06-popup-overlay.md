# Popup Overlay UI/UX Test Report

**日期**: 2026-04-06
**分支**: feature/popup-overlay
**构建**: Debug

## 测试结果总览

| 场景 | 结果 | 截图 |
|------|------|------|
| 1. 初始状态 | ✅ PASS | 01-initial.png |
| 2. Shell Popup 打开（⌥⌘I） | ✅ PASS | 02-shell-popup-open.png |
| 3. ESC 关闭 Shell Popup | ✅ PASS（修复后） | 03-shell-popup-closed.png |
| 4. 会话保留（再次打开） | ✅ PASS | 04-shell-popup-reopen.png |
| 5. Lazygit Popup 打开（⌥⌘G，Shell 自动关闭） | ✅ PASS | 05-lazygit-popup-open.png |
| 6. Lazygit Popup 关闭（再次 ⌥⌘G） | ✅ PASS | 06-lazygit-popup-closed.png |

## 发现的问题及修复

### 问题 1：ShortcutHelpView 不存在（跳过）
- 代码库中未找到 `ShortcutHelpView`，无需更新。

### 问题 2：ESC 键无法关闭 Shell Popup（已修复）
**现象**：按 ESC 后 shell popup 窗口依然可见。

**根本原因**：`SurfaceView_AppKit.swift` 的 `keyDown` 方法直接消费所有键盘事件并传给 libghostty，不会向上传递给 `PopupOverlayWindow.keyDown`，导致 `PopupOverlayWindow.onEscapePressed` 回调从未被触发。

**修复方案**：在 `PopupOverlayManager` 中安装 `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` 监听器，在 shell popup 可见且 keyWindow 为 popup 或父窗口时拦截 ESC 事件，调用 `dismiss` 并返回 `nil` 阻止事件传播。

**修复文件**：`macos/Sources/Features/PopupOverlay/PopupOverlayManager.swift`

### 问题 3：测试环境中 lazygit 未安装（预期，不修复）
- Lazygit Popup 打开后显示 "bash: exec: lazygit: not found"
- 这是测试环境问题，popup 机制本身工作正常
- 生产环境安装 lazygit 后即可正常使用

## 功能验证详情

### Shell Popup（⌥⌘I）
- ✅ 菜单项在 Workspace 菜单中正确注册
- ✅ 点击后 popup 以 0.15s 淡入动画显示在父窗口中央
- ✅ Popup 覆盖约 80%×70% 的父窗口内容区域
- ✅ ESC 键关闭 popup（修复后）
- ✅ 关闭后再次打开，shell 进程和历史保留（session persistence）

### Lazygit Popup（⌥⌘G）
- ✅ 菜单项在 Workspace 菜单中正确注册
- ✅ 打开 lazygit popup 时，如果 shell popup 已打开则自动关闭（互斥）
- ✅ 再次 ⌥⌘G 关闭 popup，返回父窗口

### 整体架构验证
- ✅ `PopupOverlayWindow` 作为 NSPanel child window 正确挂载
- ✅ 窗口数从 1→2（打开）→1（关闭）验证了 child window 机制
- ✅ `PopupOverlayManager` 生命周期管理正常

## 结论

Popup Overlay 功能整体工作正常，发现并修复了 ESC 键无法关闭 Shell Popup 的 Bug（根本原因是 SurfaceView 拦截了所有键盘事件）。修复方案采用 event monitor 模式，无需修改 SurfaceView 底层代码，改动最小、影响范围可控。

lazygit 未安装是测试环境限制，不影响功能评估。建议在安装了 lazygit 的环境中补充验证场景 5 的完整交互。
