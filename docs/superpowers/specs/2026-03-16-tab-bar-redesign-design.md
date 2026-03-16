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

**TabItem**（struct, Identifiable）：
- `id: UUID`
- `title: String` — 默认从 PTY 标题动态更新；用户双击重命名后锁定（不再跟随 PTY 变化）
- `titleLocked: Bool` — 是否被用户手动锁定
- `isActive: Bool`
- `surfaceId: UUID` — 关联的 `Ghostty.SurfaceView` 标识（非强引用，避免循环引用）

**TabBarViewModel**（ObservableObject）：
- 持有 `[TabItem]` 数组
- 持有 `[UUID: Ghostty.SurfaceView]` 字典——作为 SurfaceView 实例的唯一所有者，管理其生命周期
- 管理：当前选中 tab、添加/关闭/重排 tab、双击重命名
- 由 `TerminalController` 持有，传入 `PolterttyRootView`

### Surface 生命周期

新建 tab 时：
1. `TabBarViewModel` 请求 `TerminalController` 创建新的 `Ghostty.SurfaceView`
2. `TerminalController` 负责底层 surface 创建（调用 Ghostty core C ABI）
3. 返回的 SurfaceView 存入 `TabBarViewModel` 的字典中
4. `PolterttyRootView` 根据当前选中 tab 的 surfaceId 从字典中取出对应 SurfaceView 显示

关闭 tab 时：
1. `TabBarViewModel` 通知 `TerminalController` 销毁对应 surface
2. 从字典和数组中移除
3. 自动切换到相邻 tab

`PolterttyRootView` 的接口从接受单个 `terminalView: TerminalContent` 改为接受 `TabBarViewModel`，由 ViewModel 提供当前活跃的 TerminalView。

### Tab 标题更新规则

- `titleLocked == false`：PTY 标题变化时自动更新 `tab.title`（如 cd、SSH 等场景）
- `titleLocked == true`：忽略 PTY 标题变化，保持用户设置的名称
- 用户双击重命名 → 设置 `titleLocked = true`
- 重命名时清空内容 → 恢复为 PTY 标题并设置 `titleLocked = false`

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
- 选中 tab：文字高亮 + 底部 2px 彩色指示条（跟随 workspace 颜色，临时 workspace 用默认蓝色）
- 未选中 tab：文字灰色，无指示条
- Tab 宽度：自适应文字内容 + 左右 padding 14px，不设最小宽度
- 关闭按钮：默认隐藏，hover 该 tab 时淡入显示
- "+" 按钮：`margin-left: auto`，始终靠右

### 交互

- 单击 → 切换到该 tab
- 双击 → 进入重命名（SwiftUI inline TextField，Enter 确认，Escape 取消；清空恢复 PTY 标题）
- 右键 → 上下文菜单（重命名、关闭、关闭其他）
- 拖拽重排 → 使用 SwiftUI `draggable` / `dropDestination` 修饰符实现 tab 拖拽排序
- 关闭按钮 → 关闭该 tab（最后一个 tab 时关闭按钮不显示）
- "+" → 新建 tab

### 键盘快捷键

- `Cmd+T` → 新建 tab（重路由到自定义 tab bar，不再走原生 NSWindow tab）
- `Cmd+W` → 关闭当前 tab（仅剩一个 tab 时关闭窗口）
- `Cmd+Shift+[` / `Cmd+Shift+]` → 切换到上一个 / 下一个 tab
- `Cmd+1` ~ `Cmd+9` → 直接切换到对应位置的 tab

### Tab 溢出行为

当 tab 数量过多导致宽度超出可用空间时：
- Tab 宽度逐步压缩，最小宽度 60px（保证至少显示几个字符 + 关闭按钮）
- 超出最小宽度仍放不下时，tab bar 支持水平滚动（隐藏滚动条，trackpad/鼠标滚轮滚动）

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

## 第六节：状态持久化

### Workspace Snapshot 集成

Tab 状态纳入现有 `WorkspaceSnapshot` 机制：

- 保存：tab 数量、tab 顺序、每个 tab 的自定义名称（`titleLocked` 的）、当前选中 tab index
- 恢复：启动时按保存的顺序重建 tabs 和对应的 SurfaceView，恢复选中状态
- 临时 workspace 不保存 tab 状态（与现有规则一致）

### FileBrowser 全屏预览模式

当 `fileBrowserVM.isPreviewFullscreen == true` 时，tab bar 隐藏（文件预览覆盖整个终端区域）。退出全屏预览后恢复 tab bar 显示。
