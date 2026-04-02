# Pane Indicator UI 优化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 优化 pane selector（双击 Command 触发）的视觉呈现，使每个 pane 的 annotation 和 index 更醒目，通过遮罩层让卡片脱离背景干扰。

**Architecture:** 在 `TerminalSplitLeafContainer` 加统一遮罩层，重写 `PaneOverlayCardView` 使 annotation 成为主角、key badge 作为次级焦点，删除从未被渲染的 `PaneBadgeView`。`PaneSelectorViewModel` 无需改动。

**Tech Stack:** SwiftUI, macOS, Swift

**Working directory:** `.worktrees/feat/pane-indicator-polish`

---

## 文件变更一览

| 文件 | 操作 | 说明 |
|------|------|------|
| `macos/Sources/Features/Splits/PaneBadgeView.swift` | 删除 | 死代码，从未被渲染 |
| `macos/Sources/Features/Splits/PaneOverlayCardView.swift` | 重写 | 新卡片布局 |
| `macos/Sources/Features/Splits/TerminalSplitTreeView.swift` | 修改 | 在 `TerminalSplitLeafContainer` 加遮罩层 |

---

### Task 1: 删除 PaneBadgeView（死代码清理）

**Files:**
- Delete: `macos/Sources/Features/Splits/PaneBadgeView.swift`

- [ ] **Step 1: 确认无引用**

```bash
grep -r "PaneBadgeView" macos/Sources/
```

期望输出：只有 `PaneBadgeView.swift` 本身的定义行，无其他引用。

- [ ] **Step 2: 删除文件**

```bash
rm macos/Sources/Features/Splits/PaneBadgeView.swift
```

- [ ] **Step 3: 构建确认无报错**

在 Xcode 中 Build（⌘B），或：
```bash
# 如果项目有 swift build 入口
swift build 2>&1 | grep -E "error:|Build complete"
```

期望：`Build complete` 无 error。

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: 删除未使用的 PaneBadgeView"
```

---

### Task 2: 重写 PaneOverlayCardView

**Files:**
- Modify: `macos/Sources/Features/Splits/PaneOverlayCardView.swift`

新设计规则：
- **有 annotation**：annotation 大字（16px weight heavy）→ 细分隔线 → key badge（30×30, 16px）→ 辅助信息
- **无 annotation**：key badge 放大（44×44, 22px）→ 辅助信息
- 辅助信息格式：`进程名 · ~/路径 · 时长`（时长 < 60s 不显示）
- 卡片背景：`.regularMaterial`（比 ultraThin 更不透明，更能从终端内容中脱出）

- [ ] **Step 1: 完整替换 PaneOverlayCardView.swift**

```swift
// macos/Sources/Features/Splits/PaneOverlayCardView.swift

import SwiftUI

/// 概览模式下显示在 pane 中央的浮动信息卡片。
struct PaneOverlayCardView: View {
    let info: PaneSelectorViewModel.PaneOverlayInfo

    var body: some View {
        VStack(spacing: 7) {
            if let annotation = info.annotation {
                // annotation 是主角
                Text(annotation.count > 20 ? String(annotation.prefix(20)) + "…" : annotation)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 28, height: 1)

                keyBadge(size: 30, fontSize: 16)
            } else {
                // 无 annotation：key badge 放大顶替主角
                keyBadge(size: 44, fontSize: 22)
            }

            subInfoView
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.7), radius: 24, y: 4)
        .fixedSize()
    }

    // MARK: - Key badge

    private func keyBadge(size: CGFloat, fontSize: CGFloat) -> some View {
        let cornerRadius = size * 0.23
        return Text(PaneSelectorViewModel.label(for: info.index))
            .font(.system(size: fontSize, weight: .black, design: .monospaced))
            .foregroundStyle(Color.accentColor)
            .frame(width: size, height: size)
            .background(
                Color.accentColor.opacity(0.15),
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1.5)
            )
    }

    // MARK: - 辅助信息

    private var subInfoView: some View {
        Text(subInfo)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var subInfo: String {
        var parts: [String] = []
        if let fg = info.foregroundProcess {
            parts.append(fg)
        } else {
            parts.append(info.shellName)
        }
        let pwd = info.pwd.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        parts.append(pwd)
        if info.duration >= 60 {
            parts.append(PaneSelectorViewModel.formatDuration(info.duration))
        }
        return parts.joined(separator: " · ")
    }
}
```

- [ ] **Step 2: 构建确认无报错**

在 Xcode 中 Build（⌘B）。期望：`Build Succeeded`，无 error。

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Splits/PaneOverlayCardView.swift
git commit -m "feat(pane-indicator): 重写 PaneOverlayCardView，annotation 为主角"
```

---

### Task 3: 在 TerminalSplitLeafContainer 加遮罩层

**Files:**
- Modify: `macos/Sources/Features/Splits/TerminalSplitTreeView.swift:125-151`

在 pane selector 激活时，为每个 pane 叠加统一的 52% 黑色遮罩，使卡片从终端内容中脱离出来。遮罩要插在 **highlight pulse overlay 之后、card overlay 之前**，保证 z-order：遮罩在下，卡片在上。

- [ ] **Step 1: 在 card overlay 之前插入遮罩 overlay**

找到 `TerminalSplitLeafContainer` 的 `body`，定位到这段代码（约第 143 行）：

```swift
            .overlay {
                if paneSelectorVM.isActive,
                   let info = paneSelectorVM.overlayInfos[surfaceView.id] {
                    PaneOverlayCardView(info: info)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .animation(.easeInOut(duration: 0.15), value: paneSelectorVM.isActive)
                }
            }
```

在这段 **之前** 插入遮罩 overlay，替换后如下：

```swift
            .overlay {
                if paneSelectorVM.isActive {
                    Color.black.opacity(0.52)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.15), value: paneSelectorVM.isActive)
                }
            }
            .overlay {
                if paneSelectorVM.isActive,
                   let info = paneSelectorVM.overlayInfos[surfaceView.id] {
                    PaneOverlayCardView(info: info)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .animation(.easeInOut(duration: 0.15), value: paneSelectorVM.isActive)
                }
            }
```

- [ ] **Step 2: 构建确认无报错**

在 Xcode 中 Build（⌘B）。期望：`Build Succeeded`，无 error。

- [ ] **Step 3: 手动测试**

1. 运行 app
2. 打开 2–4 个 split pane（任意内容）
3. 双击 Command 激活 pane selector
4. 验证：
   - 所有 pane 出现统一黑色遮罩
   - 有 annotation 的 pane：annotation 大字居上，key badge 居中偏下
   - 无 annotation 的 pane：key badge 放大居中
   - 辅助信息（进程 · 路径 · 时长）显示在卡片底部小字
   - 按数字/字母键跳转后，遮罩和卡片消失
   - 按 Esc 取消，遮罩和卡片消失

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Splits/TerminalSplitTreeView.swift
git commit -m "feat(pane-indicator): 添加遮罩层，增强卡片视觉突出性"
```
