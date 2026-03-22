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

## TODO 管理

- 所有 TODO 统一存放在项目根目录 `todos/` 下，禁止在其他位置创建 TODO 文件
- 每个 TODO 主题一个独立 `.md` 文件，命名用英文短横线分隔（如 `agent-ctrl-api.md`）
- 完成的条目标记为 `[x]`，全部完成后删除文件或移至 `todos/done/`

## 相关文档

- [构建和发布规则](build-rules.md)
- [Workspace 开发规则](workspace-rules.md)
