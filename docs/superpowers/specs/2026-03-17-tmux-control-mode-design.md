# Poltertty tmux Control Mode 设计文档

**日期**: 2026-03-17
**状态**: 草稿 v3

---

## 概述

为 Poltertty 的 Workspace 增加可选的 **tmux 模式**，利用 tmux control mode（`tmux -CC`）将 tmux session 作为后端，poltertty 负责原生 UI 渲染。

- **native 模式**（现有）：不变
- **tmux 模式**（新增）：workspace 绑定一个 tmux session，tab = tmux window，pane = tmux pane

---

## 目标

- Workspace 支持两种模式：native 和 tmux，用户在创建时选择
- tmux 模式下 tab bar 由 tmux window 状态快照驱动（diff 检测增减）
- tmux 模式下支持原生 pane 分屏渲染，每个 pane 是真实 Ghostty surface，分割线可拖拽调整尺寸
- poltertty UI 操作（新建 tab、分屏）和 tmux 原生快捷键均可触发，`.windows` 快照为 source of truth
- 关闭 workspace 时 tmux session 后台保活，重新打开自动 attach

## 非目标

- 不支持 tmux copy mode 的原生渲染
- 不支持 tmux status bar 同步
- 不修改任何上游 Ghostty Zig 文件

---

## 上游 viewer.zig Action 接口

`viewer.zig` 的 `Viewer.next()` 只 emit 三种 Action：

| Action | payload | 说明 |
|---|---|---|
| `.exit` | 无 | tmux session 结束 |
| `.command` | `[]const u8` | **必须写回 PTY stdin**（viewer 驱动 tmux 的 loopback 通道） |
| `.windows` | `[]const Window` | 当前所有 window 的完整快照，含 layout 树 |

**关键约束**：
- `.command` 是 viewer 驱动 tmux 的机制（如 `list-windows\n`、`capture-pane` 等），若不写回 PTY，viewer 状态机在 `startup_block` 阶段即卡死
- pane output 在 viewer 内部路由到 `Pane.Terminal`（内部 VT 状态机），**不作为 Action 暴露**
- window 变化（增删改名）通过对比前后两次 `.windows` 快照来检测

---

## 架构

```
┌─────────────────────────────────────────────────────┐
│                   Swift UI Layer                    │
│                                                     │
│  WorkspaceModel (.native | .tmux)                   │
│  TmuxSessionManager  ←→  Ghostty.TmuxViewer         │
│  TabBarViewModel（windows diff 驱动）                 │
│  TmuxPaneLayoutView（递归 split view 渲染）            │
│  每个 pane → ghostty_surface_t（真实 surface）        │
└──────────┬──────────────────────────┬───────────────┘
           │ GhosttyKit C API          │ GhosttyKit C API
           │ (tmux viewer)             │ (surface, 现有)
┌──────────▼──────────┐   ┌───────────▼───────────────┐
│  tmux_capi.zig（新增）│   │  现有 ghostty C API        │
│  viewer_new/feed    │   │  ghostty_surface_new 等     │
│  viewer_send        │   └───────────────────────────┘
│  Action callback    │
└──────────┬──────────┘
           │ 调用，不修改
┌──────────▼──────────────────────────────────────────┐
│           上游 tmux/viewer.zig（不动）                │
│           tmux/control.zig（不动）                    │
│           tmux/layout.zig（不动）                     │
└─────────────────────────────────────────────────────┘
```

**数据流**：
```
tmux 进程输出 → PTYProcess.onData
→ Ghostty.TmuxViewer.feed()
→ tmux_capi.zig → viewer.zig 解析
→ Action callback 回 Swift：
    .command  → PTYProcess.write()（写回 PTY stdin，驱动 viewer 状态机）
    .windows  → TmuxSessionManager.diffWindows() → TabBarViewModel / TmuxPaneLayoutView 更新
    .exit     → detachCleanup()
```

---

## WorkspaceModel 扩展

```swift
enum WorkspaceMode: Codable {
    case native
    case tmux(sessionName: String, startupCommand: String)
}
```

`WorkspaceModel` 新增字段并实现向后兼容反序列化：

