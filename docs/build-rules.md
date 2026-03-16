# Poltertty 构建和发布规则

## 概述

本文档规范了 Poltertty 项目的构建和发布流程，确保开发、测试和发布的一致性。

---

## 构建模式

### 1. **Dev（开发模式）**

用于日常开发、调试和快速迭代。

**特点：**
- Debug 配置
- 包含调试符号
- Ad-hoc 代码签名
- 快速编译
- 无优化

**使用场景：**
- 功能开发
- 本地调试
- UI 调整
- 快速测试

**构建命令：**
```bash
# 方式 1: 使用 Makefile（推荐）
make dev

# 方式 2: 使用脚本
./scripts/build.sh dev

# 方式 3: 直接使用 xcodebuild
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build
```

**输出位置：**
```
~/Library/Developer/Xcode/DerivedData/Ghostty-*/Build/Products/Debug/Poltertty.app
```

### 2. **Release（发布模式）**

用于正式发布、性能测试和分发。

**特点：**
- Release 配置
- 代码优化
- 去除调试符号
- 体积更小
- 性能更好

**使用场景：**
- 正式发布
- 性能测试
- 用户分发
- App Store 提交

**构建命令：**
```bash
# 方式 1: 使用 Makefile（推荐）
make release

# 方式 2: 使用脚本（带打包）
./scripts/build.sh release --zip

# 方式 3: 仅构建不打包
./scripts/build.sh release
```

**输出位置：**
```
macos/build/ReleaseLocal/Poltertty.app
macos/build/Poltertty-{version}.zip  # 使用 --zip 参数时
```

---

## 快速参考

| 任务 | 命令 | 说明 |
|------|------|------|
| 开发构建 | `make dev` | Debug 模式，快速编译 |
| 发布构建 | `make release` | Release 模式，优化编译 |
| 构建并打包 | `make package` | 构建 Release 并打包 zip |
| 清理构建 | `make clean` | 清理所有构建产物 |
| 运行 Dev | `make run-dev` | 构建并运行 Debug 版本 |
| 运行 Release | `make run-release` | 构建并运行 Release 版本 |
| 检查错误 | `make check` | 仅检查 Swift 编译错误 |

---

## 详细流程

### 开发流程（Dev）

```bash
# 1. 拉取最新代码
git pull origin main

# 2. 构建开发版本
make dev

# 3. 运行测试
make run-dev

# 4. 修改代码后重新构建
make dev

# 5. 提交代码
git add .
git commit -m "feat: add new feature"
git push
```

### 发布流程（Release）

```bash
# 1. 确保在 main 分支且代码已同步
git checkout main
git pull origin main

# 2. 更新版本号（如需要）
# 编辑 macos/Sources/App/Info.plist

# 3. 清理旧构建
make clean

# 4. 构建发布版本
make release

# 5. 测试发布版本
make run-release

# 6. 打包分发
make package

# 7. 创建 Git tag
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0

# 8. 上传发布包
# 将 macos/build/Poltertty-v1.0.0.zip 上传到 GitHub Releases
```

---

## 构建脚本说明

### scripts/build.sh

**参数：**
- `$1`: 构建模式（`dev` 或 `release`）
- `$2`: 可选参数 `--zip` 用于打包

**示例：**
```bash
# 开发构建
./scripts/build.sh dev

# 发布构建
./scripts/build.sh release

# 发布构建并打包
./scripts/build.sh release --zip
```

---

## 构建要求

### 环境依赖

- **macOS**: 13.0 或更高
- **Xcode**: 15.0 或更高
- **Zig**: 0.15.2 或更高
- **命令行工具**: `xcodebuild`, `codesign`, `ditto`

### 检查环境

```bash
# 检查 Xcode
xcodebuild -version

# 检查 Zig
zig version

# 检查命令行工具
xcode-select -p
```

---

## 故障排查

### 1. **构建失败：Code Sign Error**

**问题：** 代码签名失败

**解决：**
```bash
# 清理扩展属性
xattr -cr ~/Library/Developer/Xcode/DerivedData/Ghostty-*/Build/Products/Debug/Poltertty.app

# 重新构建
make dev
```

### 2. **构建失败：zig-out 目录不存在**

**问题：** 缺少 Zig 构建产物

**解决：**
```bash
# 先运行 Zig 构建
zig build

# 再运行 Xcode 构建
make dev
```

### 3. **构建失败：Swift 编译错误**

**问题：** Swift 代码有语法错误

**解决：**
```bash
# 仅检查 Swift 错误
make check

# 查看详细错误信息
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | grep "\.swift:" | grep "error:"
```

### 4. **应用无法打开**

**问题：** 运行时崩溃或无法启动

**解决：**
```bash
# 查看崩溃日志
log show --predicate 'process == "Poltertty"' --last 5m

# 从命令行直接运行查看错误
~/Library/Developer/Xcode/DerivedData/Ghostty-*/Build/Products/Debug/Poltertty.app/Contents/MacOS/ghostty
```

---

## 代码签名

### 开发签名（Ad-hoc）

Dev 模式使用 ad-hoc 签名，仅用于本地运行：

```bash
codesign --force --sign - Poltertty.app
```

### 发布签名（Distribution）

Release 模式应使用开发者证书签名：

```bash
# 查看可用证书
security find-identity -v -p codesigning

# 使用指定证书签名
codesign --force --deep --sign "Developer ID Application: Your Name" Poltertty.app
```

---

## CI/CD 集成

### GitHub Actions 示例

```yaml
name: Build and Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Zig
        uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.15.2

      - name: Build Release
        run: make release

      - name: Package
        run: make package

      - name: Upload Release
        uses: actions/upload-artifact@v3
        with:
          name: Poltertty
          path: macos/build/Poltertty-*.zip
```

---

## 版本管理

### 版本号格式

遵循 [Semantic Versioning](https://semver.org/):

- **MAJOR.MINOR.PATCH** (例如: 1.2.3)
  - MAJOR: 不兼容的 API 变更
  - MINOR: 向后兼容的新功能
  - PATCH: 向后兼容的问题修复

### 更新版本号

编辑 `macos/Sources/App/Info.plist`:

```xml
<key>CFBundleShortVersionString</key>
<string>1.0.0</string>
<key>CFBundleVersion</key>
<string>1</string>
```

---

## 最佳实践

1. **开发时始终使用 Dev 模式**
   - 更快的编译速度
   - 完整的调试信息

2. **发布前必须使用 Release 模式测试**
   - 确保优化后的代码正常工作
   - 验证性能表现

3. **清理构建产物**
   - 切换模式前运行 `make clean`
   - 避免缓存问题

4. **版本控制**
   - 每次发布前打 tag
   - 保持 tag 和版本号一致

5. **测试覆盖**
   - Dev 构建后进行功能测试
   - Release 构建后进行性能测试

---

## 相关文档

- [Workspace 开发规则](workspace-rules.md)
- [项目 README](../README.md)
- [CLAUDE.md](../CLAUDE.md)

---

## 更新日志

- **2026-03-16**: 初始版本，规范化 Dev/Release 构建流程
