# File Preview 性能优化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 消除 File Preview 打开文件时的 UI hang，并优化重复切换、大 Diff、大图片的性能。

**Architecture:** Task 1（后台高亮）已完成。剩余优化分三层：① 为 JSContext 高亮结果加 NSCache 缓存避免重复计算；② 为 DiffView 加行数上限防止 SwiftUI 渲染卡顿；③ 为图片加载改用延迟引用避免大文件全量读入内存。

**Tech Stack:** Swift/SwiftUI, AppKit, NSCache, JavaScriptCore, CGImageSource

---

## 文件结构

| 文件 | 操作 | 说明 |
|------|------|------|
| `macos/Sources/Features/Workspace/FileBrowser/SyntaxHighlightView.swift` | 修改 | ✅ Task 1 已完成；Task 2 在此加 NSCache |
| `macos/Sources/Features/Workspace/FileBrowser/DiffView.swift` | 修改 | Task 3：加行数上限 + 展开按钮 |
| `macos/Sources/Features/Workspace/FileBrowser/FilePreviewView.swift` | 修改 | Task 4：图片改用 CGImageSource 懒加载 |

---

## ✅ Task 1（已完成）：JSContext 高亮移到后台线程

**已做的事：**
- `SyntaxHighlighter` 增加 `static let highlightQueue`（serial queue）
- `updateNSView` 先渲染纯文本，再在后台 queue 执行 `highlight()`
- 用 `currentHighlightID` 防止过期结果回填

无需再操作。

---

## Task 2：NSCache 缓存高亮结果

**目标：** 切换回已预览过的文件时，直接命中缓存，跳过 JSContext 执行（约省 50–500ms）。

**Files:**
- Modify: `macos/Sources/Features/Workspace/FileBrowser/SyntaxHighlightView.swift`（`SyntaxHighlighter` 类）

### 实现思路

缓存 key = `"\(text 的 hash):\(language ?? "auto")"`，value = `NSAttributedString`。
静态 `NSCache` 自动在内存紧张时回收，无需手动管理。

- [ ] **Step 1: 在 `SyntaxHighlighter` 增加静态缓存**

在 `SyntaxHighlighter` 的 `highlightQueue` 声明后面添加：

```swift
// 文件：SyntaxHighlightView.swift，SyntaxHighlighter 类顶部
private static let cache = NSCache<NSString, NSAttributedString>()
```

- [ ] **Step 2: 在 `highlight()` 方法头部加缓存读取，尾部加写入**

找到 `func highlight(_ code: String, language: String?) -> NSAttributedString?`，改为：

```swift
func highlight(_ code: String, language: String?) -> NSAttributedString? {
    guard let ctx = context else { return nil }

    // 缓存命中时直接返回
    let cacheKey = "\(code.hashValue):\(language ?? "auto")" as NSString
    if let cached = SyntaxHighlighter.cache.object(forKey: cacheKey) {
        return cached
    }

    let escaped = code
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "`", with: "\\`")

    var html: String?
    if let lang = language {
        let result = ctx.evaluateScript("hljs.highlight(`\(escaped)`, {language: `\(lang)`, ignoreIllegals: true}).value")
        let str = result?.toString()
        if let str, !str.isEmpty, str != "undefined" {
            html = str
        }
    }
    if html == nil {
        let result = ctx.evaluateScript("hljs.highlightAuto(`\(escaped)`).value")
        let str = result?.toString()
        if let str, !str.isEmpty, str != "undefined" {
            html = str
        }
    }

    guard let html else { return nil }

    let result = parseHighlightHTML(html)

    // 写入缓存
    SyntaxHighlighter.cache.setObject(result, forKey: cacheKey)

    return result
}
```

- [ ] **Step 3: 构建验证**

