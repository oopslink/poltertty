# 文件浏览器增强设计文档

**日期：** 2026-03-24
**状态：** 已批准
**范围：** `macos/Sources/Features/Workspace/FileBrowser/`

---

## 背景

现有文件浏览器已具备树形浏览、多选批量操作、Git 状态集成、代码预览、快捷键支持等核心功能。本次改进聚焦三个方向：

1. **导航与提示层**：快捷键面板 + 路径面包屑
2. **智能过滤**：按文件类型和 Git 状态过滤
3. **Git 深度集成**：Diff 预览 + Stage/Unstage 操作

按三组独立分支开发，每组可单独 PR 合入。

---

## 第一组：快捷键面板 + 路径面包屑

### 快捷键面板（ShortcutHelpView）

**新增文件：** `ShortcutHelpView.swift`

**触发方式：**
- 文件浏览器聚焦时按 `?`
- 顶栏 `⌨` 图标按钮点击

**关闭方式：** 再按 `?`、按 `Esc`、点击浮层外部

**UI：**
- 半透明深色浮层（`.ultraThinMaterial`），圆角，居中显示
- 两列布局：左侧键名，右侧功能描述
- 按功能分类展示：

| 分类 | 快捷键 | 描述 |
|------|--------|------|
| 导航 | `↑` `↓` | 上下选择 |
| | `Return` | 展开/折叠目录 |
| 文件操作 | `n` | 新建文件 |
| | `N` | 新建目录 |
| | `r` | 重命名 |
| | `⌘⌫` | 删除 |
| | `t` | 在终端打开 |
| 搜索/视图 | `⌘F` | 过滤 |
| | `.` | 切换隐藏文件 |
| | `Space` | 切换预览面板 |
| | `⌘⇧C` | 复制路径 |
| | `⌘A` | 全选 |
| 帮助 | `?` | 显示/隐藏此面板 |

**ViewModel 改动：**
```swift
// FileBrowserViewModel.swift
@Published var showShortcutHelp: Bool = false
```

---

### 路径面包屑（BreadcrumbView）

**新增文件：** `BreadcrumbView.swift`

**位置：** 文件树顶部，过滤栏上方

**行为：**
- 显示从 workspace 根目录到当前光标所在文件的父目录路径层级
- 每段可点击，点击后将该目录设为"聚焦根"（只显示该目录内容）；点击根段恢复完整树
- 超长时左侧省略：`.../ parent / current`
- 最右段高亮显示

**数据来源：** `lastSelectedId` 对应节点的 `url` 路径分解

**ViewModel 新增：**
```swift
struct BreadcrumbSegment {
    let name: String
    let url: URL
}

var breadcrumbSegments: [BreadcrumbSegment]  // 派生计算属性
@Published var focusedRootURL: URL?           // nil = 显示完整树
```

---

## 第二组：增强过滤

### UI：过滤 Chip 栏

**位置：** 现有过滤栏下方，有激活条件时展开，否则折叠隐藏

**类型过滤 Chip：**
- 动态扫描当前目录树，按扩展名分组生成 Chip
- 显示文件计数：`Swift ×12`、`JSON ×3`、`Markdown ×8`
- 点击激活，支持多选（同时过滤多个类型）

**Git 状态过滤 Chip：**
- 固定四个：`已修改` `未追踪` `已添加` `已删除`
- 显示对应颜色（与文件树 Git 颜色一致）

**过滤逻辑：** 类型 AND Git 状态，任一维度为空则忽略该维度，与现有 `filterText` 叠加。

命中文件自动展开其父目录路径。

### ViewModel 扩展

```swift
// FileBrowserViewModel.swift
@Published var activeExtensions: Set<String> = []
@Published var activeGitStatuses: Set<GitStatus> = []

struct FilterCriteria {
    let text: String
    let extensions: Set<String>
    let gitStatuses: Set<GitStatus>
}

var effectiveFilter: FilterCriteria {
    FilterCriteria(
        text: filterText,
        extensions: activeExtensions,
        gitStatuses: activeGitStatuses
    )
}

// 扩展名统计（用于 Chip 生成）
var availableExtensions: [(extension: String, count: Int)] { get }
```

**修改 `filterTree()` 方法：** 在现有文本过滤逻辑基础上叠加扩展名和 Git 状态过滤。

---

## 第三组：Git 深度集成

### Diff 预览视图（DiffView）

**新增文件：** `DiffView.swift`

**触发：** `FilePreviewView` 中，文件 Git 状态为 `modified` 或 `added` 时，顶部显示 `Diff` 切换按钮。

**Diff 来源：**
- 未暂存：`git diff HEAD -- <file>`
- 已暂存：`git diff --cached -- <file>`

**渲染：**
- 逐行解析 `+`/`-` 前缀
- `+` 行：绿色背景高亮
- `-` 行：红色背景高亮
- `@@` 行：灰色段落标记
- 行号区：原始行号 vs 新行号两列

### GitStatusService 扩展

```swift
// GitStatusService.swift 新增
func fetchDiff(rootDir: String, fileURL: URL, staged: Bool) async -> String

func stage(rootDir: String, urls: [URL]) async throws
func unstage(rootDir: String, urls: [URL]) async throws
```

**底层命令：**
```bash
# stage
git -C <rootDir> add <file>...

# unstage
git -C <rootDir> restore --staged <file>...

# diff（未暂存）
git -C <rootDir> diff HEAD -- <file>

# diff（已暂存）
git -C <rootDir> diff --cached -- <file>
```

### 右键菜单扩展（FileNodeRow）

根据文件 Git 状态动态显示操作项：

| 当前 Git 状态 | 菜单项 |
|-------------|--------|
| `modified` / `untracked` | `Stage` |
| `added`（已暂存） | `Unstage` |
| `deleted` | `Stage Deletion` / `Unstage` |

操作完成后自动调用 `refreshGitStatus()`，界面即时更新。

**多选支持：** 选中多个文件时，右键菜单显示 `Stage N items` / `Unstage N items`。

---

## 实施顺序

```
组 1: feat/file-browser-shortcuts-breadcrumb
      ShortcutHelpView + BreadcrumbView + ViewModel 小改动

组 2: feat/file-browser-smart-filter
      过滤 Chip 栏 + ViewModel 过滤扩展

组 3: feat/file-browser-git-integration
      DiffView + GitStatusService 扩展 + 右键菜单更新
```

每组独立 worktree，独立 PR，按序合入。

---

## 不在本次范围内

- 批量重命名 / 批量复制
- 列视图 / 图标视图
- 内容全文搜索
- Git commit / push 操作
