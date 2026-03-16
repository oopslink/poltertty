# Tab Bar 重新设计

**日期:** 2026-03-16
**状态:** 设计确认

## 概述

重新设计 poltertty 的 tab bar 布局：窗口标题栏只显示 workspace 名称，tab bar 作为独立区域在终端上方显示，使用自定义 SwiftUI 实现替代 macOS 原生 tab 机制。

## 设计决策记录

| 决策点 | 选择 |
|--------|------|
| 标题栏外观 | macOS 原生（保留红绿灯按钮） |
| 标题栏内容 | 仅显示 workspace 名称 |
| Tab bar 位置 | sidebar 右侧终端区域上方（不横跨 sidebar） |
| Tab 视觉风格 | 底部指示条（underline style） |
| Tab bar 高度 | 36px |
| Tab 宽度 | 紧凑，自适应文字内容 |
| 关闭按钮 | hover 时显示 × |
| Tab bar 可见性 | 仅多 tab 时显示，单 tab 隐藏 |
| "+" 按钮 | 固定在 tab bar 最右侧 |
| 实现方式 | SwiftUI 自定义 Tab Bar（方案 A） |

## 第一节：窗口标题栏

### 变更

- `window.title` 只显示 workspace 名称（不再拼接终端标题）
- 临时 workspace 显示 "Poltertty"
- 移除 `applyTitleToWindow()` 中的 `[WorkspaceName] baseTitle` 拼接逻辑

### 影响文件

- `BaseTerminalController.swift` — `applyTitleToWindow()` 方法

## 第二节：Tab 数据模型

### 新增模型

**TabItem**（ObservableObject）：
- `id: UUID`
- `title: String` — 用户自定义名称，默认从 PTY 标题取
- `isActive: Bool`
- 关联的 `TerminalController` 引用

**TabBarViewModel**（ObservableObject）：
- 持有 `[TabItem]` 数组
- 管理：当前选中 tab、添加/关闭/重排 tab、双击重命名
- 由 `TerminalController` 持有，传入 `PolterttyRootView`

### Tab 可见性规则

- `tabs.count <= 1` → tab bar 隐藏
- `tabs.count >= 2` → tab bar 显示（36px）

## 第三节：Tab Bar UI 组件

### 组件结构

```
TerminalTabBar (SwiftUI View)
├─ HStack (spacing: 0)
│   ├─ ForEach(tabs) → TerminalTabItem
│   │   ├─ Text(tab.title)  — 字体 12px, system font
│   │   └─ closeButton (×)  — hover 时显示，10px
│   └─ addButton (+)        — 固定在最右侧
└─ Divider                  — 底部 1px 分隔线
```

### 视觉细节

- 总高度 36px，背景色跟随终端背景（略浅）
- 选中 tab：文字高亮 + 底部 2px 彩色指示条（可跟随 workspace 颜色）
- 未选中 tab：文字灰色，无指示条
- Tab 宽度：自适应文字内容 + 左右 padding 14px，不设最小宽度
- 关闭按钮：默认隐藏，hover 该 tab 时淡入显示
- "+" 按钮：`margin-left: auto`，始终靠右

### 交互

- 单击 → 切换到该 tab
- 双击 → 进入重命名（inline editing）
- 右键 → 上下文菜单（重命名、关闭、关闭其他）
- 关闭按钮 → 关闭该 tab（最后一个 tab 时关闭按钮不显示）
- "+" → 新建 tab

## 第四节：与现有原生 Tab 机制的关系

### 策略

- 窗口样式改为不使用 titlebar tabs
- 窗口标题栏保持原生外观，只显示 workspace 名称
- Tab 管理从 NSWindow tab group 层移到 SwiftUI 层——多个终端视图作为子视图切换，而非多个 NSWindow 合并为 tab group
- 一个 NSWindow 内部管理多个 TerminalView，通过自定义 tab bar 切换显示

### 影响范围

- `TerminalController` — 新建 tab 不再创建新 NSWindow，而是在同一窗口内添加 TerminalView
- `TitlebarTabsTahoeTerminalWindow` / `TitlebarTabsVenturaTerminalWindow` — poltertty 模式下不再使用 titlebar tab 逻辑
- `TerminalWindow` — 简化，不需要原生 tab accessory views
- `AppDelegate` — `newTab` action 路由到自定义 tab bar 的添加逻辑

### 上游兼容

- 原生 tab 代码不删除，通过条件判断走不同分支
- poltertty 用自定义 tab bar，保留原生路径供上游合并
- 符合 workspace-rules "不修改上游核心代码"原则

## 第五节：窗口布局总览与状态切换

### 布局结构（poltertty 模式）

```
NSWindow (native titlebar, title = workspace name)
├─ contentView
│   └─ PolterttyRootView
│       └─ HStack
│           ├─ WorkspaceSidebar (左侧, 48/180-260px)
│           ├─ FileBrowserPanel (可选, 260px)
│           └─ VStack  ← 终端区域
│               ├─ TerminalTabBar (条件显示, 36px)
│               ├─ ActiveTerminalView (当前 tab 的终端)
│               └─ StatusBar (底部)
```

### 状态切换矩阵

| 状态 | Tab Bar | 标题栏 |
|------|---------|--------|
| 1 个 tab, 有 workspace | 隐藏 | workspace 名称 |
| 多个 tab, 有 workspace | 显示 (36px) | workspace 名称 |
| 1 个 tab, 临时 workspace | 隐藏 | "Poltertty" |
| 多个 tab, 临时 workspace | 显示 (36px) | "Poltertty" |

### 动画

- Tab bar 显示/隐藏：SwiftUI 过渡动画（从上滑入/滑出）
- Tab 切换：终端视图直接切换，无过渡动画（保证响应速度）
