# Poltertty 构建和发布规则

## 概述

本文档规范了 Poltertty 项目的构建和发布流程，确保开发、测试和发布的一致性。

---

## ⚠️ 重要：构建前必读

**为了避免代码签名错误和构建失败，每次构建前必须清理 Xcode DerivedData 缓存。**

### 快速清理命令

```bash
# 方式 1: 标准清理（推荐）
rm -rf ~/Library/Developer/Xcode/DerivedData/Ghostty-* && make clean

# 方式 2: 完整清理（构建失败时使用）
rm -rf ~/Library/Developer/Xcode/DerivedData/Ghostty-* && make clean && xattr -cr macos/

# 方式 3: 一键清理并构建
rm -rf ~/Library/Developer/Xcode/DerivedData/Ghostty-* && make clean && make dev
```

### 为什么需要清理？

1. **代码签名问题**：DerivedData 缓存可能包含过期的签名信息，导致 `CodeSign failed` 错误
2. **模块缓存不一致**：Swift 模块缓存可能与当前代码不匹配
3. **资源分叉**：macOS 文件系统可能添加扩展属性，干扰构建过程

### 清理时机

- ✅ 每次修改代码后准备构建时
- ✅ 构建失败后
- ✅ 切换构建模式时（Dev ↔ Release）
- ✅ 更新依赖后
- ✅ Git pull 拉取新代码后

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
| 开发构建 | `make dev` | 🔄 自动清理缓存 + Debug 模式构建 |
| 发布构建 | `make release` | 🔄 自动清理缓存 + Release 模式构建 |
| 构建并打包 | `make package` | 构建 Release 并打包 zip |
| 清理构建 | `make clean` | 清理所有构建产物 |
| 清理 Xcode | `make clean-xcode` | 清理 DerivedData 和扩展属性 |
| 完全清理 | `make clean-all` | 清理所有（包括 Xcode 缓存） |
| 运行 Dev | `make run-dev` | 构建并运行 Debug 版本 |
| 运行 Release | `make run-release` | 构建并运行 Release 版本 |
| 检查错误 | `make check` | 仅检查 Swift 编译错误 |

**📌 注意：** `make dev` 和 `make release` 已内置自动清理 DerivedData 缓存，无需手动执行清理命令。

---

## 详细流程

### 开发流程（Dev）

```bash
# 1. 拉取最新代码
git pull origin main

# 2. 清理缓存（重要！）
rm -rf ~/Library/Developer/Xcode/DerivedData/Ghostty-*
make clean

# 3. 构建开发版本
make dev

# 4. 运行测试
make run-dev

# 5. 修改代码后重新构建
# ⚠️ 每次修改后都应清理缓存
rm -rf ~/Library/Developer/Xcode/DerivedData/Ghostty-*
make dev

# 6. 提交代码
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

# 3. 彻底清理缓存（关键步骤！）
rm -rf ~/Library/Developer/Xcode/DerivedData/Ghostty-*
rm -rf ~/Library/Caches/org.swift.swiftpm
make clean
xattr -cr macos/

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

### 1. **构建失败：Code Sign Error** ⚠️

**问题：** 代码签名失败，错误信息：
```
resource fork, Finder information, or similar detritus not allowed
Command CodeSign failed with a nonzero exit code
```

**原因：**
- Xcode DerivedData 缓存包含过期的签名信息或损坏的模块缓存
- .app 包中包含 macOS 资源分叉（resource fork）或 Finder 扩展属性
- 构建缓存与当前代码状态不一致

**✅ 标准解决流程（99% 有效）：**

```bash
# 步骤 1: 清理 DerivedData 缓存（最重要）
rm -rf ~/Library/Developer/Xcode/DerivedData/Ghostty-*

# 步骤 2: 清理项目构建产物
make clean

# 步骤 3: 清理扩展属性（可选，但推荐）
xattr -cr macos/

# 步骤 4: 重新构建
make dev  # 或 make release
```

**🔧 完整清理流程（如果上述方法失败）：**

```bash
# 清理所有可能的缓存
rm -rf ~/Library/Developer/Xcode/DerivedData/*
rm -rf ~/Library/Caches/org.swift.swiftpm
find . -name "._*" -delete
find macos -type f -exec xattr -c {} \; 2>/dev/null
make clean

# 重新构建
make dev
```

**📋 快速命令（复制即用）：**

```bash
# 一键清理并构建 Dev
rm -rf ~/Library/Developer/Xcode/DerivedData/Ghostty-* && make clean && xattr -cr macos/ && make dev

# 一键清理并构建 Release
rm -rf ~/Library/Developer/Xcode/DerivedData/Ghostty-* && make clean && xattr -cr macos/ && make release
```

**🛡️ 预防措施：**
- ✅ **每次构建前清理 DerivedData**（养成习惯）
- ✅ 避免在 Finder 中复制粘贴 .app 文件（使用 `cp -r` 代替）
- ✅ 避免使用第三方工具修改 .app 包
- ✅ 定期运行 `make clean`
- ✅ 构建失败后第一反应：清理缓存

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

3. **✅ 强制清理构建缓存（重要）**
   - **每次构建前必须清理 DerivedData 缓存**，防止代码签名和编译问题
   - 使用以下命令：
     ```bash
     # 标准清理流程（推荐）
     make clean && rm -rf ~/Library/Developer/Xcode/DerivedData/Ghostty-*
     make dev  # 或 make release
     ```
   - 为什么需要清理：
     - Xcode DerivedData 缓存可能包含过期的签名信息
     - 资源分叉和扩展属性会导致 codesign 失败
     - 避免 Swift 模块缓存不一致
   - 清理频率：
     - ✅ **修改代码后准备构建时**
     - ✅ **构建失败时**
     - ✅ **切换构建模式时（Dev ↔ Release）**
     - ✅ **更新依赖后**

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

- **2026-03-16**:
  - 初始版本，规范化 Dev/Release 构建流程
  - 添加强制清理 DerivedData 缓存的规则
  - 更新 Makefile，`make dev` 和 `make release` 自动清理缓存
  - 添加代码签名错误的完整解决方案
  - 强调构建前清理的重要性和最佳实践