```swift
struct WorkspaceModel: Codable {
    // ... 现有字段 ...
    var mode: WorkspaceMode = .native

    init(from decoder: Decoder) throws {
        // ... 现有字段解码 ...
        mode = try container.decodeIfPresent(WorkspaceMode.self, forKey: .mode) ?? .native
    }
}

// WorkspaceMode 需要自定义 Codable（关联值 enum 默认编码不稳定）
extension WorkspaceMode: Codable {
    enum CodingKeys: String, CodingKey { case type, sessionName, startupCommand }
    // 手写 encode/decode，type = "native" | "tmux"
}
```

**WorkspaceCreateForm 变更**：

`onSubmit` 闭包增加 `mode` 参数，或改为传递完整配置结构体：

```swift
// 推荐：传配置结构体，避免参数列表过长
struct WorkspaceCreateConfig {
    var name: String
    var rootDir: String
    var colorHex: String
    var description: String
    var mode: WorkspaceMode
}
onSubmit: (WorkspaceCreateConfig) -> Void
```

UI 新增 mode 选择区（tmux 模式下显示 session 名和启动命令输入框，根据 session 名自动填充）。

**mode 不可变**：mode 仅在创建时设定，edit mode 不开放修改（避免 native ↔ tmux 迁移的复杂状态处理）。`WorkspaceCreateForm` 在 edit mode 下隐藏 mode 选择区。

**`WorkspaceManager.create()` 变更**：

```swift
func create(config: WorkspaceCreateConfig) -> WorkspaceModel
// WorkspaceCreateConfig.mode 默认 .native，向后兼容现有调用
```

**启动行为差异**：

| | native 模式 | tmux 模式 |
|---|---|---|
| 打开 workspace | 创建 Ghostty surface | 执行 startupCommand，连接 TmuxSessionManager |
| tab 来源 | TabBarViewModel 手动管理 | `.windows` Action diff 驱动 |
| 关闭 workspace | 销毁 surface | detach session，session 后台保活 |
| snapshot 持久化 | 保存 tab 列表 | 只保存 mode 配置，tab 由 tmux 维护 |

**WorkspaceSnapshot 变更**：`WorkspaceManager.saveSnapshot` 在 tmux 模式下 tabs / activeTabIndex 写 nil，由调用方根据 `workspace.mode` 分支处理。

---

## Zig 层：`tmux_capi.zig`（新增文件）

文件路径：`src/terminal/tmux_capi.zig`

不修改任何上游文件，将 `viewer.zig` 的三种 Action 映射为 C-compatible 结构体。

```zig
pub const ghostty_tmux_action_tag_e = enum(c_int) {
    command,    // 必须写回 PTY stdin
    windows,    // 完整 window 快照，含 layout
    exit,
};

// Layout 节点（对应 layout.zig 的 Layout 递归结构）
// 约定：
//   leaf 节点：split_type=0，pane_id 有效，children_ptr=null，children_len=0
//   container 节点：split_type=1（horizontal）或 2（vertical），pane_id=0（无意义），
//                   children_ptr 指向子节点数组
pub const ghostty_tmux_layout_node_s = extern struct {
    pane_id: usize,    // usize 与 Zig layout.zig Content.pane: usize 对齐，Swift 读作 UInt
    x: usize, y: usize, width: usize, height: usize,
    split_type: u8,  // 0=leaf, 1=horizontal, 2=vertical
    children_ptr: ?[*]ghostty_tmux_layout_node_s,
    children_len: usize,
};

// Window 快照（对应 viewer.zig 的 Viewer.Window）
// viewer.zig 不携带 window name，Swift 用 window index 合成 tab 标题（如 "Window 1"）
pub const ghostty_tmux_window_s = extern struct {
    id: usize,       // usize 与 Viewer.Window.id: usize 对齐，Swift 读作 UInt
    width: usize,
    height: usize,
    root_layout: ghostty_tmux_layout_node_s,
};

pub const ghostty_tmux_action_s = extern struct {
    tag: ghostty_tmux_action_tag_e,
    // command action
    command_ptr: ?[*]const u8,
    command_len: usize,
    // windows action
    windows_ptr: ?[*]ghostty_tmux_window_s,
    windows_len: usize,
};

export fn ghostty_tmux_viewer_new(...) ghostty_tmux_viewer_t
export fn ghostty_tmux_viewer_feed(viewer, data, len) void
export fn ghostty_tmux_viewer_send(viewer, cmd, len) void  // poltertty UI → tmux
export fn ghostty_tmux_viewer_free(viewer) void
```

