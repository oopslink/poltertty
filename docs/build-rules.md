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

- ✅ 构建失败且排除代码错误后
- ✅ 切换构建模式时（Dev ↔ Release）
- ✅ 更新依赖后
- ❌ **不需要**每次修改代码后清理（使用增量构建 `make dev`）

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
| 开发构建 | `make dev` | ⚡ 增量构建，快速迭代 |
| 开发构建(清理) | `make dev-clean` | 🔄 清理缓存 + Debug 模式构建 |
| 发布构建 | `make release` | 🔄 自动清理缓存 + Release 模式构建 |
| 构建并打包 | `make package` | 构建 Release 并打包 zip |
| 清理构建 | `make clean` | 清理所有构建产物 |
| 清理 Xcode | `make clean-xcode` | 清理 DerivedData 和扩展属性 |
| 完全清理 | `make clean-all` | 清理所有（包括 Xcode 缓存） |
| 运行 Dev | `make run-dev` | 构建并运行 Debug 版本 |
| 运行 Release | `make run-release` | 构建并运行 Release 版本 |
| 检查错误 | `make check` | 仅检查 Swift 编译错误 |

**📌 注意：**
- `make dev` 使用增量构建，速度快，适合日常开发迭代
- `make dev-clean` 在构建失败或切换模式时使用，会清理 DerivedData 缓存
- `make release` 始终清理缓存，确保发布版本的一致性

---

## 详细流程

### 开发流程（Dev）

```bash
# 1. 拉取最新代码
git pull origin main

# 2. 构建开发版本（增量构建，快速）
make dev

# 3. 运行测试
make run-dev

# 4. 修改代码后重新构建（增量，只编译改动部分）
make dev

# 5. 如果构建失败或出现奇怪错误，清理后重建
make dev-clean

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

# 2. 更新版本号（两处必须同步！）
# ⚠️ build.zig.zon 和 Xcode project.pbxproj 版本必须一致，且与 git tag 匹配

# 2a. 更新 build.zig.zon（Zig 构建系统使用，必须与 git tag 完全一致）
#     编辑 build.zig.zon，将 .version = "x.y.z" 改为新版本
sed -i '' 's/\.version = ".*"/\.version = "0.1.1"/' build.zig.zon

# 2b. 更新 Xcode 项目版本号（影响 About 页面显示）
#     更新 macos/Ghostty.xcodeproj/project.pbxproj 中所有 poltertty 目标的 MARKETING_VERSION
sed -i '' 's/MARKETING_VERSION = 0\.1\.0;/MARKETING_VERSION = 0.1.1;/g' macos/Ghostty.xcodeproj/project.pbxproj

# 2c. 提交版本更改
git add build.zig.zon macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "chore: bump version to 0.1.1"

# 3. 彻底清理缓存（关键步骤！）
rm -rf ~/Library/Developer/Xcode/DerivedData/Ghostty-*
rm -rf ~/Library/Caches/org.swift.swiftpm
make clean
xattr -cr macos/

# ⚠️ 清理 DerivedData 后，Xcode 需要重新下载 Swift Package（Sparkle 等）
# 如果网络不稳定，提前手动克隆以避免下载失败：
DERIVED=$(ls ~/Library/Developer/Xcode/DerivedData/ | grep Ghostty | head -1)
mkdir -p ~/Library/Developer/Xcode/DerivedData/$DERIVED/SourcePackages/repositories
git clone --bare https://github.com/sparkle-project/Sparkle \
  ~/Library/Developer/Xcode/DerivedData/$DERIVED/SourcePackages/repositories/Sparkle-09d89c53

# 4. 创建 Git tag（必须在构建前打 tag，Zig 构建系统会读取 tag 版本）
git tag -a v0.1.1 -m "Release version 0.1.1"

# 5. 打包（同时完成构建）
make package

# 6. 推送代码和 tag
git push origin main
git push origin v0.1.1

# 7. 创建 GitHub Release
gh release create v0.1.1 \
  macos/build/Poltertty-v0.1.1.zip \
  --title "Poltertty v0.1.1" \
  --notes "Release notes here"
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

### 2. **构建失败：Sparkle 包下载网络中断** ⚠️

**问题：** 清理 DerivedData 后，Xcode 需要重新从 GitHub 克隆 Sparkle，网络不稳定时报错：
```
error: RPC failed; curl 56 Recv failure: Connection reset by peer
fatal: early EOF
xcodebuild: error: Could not resolve package dependencies:
  Failed to clone repository https://github.com/sparkle-project/Sparkle
