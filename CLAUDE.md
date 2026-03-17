# Poltertty

Ghostty 终端模拟器的 fork，添加 Workspace 管理功能。macOS only，Swift/SwiftUI，跟踪上游。

## 快速开始

### 开发构建（Dev）
```bash
# 增量构建（推荐，快速）
make dev

# 构建并运行
make run-dev

# 清理后重建（构建失败时使用）
make dev-clean
```

### 发布构建（Release）
```bash
# 构建 Release 版本
make release

# 构建并打包
make package

# 运行 Release 版本
make run-release
```

### 其他命令
```bash
# 查看所有可用命令
make help

# 仅检查 Swift 编译错误
make check

# 清理构建产物
make clean

# 初始化本地 Git Hooks（新克隆仓库后执行一次）
make init-git-hooks
```

## 规则

- **构建和发布**: 必须遵循 [docs/build-rules.md](docs/build-rules.md) 规范
- **Workspace 开发**: 必须先阅读 [docs/workspace-rules.md](docs/workspace-rules.md)
- **语言**: 所有回复必须使用中文，禁止使用韩文
- **特性开发流程**:
  - 所有特性开发必须使用 git worktree 进行隔离开发（使用 `superpowers:using-git-worktrees` skill）
  - 开发完成后必须通过 Pull Request 合并到 main 分支
  - **main 分支受保护**：禁止任何直接提交（包括 `git push`、`git merge`、`git rebase` 到 main），所有变更必须经由 PR 合并