**Tab 标题策略**：`Viewer.Window` 不携带 window name，Swift 侧 `TmuxSessionManager` 用窗口在 snapshot 中的 index 合成标题（`Window \(index + 1)`），用户可在 poltertty tab bar 双击重命名（锁定标题，不跟随快照更新）。

**`ghostty.h` 末尾追加**（不修改现有内容）：

```c
// ===== Poltertty tmux Extensions =====
typedef void* ghostty_tmux_viewer_t;
// ... struct / enum / function declarations ...
```

**`src/main_c.zig` 追加**（pull export symbols）：
```zig
comptime { _ = @import("terminal/tmux_capi.zig"); }
```

**跟踪上游维护点**：若 `viewer.zig` 的 `Window` / `Layout` 结构变更，只需更新 `tmux_capi.zig` 的映射。

---

## Swift 层

### 文件结构

```
macos/Sources/
  Ghostty/
    Ghostty.TmuxViewer.swift       ← 薄包装 ghostty_tmux_viewer_t
  Features/Workspace/Tmux/
    TmuxSessionManager.swift       ← 业务逻辑，PTY 管理，Action 处理，window diff
    TmuxWindowState.swift          ← windows 快照数据结构（对应 ghostty_tmux_window_s）
    TmuxPaneLayoutView.swift       ← 递归 SwiftUI 分屏渲染
    TmuxDivider.swift              ← 可拖拽分割线
    TmuxPTYProcess.swift           ← 启动/读写 tmux 进程（与 Ghostty surface PTY 分离）
```

> 注：`TmuxPTYProcess` 有别于 Ghostty surface 内部的 PTY 管理，需明确注释区分，避免混淆。

### `Ghostty.TmuxViewer`

包装 opaque pointer，处理 Action callback，与现有 `Ghostty.Surface` 模式一致：
- `feed(_ data: Data)` → `ghostty_tmux_viewer_feed`
- `send(_ command: String)` → `ghostty_tmux_viewer_send`（poltertty UI 发命令用）
- `onAction: ((TmuxViewerAction) -> Void)?` 回调

### `TmuxSessionManager`

`@MainActor ObservableObject`，核心职责：

```swift
func handleAction(_ action: TmuxViewerAction) {
    switch action {
    case .command(let cmd):
        // 必须写回 PTY stdin，驱动 viewer 状态机
        ptyProcess.write(cmd)

    case .windows(let snapshot):
        // diff 前后快照，更新 TabBarViewModel
        let diff = TmuxWindowDiff(prev: currentWindows, next: snapshot)
        diff.added.forEach   { tabBarViewModel?.addTmuxTab($0) }
        diff.removed.forEach { tabBarViewModel?.removeTmuxTab($0) }
        diff.renamed.forEach { tabBarViewModel?.renameTmuxTab($0) }
        // 更新 pane layout
        snapshot.forEach { windowLayouts[$0.id] = $0.rootLayout }
        currentWindows = snapshot

    case .exit:
        detachCleanup()
    }
}
```

**poltertty UI → tmux 命令映射**：

| UI 操作 | tmux 命令 |
|---|---|
| tab bar `+` | `new-window` |
| tab bar `×` | `kill-window -t @<id>` |
| 水平分屏按钮 | `split-window -h` |
| 垂直分屏按钮 | `split-window -v` |
| 点击 pane | `select-pane -t %<id>` |
| 关闭 workspace | `detach-client` |

tmux 原生快捷键同样生效，两者最终都触发 viewer `.windows` 快照更新，UI 以快照为准。

---

## Pane 渲染：ghostty_surface_t 方案

### 选择

每个 tmux pane 对应一个真实 **`ghostty_surface_t`**（与 native 模式的 surface 相同），而非渲染 viewer.zig 内部的 `Pane.Terminal`。

**原因**：
- viewer.zig 的 `Pane.Terminal` 不暴露渲染 API，访问成本高
- 复用现有 surface 渲染管道，无需新增 VT 渲染逻辑
- 输入路由（键盘、鼠标）直接复用现有 surface 机制

### Pane Surface 生命周期

```
.windows 快照到来 →
  新 pane id → ghostty_surface_new() + 加入 pane surfaces 字典
  消失 pane id → ghostty_surface_free() + 从字典移除
  layout 变化 → 更新对应 surface 的 frame
```

`TmuxSessionManager` 维护 `paneSurfaces: [UInt: Ghostty.Surface]`（`UInt` 对应 Zig `usize`，避免 64-bit pane ID 截断）。

