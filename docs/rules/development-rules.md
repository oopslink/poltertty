# Poltertty 特性开发规则

## 分支保护

**main 分支受保护**：禁止任何直接提交（包括 `git push`、`git merge`、`git rebase` 到 main），所有变更必须经由 Pull Request 合并。

## 特性开发流程

1. **隔离开发**：所有特性开发必须使用 git worktree 进行隔离（使用 `superpowers:using-git-worktrees` skill）
   - **Worktree 位置**：必须创建在 workspace root 的 `.worktrees/` 目录下，例如 `git worktree add .worktrees/<feature-name> <branch>`
2. **Pull Request**：开发完成后必须通过 Pull Request 合并到 main 分支

## PR 定向 Review：焦点与光标

每个 PR 合并前，必须对以下两类已知高频问题进行定向 review，确认不引入回归：

### 1. 光标空心方块

**已知根因**：`syncFocusToSurfaceTree` 在 `focusedSurface == nil` 时对所有 surface 调用 `focusDidChange(false)`，覆盖 `becomeFirstResponder` 已正确设置的 focus。

**Review 检查点**：
- `BaseTerminalController.syncFocusToSurfaceTree`：当 `focusedSurface == nil` 时必须回退到 `window.firstResponder` 判断，禁止直接将所有 surface 设为 unfocused
- `SurfaceView_AppKit.focusDidChange`：`guard self.focused != focused` 保护逻辑不得被移除
- `SurfaceView_AppKit.focused` 初始值必须为 `false`（不得改回 `true`）
- 任何新增的 `windowDidBecomeKey` / `syncFocusToSurfaceTree` 调用路径，必须确认 `focusedSurface` 有值或使用 firstResponder 作为 fallback

### 2. 上下分屏焦点切换

**已知根因**：`localEventLeftMouseDown` 通过 `SurfaceView` 直接做 hitTest，坐标转换途经 `NSClipView(isFlipped=true)` 链路，在竖向分屏时不准确，导致底部 pane 错误抢占焦点。

**Review 检查点**：
- `SurfaceView_AppKit.localEventLeftMouseDown`：点击范围检测必须使用 `SurfaceScrollView`（`self.superview?.superview?.superview?.superview`）做 bounds 检查，禁止直接对 `self` 做 `hitTest` 或 `convert+bounds` 用于分屏场景
- 任何修改 `SurfaceScrollView` 视图层级（superview 深度）的变更，必须同步更新 `localEventLeftMouseDown` 中的 superview 链长度
- 新增 event monitor 或 mouse 事件处理时，检查是否绕过了上述 bounds 检查

### 3. 多窗口通知隔离

**已知根因**：`NotificationCenter.default.post(name:, object: nil)` 发出全局通知，所有订阅该通知名的视图（每个窗口各一个实例）同时响应，导致操作广播到所有窗口。

**Review 检查点**：
- 任何 per-window 快捷键/菜单项的 action，其 `NotificationCenter.post` 必须携带 `object: workspaceId`（或 `windowId`），**禁止** `object: nil`
- `PolterttyRootView`（或其他 per-window 视图）中的 `onReceive`，若通知来源于菜单/快捷键，必须在闭包内过滤 `notification.object`，只响应自己的 workspace
- 新增通知时，先判断该通知是"全局广播"还是"单窗口操作"——全局广播（如 app 级 toggle）才允许 `object: nil`

**快速识别方法**：搜索 `NotificationCenter.default.post(name:.*object: nil`，逐条确认是否为全局行为。

### 4. 初始渲染时序（AppKit ↔ SwiftUI 桥接）

**已知根因**：通过 `DispatchQueue.main.async` 延迟一帧应用 AppKit layout 约束时，SwiftUI 视图在第一帧已用默认/错误的初始值渲染，导致概率性布局异常（如 tab 出现在左侧）。

**Review 检查点**：
- 任何依赖 `DispatchQueue.main.async` 才能生效的 AppKit 布局（如 `expandWorkspaceToolbarItem`），必须确认"约束生效前"的初始状态也符合预期——通常通过给 SwiftUI 侧的初始值设一个合理的近似值（如窗口宽度）来保证
- `ToolbarWidthTracker` 等从 AppKit 侧异步更新的 `ObservableObject`，初始值必须设为"宽松值"（偏大），避免 SwiftUI 布局因初始值过小而压缩
- 新增"延迟一帧后生效"的初始化逻辑时，必须同时问：**如果这帧延迟不发生（失败/极快展示），UI 是否仍然正确？**

## TODO 管理

- 所有 TODO 统一存放在项目根目录 `todos/` 下，禁止在其他位置创建 TODO 文件
- 每个 TODO 主题一个独立 `.md` 文件，命名用英文短横线分隔（如 `agent-ctrl-api.md`）
- 完成的条目标记为 `[x]`，全部完成后删除文件或移至 `todos/done/`

## 相关文档

- [构建和发布规则](build-rules.md)
- [Workspace 开发规则](workspace-rules.md)
