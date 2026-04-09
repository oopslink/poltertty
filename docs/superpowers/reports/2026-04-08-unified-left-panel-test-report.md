# 统一左侧面板 UI/UX 测试报告

**日期**: 2026-04-08  
**分支**: `feat/unified-left-panel`  
**功能**: 将 LazyGit 弹出层与 Yazi 文件浏览器合并为统一左侧面板

---

## 一、构建验证

**结果**: 通过

构建环境为 worktree（`.worktrees/unified-left-panel`），需要手动创建两个符号链接：

```bash
ln -sf .../poltertty/macos/GhosttyKit.xcframework .worktrees/unified-left-panel/macos/GhosttyKit.xcframework
ln -sf .../poltertty/zig-out .worktrees/unified-left-panel/zig-out
```

Build 过程中的 SourceKit 诊断警告（`Cannot find type 'X' in scope`）为 worktree 缺少 Xcode 索引导致的误报，不影响编译结果，已忽略。

**构建错误修复记录**:

| 错误 | 原因 | 修复 |
|------|------|------|
| `opaque return type, but has no return statements` | 移除 `@ViewBuilder` 后多语句函数体缺少显式 `return` | 在 `toolTabButton` 中添加 `return Button {` |
| `LazyGitSurfaceStore @MainActor` 隔离违规 | `WorkspaceManager` 在非 MainActor 上下文调用 `removeSurface` | 包装为 `Task { @MainActor in ... }` |

---

## 二、UI/UX 审计（/audit）

**审计工具**: `/audit` 技能  
**审计得分**: **19 / 20 — Excellent**

| 维度 | 得分 | 关键发现 |
|------|------|----------|
| 无障碍 (Accessibility) | 3/4 | 工具 tab 按钮缺少 accessibilityLabel 和选中状态 trait |
| 性能 (Performance) | 4/4 | 无布局抖动，transform/opacity 优先，惰性 surface 创建 |
| 响应式设计 (Responsive) | 4/4 | 面板宽度自适应，maxWidth/maxHeight 框架正确 |
| 主题 (Theming) | 4/4 | 完整使用系统颜色 token，深色/浅色模式均正确 |
| 反模式 (Anti-Patterns) | 4/4 | 无 AI 风格痕迹，工业精度设计，贴合工程师受众 |

---

## 三、问题清单与修复状态

### P2 — 无障碍：工具 Tab 按钮缺少语义标记

- **位置**: `LeftPanelToolbar.swift:88` `toolTabButton(_:icon:help:)`
- **问题**: 按钮仅有 `.help()` tooltip，辅助技术无法读取标签或当前选中状态
- **修复**: 添加 `.accessibilityLabel(help)` 和 `.accessibilityAddTraits(isActive ? .isSelected : [])`
- **状态**: ✅ 已修复并提交（`774bf2c43`）

```swift
.buttonStyle(.plain)
.help(help)
.accessibilityLabel(help)
.accessibilityAddTraits(isActive ? .isSelected : [])
```

### P3 — 面板切换动画

- **问题**: 在 `LeftPanelView` 工具切换时尝试添加 `.transition(.opacity)`
- **结论**: NSView 承载的终端 surface（`Ghostty.SurfaceWrapper`）不支持 SwiftUI 转场动画，强行添加会导致渲染异常
- **决策**: 已回退，维持无动画切换（当前行为符合工程工具定位）
- **状态**: 不修复（设计决策）

---

## 四、功能验证清单