### 数据流（pane output 路由）

tmux control mode 的 `%output %<pane_id> <data>` 事件由 `control.zig` 解析，`viewer.zig` 将其路由到内部 `Pane.Terminal`（不作为 Action 暴露）。

**路由策略（明确）**：`tmux_capi.zig` 在将字节喂给 `Viewer` 前，先用 `ControlParser` 解析一遍，拦截 `.output` 通知，通过独立 callback 发给 Swift，**然后再**喂给 `Viewer`。这样 viewer 内部 Terminal 继续维护 VT 状态（供 viewer 状态机内部使用），Swift surface 同时接收相同数据做原生渲染，两者并行。

```zig
// tmux_capi.zig 额外导出：pane output callback（在 viewer.feed 内部拦截）
pub const ghostty_tmux_pane_output_cb = *const fn(
    userdata: ?*anyopaque,
    pane_id: usize,
    data_ptr: [*]const u8,
    data_len: usize,
) callconv(.C) void;
```

Swift 侧：收到 callback → 查 `paneSurfaces[pane_id]` → `surface.sendText(data)`。

### SwiftUI 布局

```swift
indirect enum TmuxLayoutNode {
    case pane(id: UInt, frame: CGRect)             // UInt 对应 Zig usize，坐标来自 layout string（绝对值）
    case horizontal(children: [TmuxLayoutNode])
    case vertical(children: [TmuxLayoutNode])
}
```

`TmuxPaneLayoutView` 递归渲染：
- `.pane` → 从 `paneSurfaces[id]` 取 surface，渲染为 `SurfaceView`，active pane 高亮边框
- `.horizontal` / `.vertical` → `HStack` / `VStack`，子节点间插入 `TmuxDivider`

---

## 可拖拽分割线

`TmuxDivider`（4pt），`DragGesture.onEnded` 发 `resize-pane`：

```swift
// px → tmux cell 换算
let cellWidth: CGFloat = ghostty.config.fontCellWidth   // 从 Ghostty.App config 取
let cellHeight: CGFloat = ghostty.config.fontCellHeight
let cells = Int(abs(delta) / (axis == .vertical ? cellWidth : cellHeight))
guard cells > 0 else { return }
let flag = axis == .vertical
    ? (delta > 0 ? "-R" : "-L")
    : (delta > 0 ? "-D" : "-U")
sessionManager.send("resize-pane -t %\(leadingPaneId) \(flag) \(cells)")
```

- `leadingPaneId`：divider 左侧（或上侧）的 pane id
- 拖拽期间本地预览偏移（`@GestureState`），`onEnded` 才发命令
- 最终 layout 以 tmux 返回的 `.windows` 快照为准，poltertty 不自维护尺寸

---

## 上游跟踪策略

| 文件 | 策略 | 冲突风险 |
|---|---|---|
| `src/terminal/tmux/*.zig` | 完全不动，直接接受上游变更 | 零 |
| `src/terminal/tmux_capi.zig` | poltertty 新增文件 | 零 |
| `src/main_c.zig` | 追加一行 comptime 引用 | 低（追加，不修改现有） |
| `include/ghostty.h` | 末尾追加专属区块，不修改现有内容 | 低 |
| `build.zig` | 若需要，追加新文件编译条目 | 低 |
| `macos/Sources/` | 全新 Swift 文件 | 零 |

**唯一逻辑适配点**：若上游重构 `viewer.zig` 的 `Window` / `Action` 类型，只需更新 `tmux_capi.zig` 的映射，无 git merge 冲突。

---

## 实现阶段

1. **阶段一（Zig 桥接层）**：`tmux_capi.zig` + `ghostty.h` + `src/main_c.zig` 引用 + `Ghostty.TmuxViewer` + `TmuxPTYProcess`
2. **阶段二（Session 管理 + Tab）**：`TmuxSessionManager`（含 command feedback loop + windows diff）+ `TabBarViewModel` tmux 分支
3. **阶段三（Pane 渲染）**：pane output 路由 + `paneSurfaces` 生命周期 + `TmuxPaneLayoutView` + `TmuxDivider`
4. **阶段四（Workspace UI）**：`WorkspaceMode` + `WorkspaceModel` Codable + `WorkspaceCreateForm` + `WorkspaceSnapshot` 适配