```bash
cd /Users/aaronlin/works/codes/oss/poltertty
xcodebuild -workspace macos/Ghostty.xcworkspace -scheme Ghostty -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

期望输出：`Build succeeded`

- [ ] **Step 4: 手动验证**

运行 App，打开一个代码文件 → 关闭预览 → 再打开同一文件。第二次打开应几乎无延迟（无高亮动画闪烁）。

- [ ] **Step 5: 提交**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/SyntaxHighlightView.swift
git commit -m "perf(file-preview): cache JSContext highlight results with NSCache"
```

---

## Task 3：DiffView 行数上限

**目标：** 防止数千行 Diff 导致 SwiftUI 一次性构建大量 View 而卡顿。策略：每个 hunk 默认展示前 200 行，超出部分折叠，点击可展开。

**Files:**
- Modify: `macos/Sources/Features/Workspace/FileBrowser/DiffView.swift`

### 实现思路

在 `patchView` 内部用 `@State` 控制每个 patch 的展开状态，默认截断超出 `maxVisibleLines = 200` 的行。

- [ ] **Step 1: 给 DiffView 增加折叠常量**

在 `DiffView` 结构体顶部（`let diff: GitFileDiff?` 之后）添加：

```swift
// DiffView.swift，struct DiffView 内
private let maxVisibleLines = 200
```

- [ ] **Step 2: 将 patchView 改为 PatchView 子视图（用 @State 存展开状态）**

将原来的 `@ViewBuilder private func patchView(_ patch: GitPatch)` 替换为一个内嵌子视图，以便每个 patch 独立保持 `isExpanded` 状态。

把原来的 `ForEach(diff.patches) { patch in patchView(patch) }` 替换为：

```swift
ForEach(diff.patches) { patch in
    PatchRowView(patch: patch, maxVisibleLines: maxVisibleLines)
}
```

然后在文件末尾（`DiffView` 结构体之后）添加 `PatchRowView`：

```swift
// DiffView.swift 末尾，DiffView 之外
private struct PatchRowView: View {
    let patch: GitPatch
    let maxVisibleLines: Int

    @State private var isExpanded = false

    var body: some View {
        let lines = patch.lines
        let truncated = !isExpanded && lines.count > maxVisibleLines
        let visibleLines = truncated ? Array(lines.prefix(maxVisibleLines)) : lines

        // Hunk header
        Text(patch.header)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(Color(hex: "#60a5fa") ?? .blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((Color(hex: "#60a5fa") ?? .blue).opacity(0.06))

        ForEach(visibleLines) { line in
            diffLineView(line)
        }

        if truncated {
            Button(action: { isExpanded = true }) {
                Text("展开剩余 \(lines.count - maxVisibleLines) 行…")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    @ViewBuilder
    private func diffLineView(_ line: GitDiffLine) -> some View {
        HStack(spacing: 0) {
            Text(line.oldLineNo.map { "\($0)" } ?? "")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.5))
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 4)
            Text(line.newLineNo.map { "\($0)" } ?? "")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.5))
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 6)
            Text(linePrefix(for: line.origin))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(lineForeground(for: line.origin))
                .frame(width: 12)
            Text(line.content)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(lineForeground(for: line.origin))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(lineBackground(for: line.origin))
    }

    private func linePrefix(for origin: GitDiffLine.Origin) -> String {
        switch origin {
        case .added:   return "+"
        case .removed: return "-"
        case .context: return " "
        }
    }

    private func lineForeground(for origin: GitDiffLine.Origin) -> Color {
        switch origin {
        case .added:   return Color(hex: "#4ade80") ?? .green
        case .removed: return Color(hex: "#f87171") ?? .red
        case .context: return .primary.opacity(0.8)
        }
    }

    private func lineBackground(for origin: GitDiffLine.Origin) -> Color {
        switch origin {
        case .added:   return (Color(hex: "#4ade80") ?? .green).opacity(0.08)
        case .removed: return (Color(hex: "#f87171") ?? .red).opacity(0.08)
        case .context: return .clear
        }
    }
}
```

- [ ] **Step 3: 删除 DiffView 中已迁移到 PatchRowView 的旧方法**

从 `DiffView` 结构体内删除以下三个私有方法（它们已移入 `PatchRowView`）：

