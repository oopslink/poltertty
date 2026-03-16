# Rebrand Ghostty → Poltertty Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将所有用户可见的 "Ghostty" 字样替换为 "Poltertty"，提供一致的品牌体验。

**Architecture:** 逐文件精准修改，只改用户可见字符串，不动代码结构（类名、函数名、C 接口等）。配置路径通过 Swift 层传入自定义路径来实现 `~/.config/poltertty/config` 的切换，无需修改底层 Zig/C 核心。

**Tech Stack:** Swift/SwiftUI, macOS only。无需新依赖。

---

## Chunk 1: UI 字符串替换

### Task 1: main.swift — 初始化失败错误信息

**Files:**
- Modify: `macos/Sources/App/macOS/main.swift:16-19`

- [ ] **Step 1: 修改错误文本**

将：
```swift
"Ghostty failed to initialize! If you're executing Ghostty from the command line\n" +
"then this is usually because an invalid action or multiple actions were specified.\n" +
"Actions start with the `+` character.\n\n" +
"View all available actions by running `ghostty +help`.\n"
```
改为：
```swift
"Poltertty failed to initialize! If you're executing Poltertty from the command line\n" +
"then this is usually because an invalid action or multiple actions were specified.\n" +
"Actions start with the `+` character.\n\n" +
"View all available actions by running `poltertty +help`.\n"
```

- [ ] **Step 2: 验证编译无报错**

```bash
make check
```
Expected: 编译成功，无错误

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/App/macOS/main.swift
git commit -m "rebrand: update CLI error message to Poltertty"
```

---

### Task 2: AppDelegate.swift — 退出确认对话框 & 执行文件确认对话框 & Help URL

**Files:**
- Modify: `macos/Sources/App/macOS/AppDelegate.swift:432,434,530,1121`

- [ ] **Step 1: 修改 Quit 对话框（~line 432-434）**

`"Quit Ghostty?"` → `"Quit Poltertty?"`
`"Close Ghostty"` → `"Close Poltertty"`

- [ ] **Step 2: 修改执行文件确认对话框（~line 530）**

`"Allow Ghostty to execute \"\(filename)\"?"` → `"Allow Poltertty to execute \"\(filename)\"?"`

- [ ] **Step 3: 为 Help URL 添加 TODO 注释（~line 1121）**

将：
```swift
guard let url = URL(string: "https://ghostty.org/docs") else { return }
```
改为：
```swift
// TODO: Update to poltertty docs site when available
guard let url = URL(string: "https://ghostty.org/docs") else { return }
```

- [ ] **Step 4: 验证编译无报错**

```bash
make check
```
Expected: 编译成功，无错误

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/App/macOS/AppDelegate.swift
git commit -m "rebrand: update dialog messages to Poltertty, add TODO for help URL"
```

---

### Task 3: ErrorView.swift — 崩溃提示文本

**Files:**
- Modify: `macos/Sources/Features/Terminal/ErrorView.swift:13`

- [ ] **Step 1: 修改错误提示**

将：
```swift
Text("Something went fatally wrong.\nCheck the logs and restart Ghostty.")
```
改为：
```swift
Text("Something went fatally wrong.\nCheck the logs and restart Poltertty.")
```

- [ ] **Step 2: 验证编译无报错**

```bash
make check
```
Expected: 编译成功，无错误

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Terminal/ErrorView.swift
git commit -m "rebrand: update fatal error view to Poltertty"
```

---

### Task 4: SettingsView.swift — 配置文件路径提示

**Files:**
- Modify: `macos/Sources/Features/Settings/SettingsView.swift:17`

- [ ] **Step 1: 修改配置路径说明文本**

将：
```swift
"edit the file at $HOME/.config/ghostty/config.ghostty and restart Ghostty."
```
改为：
```swift
"edit the file at $HOME/.config/poltertty/config and restart Poltertty."
```

注意：文件名从 `config.ghostty` 改为 `config`，路径从 `ghostty/` 改为 `poltertty/`。

- [ ] **Step 2: 验证编译无报错**

```bash
make check
```
Expected: 编译成功，无错误

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Settings/SettingsView.swift
git commit -m "rebrand: update settings config path hint to poltertty"
```

---

### Task 5: AboutView.swift — 关于页面标题与 URL TODO

**Files:**
- Modify: `macos/Sources/Features/About/AboutView.swift:6-7,50`

- [ ] **Step 1: 修改 About 标题（line 50）**

`Text("Ghostty")` → `Text("Poltertty")`

- [ ] **Step 2: 为 URL 常量添加 TODO 注释（line 6-7）**

