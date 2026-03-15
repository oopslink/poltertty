# Poltertty

Ghostty 终端模拟器的 fork，添加 Workspace 管理功能。macOS only，Swift/SwiftUI，跟踪上游。

## 构建

```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build
```

仅检查 Swift 编译错误：
```bash
xcodebuild ... 2>&1 | grep "\.swift:" | grep "error:"
```

## 规则

- 开发 Workspace 相关功能时，必须先阅读 [docs/workspace-rules.md](docs/workspace-rules.md)