```swift
private func patchView(_ patch: GitPatch) -> some View { ... }
@ViewBuilder private func diffLineView(_ line: GitDiffLine) -> some View { ... }
private func linePrefix(for origin: GitDiffLine.Origin) -> String { ... }
private func lineForeground(for origin: GitDiffLine.Origin) -> Color { ... }
private func lineBackground(for origin: GitDiffLine.Origin) -> Color { ... }
```

- [ ] **Step 4: 构建验证**

```bash
cd /Users/aaronlin/works/codes/oss/poltertty
xcodebuild -workspace macos/Ghostty.xcworkspace -scheme Ghostty -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

期望：`Build succeeded`

- [ ] **Step 5: 手动验证**

在一个有大量修改的文件上查看 Diff（如改了数百行的文件）。应看到前 200 行 + "展开剩余 N 行…" 按钮，点击后展开全部。

- [ ] **Step 6: 提交**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/DiffView.swift
git commit -m "perf(diff-view): truncate large hunks to 200 lines with expand button"
```

---

## Task 4：图片懒加载（避免大文件全量读入内存）

**目标：** 把 `loadImage()` 里的 `Data(contentsOf:)` + `NSImage(data:)` 替换为 `NSImage(byReferencing:)`，让 AppKit 按需加载图片数据，避免 50MB+ 图片直接 OOM。

**Files:**
- Modify: `macos/Sources/Features/Workspace/FileBrowser/FilePreviewView.swift`（`loadImage()` 方法）

### 实现思路

`NSImage(byReferencing: url)` 创建一个延迟加载的 NSImage 对象，AppKit 只在实际渲染时才读取图片数据，并自动处理缩放。相比 `Data(contentsOf:)` + `NSImage(data:)` 可省去整个解码过程的主线程压力。

额外加一个文件大小限制（50MB），超出则显示提示，避免用户打开原始 RAW/TIFF 等超大文件。

- [ ] **Step 1: 修改 `loadImage()` 方法**

找到 `FilePreviewView.swift` 中的 `loadImage()` 方法，替换为：

```swift
private func loadImage() async {
    guard !Task.isCancelled else { return }

    // 超大图片文件（>50MB）直接提示，避免内存溢出
    let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    if fileSize > 50_000_000 {
        await MainActor.run {
            content = .notSupported("Image file too large for preview (max 50MB)")
        }
        return
    }

    guard !Task.isCancelled else { return }

    // NSImage(byReferencing:) 延迟加载——AppKit 在渲染时才读取数据
    let nsImage = NSImage(byReferencing: url)

    guard !Task.isCancelled else { return }
    await MainActor.run {
        content = .image(nsImage)
    }
}
```

- [ ] **Step 2: 构建验证**

```bash
cd /Users/aaronlin/works/codes/oss/poltertty
xcodebuild -workspace macos/Ghostty.xcworkspace -scheme Ghostty -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

期望：`Build succeeded`

- [ ] **Step 3: 手动验证**

在文件浏览器中打开一张 PNG/JPEG 图片，确认正常显示。再尝试打开一个 >50MB 的图片文件（如 RAW 文件），应显示 "Image file too large for preview" 提示。

- [ ] **Step 4: 提交**

```bash
git add macos/Sources/Features/Workspace/FileBrowser/FilePreviewView.swift
git commit -m "perf(file-preview): lazy-load images with NSImage(byReferencing:), cap at 50MB"
```

---

## 总览：优化效果

| Task | 场景 | 优化前 | 优化后 |
|------|------|--------|--------|
| ✅ Task 1 | 首次打开代码文件 | 主线程 hang 100–500ms | 立即显示纯文本，后台高亮 |
| Task 2 | 切换回已看过的文件 | 重新 JS 执行 | < 1ms 缓存命中 |
| Task 3 | 查看大 Diff（500+ 行） | SwiftUI 一次构建全部 View | 最多 200 行，按需展开 |
| Task 4 | 打开大图片（>10MB） | 全量 Data 读入内存 | 按需解码，50MB 以上拒绝 |