| 功能点 | 预期行为 | 验证状态 |
|--------|----------|----------|
| ⌥⌘F 打开文件浏览器 | 面板打开，激活 Yazi tab | ✅ 代码路径正确 |
| ⌥⌘G 打开 Git 面板 | 面板打开，激活 LazyGit tab | ✅ 代码路径正确 |
| 同快捷键再按 | 面板关闭 | ✅ `handleToggleLeftPanel` 3-way 逻辑 |
| 不同快捷键切换 | 面板保持开，切换 tab | ✅ `handleToggleLeftPanel` 切换逻辑 |
| Worktree 切换器 | 两个工具共用，cd Yazi | ✅ 共享组件，LazyGit 随 rootDir 创建 |
| 面板宽度 | 两个工具共用同一宽度 | ✅ `panelWidth` 不区分工具 |
| 展开/折叠 | ⌥⌘O 展开至全宽，两工具均支持 | ✅ 共享逻辑 |
| 布局切换按钮 | 仅 Yazi 模式显示 | ✅ `if currentTool == .yazi` 条件渲染 |
| 工具 Tab 高亮 | 当前激活 tab 显示强调色 | ✅ `isActive` 背景 + foregroundStyle |
| 面板状态持久化 | 重启后恢复上次激活的工具 | ✅ `WorkspaceModel.leftPanelTool: LeftPanelTool` 编解码 |
| 多窗口隔离 | ⌥⌘G 仅影响 keyWindow | ✅ `notification.object as? NSWindow == windowProvider()` |
| LazyGit session 生命周期 | 关闭 workspace 时释放 | ✅ `WorkspaceManager` 调用 `lazygitStore.removeSurface` |
| LazyGit Popup 已移除 | 旧弹出层不再出现 | ✅ `PopupOverlayManager` 已清除 lazygit 相关代码 |

---

## 五、架构说明

**方案**: Option A — 扩展现有 Yazi 面板（YaziPanel → LeftPanel）

**新增/修改文件**:

| 文件 | 变更类型 | 说明 |
|------|----------|------|
| `LazyGitSurfaceStore.swift` | 新增 | `@MainActor` class，per-workspace LazyGit surface 生命周期管理 |
| `LeftPanelToolbar.swift` | 重命名+扩展 | 原 `YaziPanelToolbar`；新增工具 tab 切换；布局按钮条件显示 |
| `LeftPanelView.swift` | 重命名+扩展 | 原 `YaziPanelView`；switch 渲染 yazi/lazygit 内容 |
| `WorkspaceModel.swift` | 修改 | 新增 `leftPanelTool: LeftPanelTool` 持久化字段 |
| `WorkspaceManager.swift` | 修改 | 注入 `lazygitSurfaceStore`，workspace 删除时清理 |
| `PolterttyRootView.swift` | 修改 | 状态管理、三段式切换逻辑、多窗口通知隔离 |
| `PopupOverlayManager.swift` | 修改 | 移除 lazygit 弹出逻辑 |
| `AppDelegate.swift` | 修改 | `toggleGitPanel` 替换 `toggleLazygitPopup` |
| `TerminalController.swift` | 修改 | 删除 `toggleLazygitPopup` |
| `KeyboardShortcutsPanelView.swift` | 修改 | 标签更新为 "Git Panel" |

---

## 六、提交记录

| 提交 | 说明 |
|------|------|
| `774bf2c43` | a11y: add accessibility label and selected trait to tool tab buttons |
| `a13c147c7` | fix: add explicit return in toolTabButton to fix opaque return type error |
| `a501d34e8` | fix: guard nil window in toggleGitPanel |
| `fc7f2036a` | feat: update keyboard shortcuts panel |
| `425285ba2` | feat: remove toggleLazygitPopup from TerminalController |
| `f1e89d32c` | feat: update AppDelegate |
| `6a11d2495` | feat: remove lazygit from PopupOverlayManager |
| `40486563d` | fix: window isolation + handleToggleLeftPanel helper |
| `6d66c0138` | feat: update PolterttyRootView |
| `515599e3e` | fix: use LeftPanelTool enum in WorkspaceModel, MainActor cleanup |
| `56bcfc93e` | feat: add lazygitSurfaceStore to WorkspaceManager |
| `70d38755d` | feat: add leftPanelTool field to WorkspaceModel |
| `e955f3ec7` | feat: rename YaziPanelView to LeftPanelView |
| `3a159303b` | fix: rename to LeftPanelToolbar.swift |
| `3359bbefd` | feat: rename YaziPanelToolbar to LeftPanelToolbar |
| `778e3d8bc` | fix: @MainActor and deinit cleanup in LazyGitSurfaceStore |
| `9fd9979ba` | feat: add LazyGitSurfaceStore |

---

**结论**: 所有发现的问题均已修复，审计得分 19/20 (Excellent)，无阻断性或主要问题遗留，可合并至 main。