将：
```swift
private let githubURL = URL(string: "https://github.com/ghostty-org/ghostty")
private let docsURL = URL(string: "https://ghostty.org/docs")
```
改为：
```swift
// TODO: Update to poltertty GitHub repo when available
private let githubURL = URL(string: "https://github.com/ghostty-org/ghostty")
// TODO: Update to poltertty docs site when available
private let docsURL = URL(string: "https://ghostty.org/docs")
```

- [ ] **Step 3: 验证编译无报错**

```bash
make check
```
Expected: 编译成功，无错误

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/About/AboutView.swift
git commit -m "rebrand: update About view title to Poltertty, add TODO for URLs"
```

---

### Task 6: CyclingIconView.swift — Accessibility label

**Files:**
- Modify: `macos/Sources/Features/About/CyclingIconView.swift:29`

- [ ] **Step 1: 修改 VoiceOver 无障碍标签**

将：
```swift
.accessibilityLabel("Ghostty Application Icon")
```
改为：
```swift
.accessibilityLabel("Poltertty Application Icon")
```

- [ ] **Step 2: 验证编译无报错**

```bash
make check
```
Expected: 编译成功，无错误

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/About/CyclingIconView.swift
git commit -m "rebrand: update accessibility label to Poltertty"
```

---

### Task 7: TerminalCommandPalette.swift — 更新菜单项

**Files:**
- Modify: `macos/Sources/Features/Command Palette/TerminalCommandPalette.swift:95`

- [ ] **Step 1: 修改更新菜单文本**

`"Update Ghostty and Restart"` → `"Update Poltertty and Restart"`

- [ ] **Step 2: 验证编译无报错**

```bash
make check
```
Expected: 编译成功，无错误

- [ ] **Step 3: Commit**

```bash
git add "macos/Sources/Features/Command Palette/TerminalCommandPalette.swift"
git commit -m "rebrand: update command palette update text to Poltertty"
```

---

### Task 8: UpdatePopoverView.swift — 自动更新提示

**Files:**
- Modify: `macos/Sources/Features/Update/UpdatePopoverView.swift:65`

- [ ] **Step 1: 修改自动更新说明文本**

将：
```swift
Text("Ghostty can automatically check for updates in the background.")
```
改为：
```swift
Text("Poltertty can automatically check for updates in the background.")
```

- [ ] **Step 2: 验证编译无报错**

```bash
make check
```
Expected: 编译成功，无错误

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Update/UpdatePopoverView.swift
git commit -m "rebrand: update auto-update description to Poltertty"
```

---

### Task 9: App Intents 错误字符串

**Files:**
- Modify: `macos/Sources/Features/App Intents/GhosttyIntentError.swift:8,10`
- Modify: `macos/Sources/Features/App Intents/IntentPermission.swift:48`

- [ ] **Step 1: 修改 GhosttyIntentError.swift**

将：
```swift
case .appUnavailable: "The Ghostty app isn't properly initialized."
case .permissionDenied: "Ghostty doesn't allow Shortcuts."
```
改为：
```swift
case .appUnavailable: "The Poltertty app isn't properly initialized."
case .permissionDenied: "Poltertty doesn't allow Shortcuts."
```

- [ ] **Step 2: 修改 IntentPermission.swift（~line 48）**

将：
```swift
message: "Allow Shortcuts to interact with Ghostty?"
```
改为：
```swift
message: "Allow Shortcuts to interact with Poltertty?"
```

- [ ] **Step 3: 验证编译无报错**

```bash
make check
```
Expected: 编译成功，无错误

- [ ] **Step 4: Commit**

```bash
git add "macos/Sources/Features/App Intents/GhosttyIntentError.swift"
git add "macos/Sources/Features/App Intents/IntentPermission.swift"
git commit -m "rebrand: update App Intents error strings to Poltertty"
```

---

### Task 10: AppleScript 错误字符串

**Files:**
- Modify: `macos/Sources/Features/AppleScript/AppDelegate+AppleScript.swift:177,235`

- [ ] **Step 1: 修改 AppleScript 错误信息**

将两处：
```swift
command.scriptErrorString = "Ghostty app delegate is unavailable."
```
改为：
```swift
command.scriptErrorString = "Poltertty app delegate is unavailable."
```

- [ ] **Step 2: 验证编译无报错**

```bash
make check
```
Expected: 编译成功，无错误

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/AppleScript/AppDelegate+AppleScript.swift
git commit -m "rebrand: update AppleScript error strings to Poltertty"
```

---

### Task 11: Window 默认标题

