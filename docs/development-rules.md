# Poltertty 特性开发规则

## 分支保护

**main 分支受保护**：禁止任何直接提交（包括 `git push`、`git merge`、`git rebase` 到 main），所有变更必须经由 Pull Request 合并。

## 特性开发流程

1. **隔离开发**：所有特性开发必须使用 git worktree 进行隔离（使用 `superpowers:using-git-worktrees` skill）
   - **Worktree 位置**：必须创建在 workspace root 的 `.worktrees/` 目录下，例如 `git worktree add .worktrees/<feature-name> <branch>`
2. **Pull Request**：开发完成后必须通过 Pull Request 合并到 main 分支

## 相关文档

- [构建和发布规则](build-rules.md)
- [Workspace 开发规则](workspace-rules.md)