```

**原因：** `make clean` 或 `make clean-xcode` 删除了 DerivedData，其中包含已缓存的 Swift Package（Sparkle）。

**✅ 解决方案：手动预克隆 Sparkle**

```bash
# 找到 DerivedData 目录名（先运行一次构建，让 Xcode 创建目录）
DERIVED=$(ls ~/Library/Developer/Xcode/DerivedData/ | grep Ghostty | head -1)

# 手动克隆 Sparkle 到期望位置
mkdir -p ~/Library/Developer/Xcode/DerivedData/$DERIVED/SourcePackages/repositories
git clone --bare https://github.com/sparkle-project/Sparkle \
  ~/Library/Developer/Xcode/DerivedData/$DERIVED/SourcePackages/repositories/Sparkle-09d89c53

# 然后重新构建
make package
```

**🛡️ 预防措施：**
- 在网络稳定的环境下执行清理操作
- 清理后第一次构建失败时，用上述方法手动克隆，无需重复下载

---

### 3. **构建失败：Zig tag 版本不匹配** ⚠️

**问题：** 打了 git tag 后构建时 Zig panic：
```
thread panic: tagged releases must be in vX.Y.Z format matching build.zig
src/build/Config.zig: @panic("tagged releases must be in vX.Y.Z format matching build.zig")
```

**原因：** `build.zig.zon` 中的 `.version` 字段必须与当前 git tag 完全一致。如果 tag 是 `v0.1.1` 但 `build.zig.zon` 中是 `1.3.0`（上游版本），构建就会 panic。

**✅ 解决方案：发布前同步 build.zig.zon 版本**

```bash
# 确认当前 build.zig.zon 版本
grep "version" build.zig.zon

# 更新为与 git tag 匹配的版本（在打 tag 之前！）
sed -i '' 's/\.version = ".*"/\.version = "0.1.1"/' build.zig.zon

# 提交后再打 tag
git add build.zig.zon
git commit -m "chore: bump version to 0.1.1"
git tag -a v0.1.1 -m "Release version 0.1.1"
```

**⚠️ 重要：**
- 每次发布必须同时更新 `build.zig.zon` 和 `project.pbxproj` 中的版本号
- **必须在打 tag 之前**更新 `build.zig.zon`，否则需要删除 tag 重建
- 删除并重建 tag：`git tag -d v0.1.1 && git tag -a v0.1.1 -m "Release version 0.1.1"`

---

### 4. **构建失败：zig-out 目录不存在**

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

# 从命令行直接运行查看错误（最有效的诊断方式！）
~/Library/Developer/Xcode/DerivedData/Ghostty-*/Build/Products/Debug/Poltertty.app/Contents/MacOS/ghostty
```

**📌 诊断技巧：** `open Poltertty.app` 失败时不会显示错误原因，务必直接运行 binary 查看 stderr 输出，崩溃信息会直接打印出来。

---

### 5. **运行时崩溃：SwiftUI EnvironmentObject 未注入** ⚠️

**问题：** app 打开即崩溃，命令行运行 binary 报错：
```
Fatal error: No ObservableObject of type App found.
A View.environmentObject(_:) for App may be missing as an ancestor of this view.
```

**原因：** 某个 SwiftUI View 使用了 `@EnvironmentObject`，但其渲染路径上的父视图没有调用 `.environmentObject()` 注入。

