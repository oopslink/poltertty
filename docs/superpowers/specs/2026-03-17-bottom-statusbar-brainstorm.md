# 底部状态栏 — 头脑风暴记录

**日期:** 2026-03-17
**状态:** 进行中（待继续讨论）

---

## 背景：竞品分析

分析了竞品 **Onda** 终端的界面，识别出以下值得借鉴的特性：

- 彩色字母徽章（快速识别 workspace）
- "All Tabs" 聚合视图
- **底部状态栏**（当前讨论重点）
- 左侧图标快速切换栏

### Onda 底部状态栏内容

- 左侧：当前工作目录路径（文件夹图标 + 路径文字）
- 右侧：git 分支名（git 图标 + 分支名）

---

## 项目现状调研

### 已有相关设计

`docs/superpowers/specs/2026-03-15-worktree-statusbar-design.md`（状态：Approved）

这个已批准的设计涵盖了类似需求（git worktree/branch 状态栏），但侧重点在 worktree 导航。需在继续讨论时确认：

- 两者是否应合并为同一功能？
- 还是 Onda 风格的状态栏是独立的、更简单的实现？

### 关键架构信息

**最佳插入点：**
- `macos/Sources/Features/Workspace/PolterttyRootView.swift`（`terminalAreaView` 区域，约第 274-295 行）
- 备选：`macos/Sources/Features/Terminal/TerminalView.swift`

**数据来源：**
- 当前工作目录：`@FocusedValue(\.ghosttySurfacePwd)` — 已在 TerminalView 中可用，随焦点 surface 自动更新
- Git 分支：需要新实现，通过 `git -C <pwd> branch --show-current` 或类似方式获取，需要防抖/缓存

**UI 参照模式：**
- `TerminalTabBar.swift` — 同类横向栏结构（VStack + Divider + background）
- `UpdatePill.swift` — overlay 状态提示模式

---

## 待讨论问题

brainstorming 流程刚开始，以下问题尚未讨论：

1. 是否与已批准的 worktree-statusbar 设计合并，还是独立实现？
2. 状态栏是否应该可以隐藏/折叠？
3. 路径显示格式：完整路径、相对路径、还是 `~` 缩写形式？
4. git 分支信息的刷新策略（切换 tab 时、定时轮询、文件系统监听？）
5. 是否要显示脏状态指示（uncommitted changes）？

---

## 下一步

继续 brainstorming 流程：
- 逐一回答上述问题
- 提出 2-3 种实现方案及取舍
- 完善并提交正式 spec
- 调用 `writing-plans` skill 生成实施计划
