# Poltertty

Ghostty 终端模拟器的 fork，添加 Workspace 管理功能。macOS only，Swift/SwiftUI，跟踪上游。

## 快速开始

### 开发构建（Dev）
```bash
# 使用 Makefile（推荐）
make dev

# 或直接运行
make run-dev
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
```

## 规则

- **构建和发布**: 必须遵循 [docs/build-rules.md](docs/build-rules.md) 规范
- **Workspace 开发**: 必须先阅读 [docs/workspace-rules.md](docs/workspace-rules.md)