**Files:**
- Modify: `macos/Sources/Features/Terminal/Window Styles/TitlebarTabsVenturaTerminalWindow.swift:589`
- Modify: `macos/Sources/Features/Terminal/Window Styles/TitlebarTabsTahoeTerminalWindow.swift:300`

- [ ] **Step 1: 修改 Ventura 窗口默认标题**

`"👻 Ghostty"` → `"👻 Poltertty"`

- [ ] **Step 2: 修改 Tahoe 窗口默认标题**

同上：`"👻 Ghostty"` → `"👻 Poltertty"`

- [ ] **Step 3: 验证编译无报错**

```bash
make check
```
Expected: 编译成功，无错误

- [ ] **Step 4: Commit**

```bash
git add "macos/Sources/Features/Terminal/Window Styles/TitlebarTabsVenturaTerminalWindow.swift"
git add "macos/Sources/Features/Terminal/Window Styles/TitlebarTabsTahoeTerminalWindow.swift"
git commit -m "rebrand: update default window title to Poltertty"
```

---

## Chunk 2: 配置路径切换

### Task 12: Ghostty.Config.swift — 自定义图标默认路径

**Files:**
- Modify: `macos/Sources/Ghostty/Ghostty.Config.swift:410`

- [ ] **Step 1: 修改自定义图标默认路径**

将：
```swift
let defaultValue = NSString("~/.config/ghostty/Ghostty.icns").expandingTildeInPath
```
改为：
```swift
let defaultValue = NSString("~/.config/poltertty/Poltertty.icns").expandingTildeInPath
```

- [ ] **Step 2: 验证编译无报错**

```bash
make check
```
Expected: 编译成功，无错误

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Ghostty/Ghostty.Config.swift
git commit -m "rebrand: update custom icon path to ~/.config/poltertty"
```

---

### Task 13: AppDelegate.swift — 配置文件加载路径

**Background:** 底层 `ghostty_config_load_default_files()` 会读取 `~/.config/ghostty/config`。要改为 `~/.config/poltertty/config`，需在 Swift 层显式传入路径。

实际代码使用 `#if DEBUG / #else` 编译指令，**不是**运行时 `if let`。

**Files:**
- Modify: `macos/Sources/App/macOS/AppDelegate.swift`（`override init()`，约 line 167-176）

- [ ] **Step 1: 确认当前代码结构**

当前代码：
```swift
override init() {
#if DEBUG
    ghostty = Ghostty.App(configPath: ProcessInfo.processInfo.environment["GHOSTTY_CONFIG_PATH"])
#else
    ghostty = Ghostty.App()
#endif
    super.init()
    ghostty.delegate = self
}
```

- [ ] **Step 2: 修改 Release 分支使用 poltertty 配置路径**

将 `#else` 分支改为：
```swift
override init() {
#if DEBUG
    ghostty = Ghostty.App(configPath: ProcessInfo.processInfo.environment["GHOSTTY_CONFIG_PATH"])
#else
    // Use poltertty config path by default
    let polterttyConfig = NSString("~/.config/poltertty/config").expandingTildeInPath
    ghostty = Ghostty.App(configPath: polterttyConfig)
#endif
    super.init()
    ghostty.delegate = self
}
```

> **说明:** `Ghostty.App(configPath:)` 接受文件路径；如果文件不存在，底层 C 库会使用默认空配置。用户需手动将配置迁移至 `~/.config/poltertty/config`（无自动迁移，符合方案 A 决策）。

- [ ] **Step 3: 验证编译无报错**

```bash
make check
```
Expected: 编译成功，无错误

- [ ] **Step 4: 运行应用验证行为**

```bash
make run-dev
```
验证：
- App 正常启动
- Release 构建读取 `~/.config/poltertty/config`
- Debug 构建仍支持 `GHOSTTY_CONFIG_PATH` 环境变量覆盖

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/App/macOS/AppDelegate.swift
git commit -m "rebrand: switch config path from ghostty to poltertty"
```

---

## Chunk 3: 收尾验证

### Task 14: 全量扫描遗漏

- [ ] **Step 1: 扫描剩余用户可见 Ghostty 字符串**

```bash
grep -rn '"[^"]*[Gg]hostty[^"]*"' macos/Sources/ --include="*.swift" \
  | grep -v "//.*ghostty\|GhosttyKit\|com\.mitchellh\|\.ghostty\b"
```

确认输出只剩内部代码引用（不含面向用户的字符串）。如有遗漏，补充修复。

- [ ] **Step 2: 构建 Release 版本最终验证**

```bash
make release
```
Expected: Release 构建成功

- [ ] **Step 3: 最终 commit（如有补充修改）**

```bash
git add -p
git commit -m "rebrand: fix remaining ghostty user-facing strings"
```