常见场景：重构时将一个子 View 提升到更高层级渲染，脱离了原来的注入链。例如：
- `TerminalView` 里注入了 `.environmentObject(ghostty)`
- 但 `PolterttyRootView` 直接渲染 `Ghostty.SurfaceWrapper`（绕过了 `TerminalView`）
- `SurfaceWrapper` 内部依赖 `@EnvironmentObject var ghostty: Ghostty.App`，找不到注入 → crash

**✅ 解决方案：**

1. 找到崩溃的 View 及其所需的 EnvironmentObject 类型
2. 沿渲染树向上找到最近的注入点，确认哪条路径漏掉了注入
3. 在调用处补充 `.environmentObject(xxx)` 注入，或将依赖的对象通过参数传递下去

**🛡️ 预防措施：**
- 将子 View 提升层级或在新的渲染分支复用时，检查该 View 所有 `@EnvironmentObject` 依赖是否在新路径上都有注入
- 新建渲染分支（如直接在 `NSHostingView` 包裹某 View）时，逐一检查 `@EnvironmentObject` 依赖

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

⚠️ **发布时必须同步更新两处版本号，且顺序很重要：**

#### 1. `build.zig.zon`（最重要，必须与 git tag 完全一致）

```bash
# Zig 构建系统在检测到 git tag 时，会校验此版本与 tag 是否匹配
# 不一致会导致构建 panic
sed -i '' 's/\.version = ".*"/\.version = "0.1.1"/' build.zig.zon
```

#### 2. `macos/Ghostty.xcodeproj/project.pbxproj`（影响 About 页面版本显示）

```bash
# 更新所有 poltertty 相关目标的 MARKETING_VERSION
sed -i '' 's/MARKETING_VERSION = 旧版本;/MARKETING_VERSION = 新版本;/g' \
  macos/Ghostty.xcodeproj/project.pbxproj
```

#### 正确的版本更新顺序

```bash
# 1. 先更新两处版本号并提交
sed -i '' 's/\.version = ".*"/\.version = "0.1.1"/' build.zig.zon
# (更新 project.pbxproj 中的 MARKETING_VERSION)
git add build.zig.zon macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "chore: bump version to 0.1.1"

# 2. 再打 tag（构建时 Zig 会读取 tag，与 build.zig.zon 对比）
git tag -a v0.1.1 -m "Release version 0.1.1"

# 3. 最后构建
make package
```

---

## 最佳实践

1. **开发时始终使用 Dev 模式**
   - 更快的编译速度
   - 完整的调试信息

2. **发布前必须使用 Release 模式测试**
   - 确保优化后的代码正常工作
   - 验证性能表现

3. **使用增量构建加速开发**
   - 日常开发使用 `make dev`（增量构建），仅编译改动部分
   - 只在构建失败时使用 `make dev-clean`（清理缓存后全量重建）
   - `make release` 始终自动清理，确保发布一致性

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

- **2026-03-17**:
  - 新增故障排查：SwiftUI EnvironmentObject 未注入导致启动即崩溃的诊断和修复方法
  - 新增诊断技巧：直接运行 binary 查看 stderr 是定位 crash 原因的最有效方式
  - 新增 xattr -cr 可以在不完整清理 DerivedData 的情况下修复代码签名失败

- **2026-03-16** (v0.1.1 发布后更新):
  - 完善发布流程：明确 `build.zig.zon` 和 `project.pbxproj` 两处版本号必须同步
  - 新增故障排查：Sparkle 包下载网络中断的解决方案（手动 `git clone --bare`）
  - 新增故障排查：Zig tag 版本不匹配的原因和修复方法
  - 更新发布流程：强调必须在打 tag 之前更新 `build.zig.zon`
  - 新增 `gh release create` 命令到发布流程

- **2026-03-16** (初始版本):
  - 初始版本，规范化 Dev/Release 构建流程
  - 添加强制清理 DerivedData 缓存的规则
  - 更新 Makefile，`make dev` 和 `make release` 自动清理缓存
  - 添加代码签名错误的完整解决方案
  - 强调构建前清理的重要性和最佳实践
