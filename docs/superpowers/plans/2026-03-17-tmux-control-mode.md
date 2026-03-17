# tmux Control Mode Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Poltertty Workspace 增加可选的 tmux 模式，tab = tmux window，pane = 真实 ghostty_surface_t，分割线可拖拽。

**Architecture:** 新增 `tmux_capi.zig` 薄包装层暴露 viewer.zig 给 Swift（C API bridge），不动任何上游 Zig 文件。Swift 层 `TmuxSessionManager` 处理 PTY 进程和 Action feedback loop，`TmuxPaneLayoutView` 递归渲染 pane 树。

**Tech Stack:** Zig (tmux_capi.zig), Swift/SwiftUI (Workspace layer), GhosttyKit C interop, Swift Testing

---

## 文件结构

### 新增文件

| 文件 | 职责 |
|---|---|
| `src/terminal/tmux_capi.zig` | C API wrapper：解析字节 → 拦截 output → 驱动 Viewer |
| `macos/Sources/Ghostty/Ghostty.TmuxViewer.swift` | 包装 ghostty_tmux_viewer_t opaque pointer |
| `macos/Sources/Features/Workspace/Tmux/TmuxPTYProcess.swift` | 启动/读写 tmux -CC 进程的 PTY 包装 |
| `macos/Sources/Features/Workspace/Tmux/TmuxWindowState.swift` | window 快照数据结构 + diff 逻辑 |
| `macos/Sources/Features/Workspace/Tmux/TmuxSessionManager.swift` | 业务逻辑：PTY、viewer、tab bar、pane surface 生命周期 |
| `macos/Sources/Features/Workspace/Tmux/TmuxPaneLayoutView.swift` | SwiftUI 递归 pane 分屏渲染 |
| `macos/Sources/Features/Workspace/Tmux/TmuxDivider.swift` | 可拖拽分割线，发 resize-pane 命令 |
| `macos/Tests/Splits/TmuxWindowDiffTests.swift` | TmuxWindowDiff 纯逻辑单元测试（放入已有 Splits 目录）|
（TmuxLayoutNode 解析测试可在后续迭代补充）|

### 修改文件（仅追加，不改现有内容）

| 文件 | 变更 |
|---|---|
| `include/ghostty.h` | 末尾追加 poltertty tmux extension block（在 benchmark API 前） |
| `src/main_c.zig` | comptime block 追加 `_ = @import("terminal/tmux_capi.zig");` |
| `macos/Sources/Features/Workspace/WorkspaceModel.swift` | 新增 WorkspaceMode enum + mode 字段 |
| `macos/Sources/Features/Workspace/WorkspaceManager.swift` | create() 增加 mode 参数 |
| `macos/Sources/Features/Workspace/WorkspaceCreateForm.swift` | onSubmit 改为 WorkspaceCreateConfig，新增 mode 选择 UI |
| `macos/Sources/Features/Workspace/PolterttyRootView.swift` | terminalAreaView 增加 tmux 模式分支 |
| `macos/Sources/Features/Workspace/TabBar/TabBarViewModel.swift` | 增加 tmux tab 管理方法 |

---

## Phase 1: Zig 桥接层

### Task 1: tmux_capi.zig — C 结构体和导出函数

**文件:**
- Create: `src/terminal/tmux_capi.zig`

- [ ] **Step 1.1: 新建文件，定义 C 结构体**

```zig
// src/terminal/tmux_capi.zig
// このファイルは src/terminal/ に置く。インポートパスは src/terminal/ 相対
const std = @import("std");
const Allocator = std.mem.Allocator;
const control = @import("tmux/control.zig");
const viewer_mod = @import("tmux/viewer.zig");
const layout_mod = @import("tmux/layout.zig");

const log = std.log.scoped(.tmux_capi);

/// Layout 节点。约定：
///   leaf:      split_type=0，pane_id 有效，children_ptr=null，children_len=0
///   container: split_type=1(horizontal)/2(vertical)，pane_id=0，children_ptr 指向子数组
pub const ghostty_tmux_layout_node_s = extern struct {
    pane_id: usize,
    x: usize,
    y: usize,
    width: usize,
    height: usize,
    split_type: u8, // 0=leaf, 1=horizontal, 2=vertical
    children_ptr: ?[*]ghostty_tmux_layout_node_s,
    children_len: usize,
};

pub const ghostty_tmux_window_s = extern struct {
    id: usize,
    width: usize,
    height: usize,
    root_layout: ghostty_tmux_layout_node_s,
};

pub const ghostty_tmux_action_tag_e = enum(c_int) {
    command = 0,
    windows = 1,
    exit = 2,
};

pub const ghostty_tmux_action_s = extern struct {
    tag: ghostty_tmux_action_tag_e,
    command_ptr: ?[*]const u8,
    command_len: usize,
    windows_ptr: ?[*]ghostty_tmux_window_s,
    windows_len: usize,
};

pub const ghostty_tmux_action_cb = *const fn (
    userdata: ?*anyopaque,
    action: ghostty_tmux_action_s,
) callconv(.C) void;

pub const ghostty_tmux_pane_output_cb = *const fn (
    userdata: ?*anyopaque,
    pane_id: usize,
    data_ptr: [*]const u8,
    data_len: usize,
) callconv(.C) void;
```

- [ ] **Step 1.2: 定义内部 State struct 和 viewer_new**

```zig
/// 内部状态，持有 ControlParser + Viewer + allocator
const TmuxCApi = struct {
    alloc: Allocator,
    parser: control.Parser,
    viewer: viewer_mod.Viewer,
    userdata: ?*anyopaque,
    action_cb: ghostty_tmux_action_cb,
    pane_output_cb: ?ghostty_tmux_pane_output_cb,
    // windows_buf: 顶层 window 列表（C callback 存活期间有效）
    windows_buf: std.ArrayList(ghostty_tmux_window_s),
    // layout_arena: 存储递归转换的 layout 节点（每次 .windows action 前 reset）
    layout_arena: std.heap.ArenaAllocator,

    fn deinit(self: *TmuxCApi) void {
        self.parser.deinit();
        self.viewer.deinit();          // Viewer 内部持有 allocator，无需传参
        self.layout_arena.deinit();
        self.windows_buf.deinit();
        self.alloc.destroy(self);
    }
};

pub export fn ghostty_tmux_viewer_new(
    userdata: ?*anyopaque,
    action_cb: ghostty_tmux_action_cb,
    pane_output_cb: ?ghostty_tmux_pane_output_cb,
) ?*anyopaque {
    const alloc = std.heap.c_allocator;
    const state = alloc.create(TmuxCApi) catch return null;
    state.* = .{
        .alloc = alloc,
        // Parser 用 struct literal 初始化（无 init() 函数）
        .parser = .{ .buffer = .init(alloc) },
        .viewer = viewer_mod.Viewer.init(alloc) catch {
            alloc.destroy(state);
            return null;
        },
        .userdata = userdata,
        .action_cb = action_cb,
        .pane_output_cb = pane_output_cb,
        .windows_buf = std.ArrayList(ghostty_tmux_window_s).init(alloc),
        .layout_arena = std.heap.ArenaAllocator.init(alloc),
    };
    return state;
}
```

- [ ] **Step 1.3: 实现 feed — 解析字节，拦截 output，驱动 viewer**

```zig
pub export fn ghostty_tmux_viewer_feed(
    handle: ?*anyopaque,
    data: [*]const u8,
    len: usize,
) void {
    const state: *TmuxCApi = @ptrCast(@alignCast(handle orelse return));
    for (data[0..len]) |byte| {
        const notif = state.parser.put(byte) catch continue orelse continue;

        // 拦截 output 事件，在 viewer 处理前发给 Swift
        if (notif == .output) {
            if (state.pane_output_cb) |cb| {
                cb(state.userdata, notif.output.pane_id, notif.output.data.ptr, notif.output.data.len);
            }
        }

        // 喂给 viewer（返回 []const Action，不是 optional）
        const actions = state.viewer.next(.{ .tmux = notif });
        for (actions) |action| dispatchAction(state, action);
    }
}

fn dispatchAction(state: *TmuxCApi, action: viewer_mod.Viewer.Action) void {
    switch (action) {
        .exit => state.action_cb(state.userdata, .{ .tag = .exit, .command_ptr = null, .command_len = 0, .windows_ptr = null, .windows_len = 0 }),
        .command => |cmd| state.action_cb(state.userdata, .{ .tag = .command, .command_ptr = cmd.ptr, .command_len = cmd.len, .windows_ptr = null, .windows_len = 0 }),
        .windows => |wins| {
            // reset arena，释放上次转换的 layout 节点
            _ = state.layout_arena.reset(.retain_capacity);
            const arena_alloc = state.layout_arena.allocator();
            state.windows_buf.clearRetainingCapacity();
            for (wins) |w| {
                const c_win = convertWindow(arena_alloc, w) catch continue;
                state.windows_buf.append(c_win) catch continue;
            }
            state.action_cb(state.userdata, .{
                .tag = .windows,
                .command_ptr = null, .command_len = 0,
                .windows_ptr = state.windows_buf.items.ptr,
                .windows_len = state.windows_buf.items.len,
            });
        },
    }
}
```

- [ ] **Step 1.4: 实现 layout 转换和其余 exports**

```zig
/// 递归转换 Layout 树。alloc 是 layout_arena 的 allocator，生命周期与本次 .windows 回调绑定。
fn convertLayout(alloc: Allocator, layout: layout_mod.Layout) Allocator.Error!ghostty_tmux_layout_node_s {
    return switch (layout.content) {
        .pane => |pane_id| .{
            .pane_id = pane_id, .x = layout.x, .y = layout.y,
            .width = layout.width, .height = layout.height,
            .split_type = 0, .children_ptr = null, .children_len = 0,
        },
        .horizontal => |children| blk: {
            // 分配 C 节点数组（arena 管理，回调结束前有效）
            const c_children = try alloc.alloc(ghostty_tmux_layout_node_s, children.len);
            for (children, 0..) |child, i| {
                c_children[i] = try convertLayout(alloc, child);
            }
            break :blk .{
                .pane_id = 0, .x = layout.x, .y = layout.y,
                .width = layout.width, .height = layout.height,
                .split_type = 1,
                .children_ptr = c_children.ptr,
                .children_len = c_children.len,
            };
        },
        .vertical => |children| blk: {
            const c_children = try alloc.alloc(ghostty_tmux_layout_node_s, children.len);
            for (children, 0..) |child, i| {
                c_children[i] = try convertLayout(alloc, child);
            }
            break :blk .{
                .pane_id = 0, .x = layout.x, .y = layout.y,
                .width = layout.width, .height = layout.height,
                .split_type = 2,
                .children_ptr = c_children.ptr,
                .children_len = c_children.len,
            };
        },
    };
}

fn convertWindow(alloc: Allocator, w: viewer_mod.Viewer.Window) Allocator.Error!ghostty_tmux_window_s {
    return .{
        .id = w.id, .width = w.width, .height = w.height,
        .root_layout = try convertLayout(alloc, w.layout),
    };
}

pub export fn ghostty_tmux_viewer_send(handle: ?*anyopaque, cmd: [*]const u8, len: usize) void {
    // poltertty UI → tmux 命令（e.g. "new-window\n"）
    // 由 Swift 直接写到 PTY stdin，这里是预留接口（可选实现为直接写 PTY）
    // 实际上 Swift 侧直接调 TmuxPTYProcess.write() 更简单，此 export 可为空实现
    _ = handle; _ = cmd; _ = len;
}

pub export fn ghostty_tmux_viewer_free(handle: ?*anyopaque) void {
    if (handle) |h| {
        const state: *TmuxCApi = @ptrCast(@alignCast(h));
        state.deinit();
    }
}
```

- [ ] **Step 1.5: 验证 Zig 编译**

```bash
make check
```
预期：无编译错误

- [ ] **Step 1.6: Commit**

```bash
git add src/terminal/tmux_capi.zig
git commit -m "feat(zig): add tmux_capi.zig C API wrapper for tmux viewer"
```

---

### Task 2: 暴露 C API 给 Swift

**文件:**
- Modify: `src/main_c.zig`
- Modify: `include/ghostty.h`

- [ ] **Step 2.1: main_c.zig 追加 comptime 引用**

在 `/Users/aaronlin/works/codes/oss/poltertty/src/main_c.zig` 的 `comptime { ... }` 块末尾（在最后一个 `_` 赋值后，`}` 之前）追加：

```zig
    // Poltertty tmux extensions
    // main_c.zig 位于 src/，路径相对于 src/
    _ = @import("terminal/tmux_capi.zig");
```

> 注：`tmux_capi.zig` 位于 `src/terminal/`，内部 imports 使用相对路径（`tmux/control.zig` 等）。`main_c.zig` 引用时用 `terminal/tmux_capi.zig`，两者路径基准不同，都是正确的。

- [ ] **Step 2.2: ghostty.h 追加 poltertty tmux extension block**

在 `/Users/aaronlin/works/codes/oss/poltertty/include/ghostty.h` 的 benchmark API 声明之前追加（约 line 1171）：

```c
// ===== Poltertty tmux Extensions =====
typedef void* ghostty_tmux_viewer_t;

// 注意：递归自引用需要 struct tag 名，不能只用 typedef
typedef struct ghostty_tmux_layout_node_s {
    size_t pane_id;
    size_t x, y, width, height;
    uint8_t split_type; // 0=leaf, 1=horizontal, 2=vertical
    struct ghostty_tmux_layout_node_s* children_ptr;
    size_t children_len;
} ghostty_tmux_layout_node_s;

typedef struct {
    size_t id;
    size_t width;
    size_t height;
    ghostty_tmux_layout_node_s root_layout;
} ghostty_tmux_window_s;

typedef enum {
    GHOSTTY_TMUX_ACTION_COMMAND = 0,
    GHOSTTY_TMUX_ACTION_WINDOWS = 1,
    GHOSTTY_TMUX_ACTION_EXIT    = 2,
} ghostty_tmux_action_tag_e;

typedef struct {
    ghostty_tmux_action_tag_e tag;
    const char* command_ptr;
    size_t command_len;
    ghostty_tmux_window_s* windows_ptr;
    size_t windows_len;
} ghostty_tmux_action_s;

typedef void (*ghostty_tmux_action_cb)(void* userdata, ghostty_tmux_action_s action);
typedef void (*ghostty_tmux_pane_output_cb)(void* userdata, size_t pane_id, const char* data, size_t len);

ghostty_tmux_viewer_t ghostty_tmux_viewer_new(
    void* userdata,
    ghostty_tmux_action_cb action_cb,
    ghostty_tmux_pane_output_cb pane_output_cb
);
void ghostty_tmux_viewer_feed(ghostty_tmux_viewer_t, const char* data, size_t len);
void ghostty_tmux_viewer_send(ghostty_tmux_viewer_t, const char* cmd, size_t len);
void ghostty_tmux_viewer_free(ghostty_tmux_viewer_t);
// ===== End Poltertty tmux Extensions =====
```

- [ ] **Step 2.3: 验证 Swift 能看到新符号**

```bash
make check
```
预期：无编译错误，GhosttyKit module 可见新符号

- [ ] **Step 2.4: Commit**

```bash
git add src/main_c.zig include/ghostty.h
git commit -m "feat(bridge): expose tmux C API to Swift via GhosttyKit"
```

---

## Phase 2: Swift PTY + Viewer 包装

### Task 3: TmuxPTYProcess — PTY 进程管理

**文件:**
- Create: `macos/Sources/Features/Workspace/Tmux/TmuxPTYProcess.swift`

> 注：与 Ghostty surface 内部的 PTY 完全独立，仅用于 `tmux -CC` 控制进程。

- [ ] **Step 3.1: 实现 TmuxPTYProcess**

```swift
// macos/Sources/Features/Workspace/Tmux/TmuxPTYProcess.swift
import Foundation

/// tmux -CC 控制进程的 PTY 包装。
/// 独立于 Ghostty surface 的 PTY 管理，仅用于 tmux control mode。
@MainActor
final class TmuxPTYProcess {
    var onData: ((Data) -> Void)?

    private var process: Process?
    private var masterFD: Int32 = -1
    private var readSource: DispatchSourceRead?

    func launch(command: String) throws {
        // 创建 PTY pair
        var master: Int32 = 0
        var slave: Int32 = 0
        var winsize = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &winsize) == 0 else {
            throw TmuxError.ptyCreationFailed
        }
        self.masterFD = master

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", command]

        // 将 slave 端绑定到 stdin/stdout/stderr
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
        proc.standardInput = slaveHandle
        proc.standardOutput = slaveHandle
        proc.standardError = slaveHandle

        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.cleanup() }
        }

        try proc.run()
        self.process = proc

        // 监听 master 端输出
        let source = DispatchSource.makeReadSource(fileDescriptor: master, queue: .main)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        source.resume()
        self.readSource = source
    }

    func write(_ data: Data) {
        guard masterFD >= 0 else { return }
        data.withUnsafeBytes { ptr in
            _ = Foundation.write(masterFD, ptr.baseAddress, ptr.count)
        }
    }

    func write(_ string: String) {
        write(Data(string.utf8))
    }

    func terminate() {
        process?.terminate()
        cleanup()
    }

    private func readAvailable() {
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = read(masterFD, &buf, buf.count)
        guard n > 0 else { cleanup(); return }
        onData?(Data(buf[0..<n]))
    }

    private func cleanup() {
        readSource?.cancel()
        readSource = nil
        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }
        process = nil
    }

    deinit { cleanup() }
}

enum TmuxError: Error {
    case ptyCreationFailed
    case processLaunchFailed
}
```

- [ ] **Step 3.2: 验证编译**

```bash
make check
```
预期：无编译错误

- [ ] **Step 3.3: Commit**

```bash
git add macos/Sources/Features/Workspace/Tmux/TmuxPTYProcess.swift
git commit -m "feat(tmux): add TmuxPTYProcess for tmux -CC PTY management"
```

---

### Task 4: Ghostty.TmuxViewer — Swift wrapper

**文件:**
- Create: `macos/Sources/Ghostty/Ghostty.TmuxViewer.swift`

- [ ] **Step 4.1: 实现 Ghostty.TmuxViewer**

```swift
// macos/Sources/Ghostty/Ghostty.TmuxViewer.swift
import GhosttyKit
import Foundation

extension Ghostty {
    /// 包装 ghostty_tmux_viewer_t opaque pointer。
    /// 与 Ghostty.Surface 模式一致：C callback → Swift closure。
    final class TmuxViewer {
        private var handle: ghostty_tmux_viewer_t?
        var onAction: ((TmuxViewerAction) -> Void)?
        var onPaneOutput: ((_ paneId: UInt, _ data: Data) -> Void)?

        init() {
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            handle = ghostty_tmux_viewer_new(selfPtr, { userdata, action in
                guard let userdata else { return }
                let viewer = Unmanaged<TmuxViewer>.fromOpaque(userdata).takeUnretainedValue()
                viewer.handleAction(action)
            }, { userdata, paneId, dataPtr, dataLen in
                guard let userdata, let dataPtr else { return }
                let viewer = Unmanaged<TmuxViewer>.fromOpaque(userdata).takeUnretainedValue()
                viewer.onPaneOutput?(paneId, Data(bytes: dataPtr, count: dataLen))
            })
        }

        func feed(_ data: Data) {
            guard let handle else { return }
            data.withUnsafeBytes { ptr in
                guard let base = ptr.baseAddress else { return }
                ghostty_tmux_viewer_feed(handle, base.assumingMemoryBound(to: CChar.self), ptr.count)
            }
        }

        deinit {
            if let handle { ghostty_tmux_viewer_free(handle) }
        }

        private func handleAction(_ action: ghostty_tmux_action_s) {
            switch action.tag {
            case GHOSTTY_TMUX_ACTION_COMMAND:
                guard let ptr = action.command_ptr else { return }
                let cmd = String(bytes: Data(bytes: ptr, count: action.command_len), encoding: .utf8) ?? ""
                onAction?(.command(cmd))
            case GHOSTTY_TMUX_ACTION_WINDOWS:
                let windows = (0..<action.windows_len).map { i in
                    TmuxWindowSnapshot(from: action.windows_ptr![i])
                }
                onAction?(.windows(windows))
            case GHOSTTY_TMUX_ACTION_EXIT:
                onAction?(.exit)
            default:
                break
            }
        }
    }
}

enum TmuxViewerAction {
    case command(String)
    case windows([TmuxWindowSnapshot])
    case exit
}
```

- [ ] **Step 4.2: 验证编译**

```bash
make check
```

- [ ] **Step 4.3: Commit**

```bash
git add macos/Sources/Ghostty/Ghostty.TmuxViewer.swift
git commit -m "feat(tmux): add Ghostty.TmuxViewer Swift wrapper for tmux C API"
```

---

## Phase 3: Session 管理 + Tab Bar

### Task 5: TmuxWindowState — 数据结构 + Diff 逻辑

**文件:**
- Create: `macos/Sources/Features/Workspace/Tmux/TmuxWindowState.swift`
- Create: `macos/Tests/Workspace/TmuxWindowDiffTests.swift`

- [ ] **Step 5.1: 先写测试**

> 注：项目使用 Swift Testing 框架（`import Testing`），与现有测试保持一致。
> 新文件放入 `macos/Tests/Splits/` 目录（已有目录），并在 Xcode 中 add to target GhosttyTests。

```swift
// macos/Tests/Splits/TmuxWindowDiffTests.swift
import Testing
@testable import Ghostty

@Suite struct TmuxWindowDiffTests {
    @Test func addedWindows() {
        let prev: [TmuxWindowSnapshot] = []
        let next = [TmuxWindowSnapshot(id: 1, width: 80, height: 24, rootLayout: .pane(id: 0, frame: .zero))]
        let diff = TmuxWindowDiff(prev: prev, next: next)
        #expect(diff.added.map(\.id) == [1])
        #expect(diff.removed.isEmpty)
        #expect(diff.updated.isEmpty)
    }

    @Test func removedWindows() {
        let prev = [TmuxWindowSnapshot(id: 1, width: 80, height: 24, rootLayout: .pane(id: 0, frame: .zero))]
        let next: [TmuxWindowSnapshot] = []
        let diff = TmuxWindowDiff(prev: prev, next: next)
        #expect(diff.removed.map(\.id) == [1])
        #expect(diff.added.isEmpty)
    }

    @Test func updatedLayout() {
        let w1 = TmuxWindowSnapshot(id: 1, width: 80, height: 24, rootLayout: .pane(id: 0, frame: .zero))
        let w2 = TmuxWindowSnapshot(id: 1, width: 100, height: 24, rootLayout: .pane(id: 0, frame: .zero))
        let diff = TmuxWindowDiff(prev: [w1], next: [w2])
        #expect(diff.updated.map(\.id) == [1])
        #expect(diff.added.isEmpty)
        #expect(diff.removed.isEmpty)
    }
}
```

- [ ] **Step 5.2: 运行测试确认 fail**

```bash
# scheme 是 Ghostty（不是 GhosttyTests）
xcodebuild test -scheme Ghostty -only-testing:GhosttyTests/TmuxWindowDiffTests 2>&1 | tail -20
```
预期：编译错误（类型未定义）

- [ ] **Step 5.3: 实现数据结构**

```swift
// macos/Sources/Features/Workspace/Tmux/TmuxWindowState.swift
import CoreGraphics
import GhosttyKit

// MARK: - Layout 树

indirect enum TmuxLayoutNode {
    /// UInt 对应 Zig usize，避免 64-bit pane ID 截断
    case pane(id: UInt, frame: CGRect)
    case horizontal(children: [TmuxLayoutNode])
    case vertical(children: [TmuxLayoutNode])
}

extension TmuxLayoutNode {
    init(from node: ghostty_tmux_layout_node_s) {
        let frame = CGRect(x: CGFloat(node.x), y: CGFloat(node.y),
                           width: CGFloat(node.width), height: CGFloat(node.height))
        switch node.split_type {
        case 0: // leaf
            self = .pane(id: node.pane_id, frame: frame)
        case 1: // horizontal
            let children = (0..<node.children_len).map { TmuxLayoutNode(from: node.children_ptr![$0]) }
            self = .horizontal(children: children)
        default: // vertical
            let children = (0..<node.children_len).map { TmuxLayoutNode(from: node.children_ptr![$0]) }
            self = .vertical(children: children)
        }
    }
}

// MARK: - Window 快照

struct TmuxWindowSnapshot: Equatable {
    let id: UInt          // UInt 对应 Zig usize
    let width: UInt
    let height: UInt
    let rootLayout: TmuxLayoutNode

    init(id: UInt, width: UInt, height: UInt, rootLayout: TmuxLayoutNode) {
        self.id = id; self.width = width; self.height = height; self.rootLayout = rootLayout
    }

    init(from c: ghostty_tmux_window_s) {
        id = c.id; width = c.width; height = c.height
        rootLayout = TmuxLayoutNode(from: c.root_layout)
    }

    static func == (lhs: TmuxWindowSnapshot, rhs: TmuxWindowSnapshot) -> Bool {
        lhs.id == rhs.id && lhs.width == rhs.width && lhs.height == rhs.height
    }
}

// MARK: - Diff

struct TmuxWindowDiff {
    let added: [TmuxWindowSnapshot]
    let removed: [TmuxWindowSnapshot]
    let updated: [TmuxWindowSnapshot]

    init(prev: [TmuxWindowSnapshot], next: [TmuxWindowSnapshot]) {
        let prevIds = Set(prev.map(\.id))
        let nextIds = Set(next.map(\.id))
        let prevMap = Dictionary(uniqueKeysWithValues: prev.map { ($0.id, $0) })

        added   = next.filter { !prevIds.contains($0.id) }
        removed = prev.filter { !nextIds.contains($0.id) }
        updated = next.filter { prevIds.contains($0.id) && $0 != prevMap[$0.id]! }
    }
}
```

- [ ] **Step 5.4: 运行测试确认通过**

```bash
xcodebuild test -scheme Ghostty -only-testing:GhosttyTests/TmuxWindowDiffTests 2>&1 | tail -20
```
预期：3 tests passed

- [ ] **Step 5.5: Commit**

```bash
git add macos/Sources/Features/Workspace/Tmux/TmuxWindowState.swift macos/Tests/Splits/TmuxWindowDiffTests.swift
git commit -m "feat(tmux): add TmuxWindowState data structures and diff logic with tests"
```

---

### Task 6: TmuxSessionManager — 业务逻辑核心

**文件:**
- Create: `macos/Sources/Features/Workspace/Tmux/TmuxSessionManager.swift`

- [ ] **Step 6.1: 实现 TmuxSessionManager**

```swift
// macos/Sources/Features/Workspace/Tmux/TmuxSessionManager.swift
import Foundation
import SwiftUI

@MainActor
final class TmuxSessionManager: ObservableObject {
    // 驱动 TabBarViewModel（tmux tab 分支）
    weak var tabBarViewModel: TabBarViewModel?

    @Published private(set) var windowLayouts: [UInt: TmuxLayoutNode] = [:]
    @Published private(set) var activePaneId: UInt = 0

    // pane_id → Ghostty.SurfaceView（NSView-backed ObservableObject，供 SurfaceWrapper 使用）
    // 注：是 Ghostty.SurfaceView 而非 Ghostty.Surface（后者是薄包装，没有 .view 属性）
    private var paneSurfaces: [UInt: Ghostty.SurfaceView] = [:]
    private var currentWindows: [TmuxWindowSnapshot] = []

    private let viewer = Ghostty.TmuxViewer()
    private var ptyProcess: TmuxPTYProcess?

    // 需要 ghostty app 引用来创建 surface
    private weak var ghosttyApp: Ghostty.App?

    init(ghosttyApp: Ghostty.App) {
        self.ghosttyApp = ghosttyApp
        setupViewer()
    }

    func attach(command: String) throws {
        let proc = TmuxPTYProcess()
        proc.onData = { [weak self] data in self?.viewer.feed(data) }
        try proc.launch(command: command)
        self.ptyProcess = proc
    }

    func detach() {
        sendToTmux("detach-client\n")
    }

    // MARK: - poltertty UI → tmux

    func newWindow()              { sendToTmux("new-window\n") }
    func closeWindow(_ id: UInt)  { sendToTmux("kill-window -t @\(id)\n") }
    func splitHorizontal()        { sendToTmux("split-window -h\n") }
    func splitVertical()          { sendToTmux("split-window -v\n") }
    func focusPane(_ id: UInt)    { sendToTmux("select-pane -t %\(id)\n") }
    func resizePane(id: UInt, flag: String, cells: Int) {
        sendToTmux("resize-pane -t %\(id) \(flag) \(cells)\n")
    }

    func sendToTmux(_ cmd: String) {
        ptyProcess?.write(cmd)
    }

    // MARK: - Action 处理

    private func setupViewer() {
        viewer.onAction = { [weak self] action in self?.handleAction(action) }
        viewer.onPaneOutput = { [weak self] paneId, data in
            guard let surface = self?.paneSurfaces[paneId] else { return }
            surface.sendText(String(data: data, encoding: .utf8) ?? "")
        }
    }

    private func handleAction(_ action: TmuxViewerAction) {
        switch action {
        case .command(let cmd):
            // 必须写回 PTY stdin 驱动 viewer 状态机
            ptyProcess?.write(cmd)

        case .windows(let snapshot):
            let diff = TmuxWindowDiff(prev: currentWindows, next: snapshot)
            diff.added.forEach   { addTmuxTab($0) }
            diff.removed.forEach { removeTmuxTab($0.id) }
            diff.updated.forEach { updateTmuxWindow($0) }
            currentWindows = snapshot

        case .exit:
            detachCleanup()
        }
    }

    private func addTmuxTab(_ window: TmuxWindowSnapshot) {
        windowLayouts[window.id] = window.rootLayout
        updatePaneSurfaces(for: window)
        // 使用 tab bar 当前数量+1 作为标题，避免依赖尚未更新的 currentWindows
        let tabCount = (tabBarViewModel?.tabs.count ?? 0) + 1
        let title = "Window \(tabCount)"
        tabBarViewModel?.addTmuxTab(windowId: window.id, title: title)
    }

    private func removeTmuxTab(_ windowId: UInt) {
        windowLayouts.removeValue(forKey: windowId)
        tabBarViewModel?.removeTmuxTab(windowId: windowId)
    }

    private func updateTmuxWindow(_ window: TmuxWindowSnapshot) {
        windowLayouts[window.id] = window.rootLayout
        updatePaneSurfaces(for: window)
    }

    private func updatePaneSurfaces(for window: TmuxWindowSnapshot) {
        let paneIds = collectPaneIds(from: window.rootLayout)
        // 新增 pane：通过 Ghostty.App 创建新 surface
        // Ghostty.App 没有公开的 newSurface()，需通过发送 open_tab action 或
        // 直接调用 ghostty_surface_new() C API 创建 surface（实现阶段确认具体 API）
        // 占位实现：开发者需在此处接入实际 surface 创建路径
        for paneId in paneIds where paneSurfaces[paneId] == nil {
            // TODO: 创建 Ghostty.SurfaceView 实例
            // SurfaceView 是 NSView subclass（ObservableObject），通过 ghostty_surface_new() 初始化
            // 参考 TerminalController.swift 中创建 surface 的方式
            // let surfaceView = Ghostty.SurfaceView(app: ghosttyApp.app, config: ghosttyApp.config)
            // paneSurfaces[paneId] = surfaceView
            _ = paneId
        }
        // 移除消失的 pane
        for paneId in paneSurfaces.keys where !paneIds.contains(paneId) {
            paneSurfaces.removeValue(forKey: paneId)
        }
    }

    private func collectPaneIds(from node: TmuxLayoutNode) -> Set<UInt> {
        switch node {
        case .pane(let id, _): return [id]
        case .horizontal(let children), .vertical(let children):
            return children.reduce(into: Set<UInt>()) { $0.formUnion(collectPaneIds(from: $1)) }
        }
    }

    private func detachCleanup() {
        ptyProcess?.terminate()
        ptyProcess = nil
        paneSurfaces.removeAll()
        windowLayouts.removeAll()
        currentWindows.removeAll()
    }

    func surface(for paneId: UInt) -> Ghostty.SurfaceView? {
        paneSurfaces[paneId]
    }
}
```

- [ ] **Step 6.2: 验证编译**

```bash
make check
```

- [ ] **Step 6.3: Commit**

```bash
git add macos/Sources/Features/Workspace/Tmux/TmuxSessionManager.swift
git commit -m "feat(tmux): add TmuxSessionManager with action feedback loop and pane surface lifecycle"
```

---

### Task 7: TabBarViewModel tmux 扩展

**文件:**
- Modify: `macos/Sources/Features/Workspace/TabBar/TabBarViewModel.swift`

- [ ] **Step 7.1: 在 TabBarViewModel 末尾追加 tmux tab 方法**

```swift
// 追加到 TabBarViewModel 末尾

// MARK: - tmux Tab 管理

/// tmux 模式：用 windowId 作为 tab 标识符（独立于 surfaceId）
private var tmuxWindowIds: [UUID: UInt] = [:]  // tabId → tmuxWindowId

func addTmuxTab(windowId: UInt, title: String) {
    var item = TabItem(title: title, surfaceId: UUID())  // surfaceId 占位，tmux 模式不使用
    item.isActive = true
    for i in tabs.indices { tabs[i].isActive = false }
    tabs.append(item)
    tmuxWindowIds[item.id] = windowId
    activeTabId = item.id
}

func removeTmuxTab(windowId: UInt) {
    guard let tabId = tmuxWindowIds.first(where: { $0.value == windowId })?.key else { return }
    tmuxWindowIds.removeValue(forKey: tabId)
    closeTab(tabId)
}

func activeTmuxWindowId() -> UInt? {
    guard let activeTabId else { return nil }
    return tmuxWindowIds[activeTabId]
}
```

- [ ] **Step 7.2: 验证编译**

```bash
make check
```

- [ ] **Step 7.3: Commit**

```bash
git add macos/Sources/Features/Workspace/TabBar/TabBarViewModel.swift
git commit -m "feat(tmux): add tmux tab management methods to TabBarViewModel"
```

---

## Phase 4: Pane 渲染

### Task 8: TmuxPaneLayoutView — 递归分屏渲染

**文件:**
- Create: `macos/Sources/Features/Workspace/Tmux/TmuxPaneLayoutView.swift`
- Create: `macos/Sources/Features/Workspace/Tmux/TmuxDivider.swift`

- [ ] **Step 8.1: 实现 TmuxPaneLayoutView**

```swift
// macos/Sources/Features/Workspace/Tmux/TmuxPaneLayoutView.swift
import SwiftUI

struct TmuxPaneLayoutView: View {
    let layout: TmuxLayoutNode
    let activePaneId: UInt
    @ObservedObject var sessionManager: TmuxSessionManager
    @EnvironmentObject var ghostty: Ghostty.App  // 传给 SurfaceWrapper

    var body: some View {
        switch layout {
        case .pane(let id, _):
            paneView(id: id)

        case .horizontal(let children):
            HStack(spacing: 0) {
                ForEach(Array(children.enumerated()), id: \.offset) { i, child in
                    TmuxPaneLayoutView(layout: child, activePaneId: activePaneId, sessionManager: sessionManager)
                    if i < children.count - 1 {
                        TmuxDivider(axis: .vertical, leadingPaneId: leafId(of: child),
                                    sessionManager: sessionManager)
                    }
                }
            }

        case .vertical(let children):
            VStack(spacing: 0) {
                ForEach(Array(children.enumerated()), id: \.offset) { i, child in
                    TmuxPaneLayoutView(layout: child, activePaneId: activePaneId, sessionManager: sessionManager)
                    if i < children.count - 1 {
                        TmuxDivider(axis: .horizontal, leadingPaneId: leafId(of: child),
                                    sessionManager: sessionManager)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func paneView(id: UInt) -> some View {
        if let surfaceView = sessionManager.surface(for: id) {
            // surface(for:) 返回 Ghostty.SurfaceView（NSView-backed），直接传给 SurfaceWrapper
            Ghostty.SurfaceWrapper(surfaceView: surfaceView)
                .overlay(
                    activePaneId == id
                        ? RoundedRectangle(cornerRadius: 0).stroke(Color.accentColor, lineWidth: 1)
                        : nil
                )
                .onTapGesture { sessionManager.focusPane(id) }
                .environmentObject(ghostty)  // SurfaceWrapper 需要 ghostty EnvironmentObject
        } else {
            Color.black  // placeholder while surface initializes
        }
    }

    /// 取 layout 树中第一个 leaf pane 的 id（用于 divider 标识）
    private func leafId(of node: TmuxLayoutNode) -> UInt {
        switch node {
        case .pane(let id, _): return id
        case .horizontal(let c), .vertical(let c): return leafId(of: c[0])
        }
    }
}
```

- [ ] **Step 8.2: 实现 TmuxDivider**

```swift
// macos/Sources/Features/Workspace/Tmux/TmuxDivider.swift
import SwiftUI

struct TmuxDivider: View {
    let axis: Axis               // .vertical = 左右分隔线，.horizontal = 上下分隔线
    let leadingPaneId: UInt
    @ObservedObject var sessionManager: TmuxSessionManager

    @GestureState private var isDragging = false
    @State private var previewOffset: CGFloat = 0

    @EnvironmentObject var ghostty: Ghostty.App

    // 字体格宽高：理想情况从 ghostty.config 取，暂用默认值保底
    // 后续可通过 ghostty.config.fontSize 和字体 metrics 计算精确值
    private var cellWidth: CGFloat  { 8.0 }
    private var cellHeight: CGFloat { 16.0 }

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor.opacity(0.4) : Color.gray.opacity(0.2))
            .frame(
                width:  axis == .vertical   ? 4 : nil,
                height: axis == .horizontal ? 4 : nil
            )
            .offset(
                x: axis == .vertical   ? previewOffset : 0,
                y: axis == .horizontal ? previewOffset : 0
            )
            .gesture(dragGesture)
            // 使用与 SplitView.Divider 相同的 cursor 模式（.onHover + NSCursor）
            .onHover { inside in
                if inside {
                    (axis == .vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { value in
                previewOffset = axis == .vertical ? value.translation.width : value.translation.height
            }
            .onEnded { value in
                previewOffset = 0
                let delta = axis == .vertical ? value.translation.width : value.translation.height
                let cellSize = axis == .vertical ? cellWidth : cellHeight
                let cells = Int(abs(delta) / cellSize)
                guard cells > 0 else { return }
                let flag: String
                if axis == .vertical {
                    flag = delta > 0 ? "-R" : "-L"
                } else {
                    flag = delta > 0 ? "-D" : "-U"
                }
                sessionManager.resizePane(id: leadingPaneId, flag: flag, cells: cells)
            }
    }
}
```

- [ ] **Step 8.3: 验证编译**

```bash
make check
```

- [ ] **Step 8.4: Commit**

```bash
git add macos/Sources/Features/Workspace/Tmux/TmuxPaneLayoutView.swift macos/Sources/Features/Workspace/Tmux/TmuxDivider.swift
git commit -m "feat(tmux): add TmuxPaneLayoutView recursive split view and TmuxDivider"
```

---

## Phase 5: Workspace 模型 + UI

### Task 9: WorkspaceMode + WorkspaceModel 扩展

**文件:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceModel.swift`

- [ ] **Step 9.1: 在 WorkspaceModel.swift 顶部追加 WorkspaceMode**

在文件顶部（`struct WorkspaceModel` 之前）追加：

```swift
// MARK: - WorkspaceMode

enum WorkspaceMode: Equatable {
    case native
    case tmux(sessionName: String, startupCommand: String)
}

extension WorkspaceMode: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, sessionName, startupCommand
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .native:
            try c.encode("native", forKey: .type)
        case .tmux(let sessionName, let startupCommand):
            try c.encode("tmux", forKey: .type)
            try c.encode(sessionName, forKey: .sessionName)
            try c.encode(startupCommand, forKey: .startupCommand)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type_ = try c.decode(String.self, forKey: .type)
        switch type_ {
        case "tmux":
            let session = try c.decode(String.self, forKey: .sessionName)
            let cmd    = try c.decode(String.self, forKey: .startupCommand)
            self = .tmux(sessionName: session, startupCommand: cmd)
        default:
            self = .native
        }
    }
}
```

- [ ] **Step 9.2: WorkspaceModel 新增 mode 字段**

在 `WorkspaceModel` 的现有字段末尾追加：

```swift
var mode: WorkspaceMode = .native
```

在 `WorkspaceModel.init(from:)` 的现有解码末尾追加：

```swift
mode = try container.decodeIfPresent(WorkspaceMode.self, forKey: .mode) ?? .native
```

在 `CodingKeys` enum 追加：

```swift
case mode
```

- [ ] **Step 9.3: 验证编译 + 现有测试通过**

```bash
make check
```

- [ ] **Step 9.4: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceModel.swift
git commit -m "feat(tmux): add WorkspaceMode enum and mode field to WorkspaceModel"
```

---

### Task 10: WorkspaceManager + WorkspaceCreateForm 扩展

**文件:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceManager.swift`
- Modify: `macos/Sources/Features/Workspace/WorkspaceCreateForm.swift`

- [ ] **Step 10.1: WorkspaceManager.create() 增加 mode 参数**

在 `WorkspaceManager.swift` 中修改 `create()` 函数，追加 `mode` 参数：

```swift
// 在现有 create() 前新增 WorkspaceCreateConfig struct
struct WorkspaceCreateConfig {
    var name: String
    var rootDir: String
    var colorHex: String = "#FF6B6B"
    var description: String = ""
    var mode: WorkspaceMode = .native
}

// 修改现有 create() 为接受 config 版本（保留原版本向后兼容）
@discardableResult
func create(config: WorkspaceCreateConfig) -> WorkspaceModel {
    var workspace = WorkspaceModel(name: config.name, rootDir: config.rootDir, colorHex: config.colorHex)
    workspace.description = config.description
    workspace.mode = config.mode
    workspaces.append(workspace)
    save(workspace)
    return workspace
}
```

- [ ] **Step 10.2: saveSnapshot 在 tmux 模式下跳过 tab 保存**

在 `saveSnapshot()` 中，在构建 `WorkspaceSnapshot` 之前追加：

```swift
// tmux 模式：tab 状态由 tmux session 维护，不写入 snapshot
let resolvedTabs: [WorkspaceSnapshot.PersistedTab]?
let resolvedActiveTabIndex: Int?
if case .tmux = workspace.mode {
    resolvedTabs = nil
    resolvedActiveTabIndex = nil
} else {
    resolvedTabs = tabs
    resolvedActiveTabIndex = activeTabIndex
}
```

然后将 `WorkspaceSnapshot` 初始化中的 `tabs:` 和 `activeTabIndex:` 改为 `resolvedTabs` 和 `resolvedActiveTabIndex`。

- [ ] **Step 10.3: WorkspaceCreateForm 新增 mode 选择 UI**

在 `WorkspaceCreateForm.swift` 中：

1. 修改 `onSubmit` 类型：
```swift
let onSubmit: (WorkspaceCreateConfig) -> Void
```

2. 新增 state：
```swift
@State private var selectedMode: WorkspaceMode = .native
@State private var tmuxSessionName: String = ""
@State private var tmuxCommand: String = ""
```

3. 在颜色选择器后追加 mode 选择区（仅创建模式，edit 模式隐藏）：
```swift
if editing == nil {
    Picker("模式", selection: $selectedModeTag) {
        Text("原生").tag("native")
        Text("tmux").tag("tmux")
    }
    .pickerStyle(.segmented)

    if selectedModeTag == "tmux" {
        TextField("Session 名", text: $tmuxSessionName)
            .onChange(of: tmuxSessionName) { name in
                if tmuxCommand.isEmpty || tmuxCommand == "tmux new -As " {
                    tmuxCommand = "tmux new -As \(name)"
                }
            }
        TextField("启动命令", text: $tmuxCommand)
    }
}
```

4. 修改 submit 按钮的 `onSubmit` 调用：
```swift
let mode: WorkspaceMode = selectedModeTag == "tmux"
    ? .tmux(sessionName: tmuxSessionName, startupCommand: tmuxCommand)
    : .native
onSubmit(WorkspaceCreateConfig(
    name: name, rootDir: rootDir,
    colorHex: selectedColor, description: description,
    mode: mode
))
```

- [ ] **Step 10.4: 更新 PolterttyRootView 中 WorkspaceCreateForm 的调用点**

在 `PolterttyRootView.swift` 中找到 `WorkspaceCreateForm(onSubmit:)` 的调用，改为接受 `WorkspaceCreateConfig`：

```swift
WorkspaceCreateForm(
    onSubmit: { config in
        workspaceManager.create(config: config)
        // ... 原有的 window/tab 初始化逻辑
    },
    onCancel: { ... },
    editing: editingWorkspace
)
```

- [ ] **Step 10.5: 验证编译**

```bash
make check
```

- [ ] **Step 10.6: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceManager.swift macos/Sources/Features/Workspace/WorkspaceCreateForm.swift macos/Sources/Features/Workspace/PolterttyRootView.swift
git commit -m "feat(tmux): add WorkspaceCreateConfig, mode field to manager/form, skip tab snapshot in tmux mode"
```

---

### Task 11: PolterttyRootView — 模式切换

**文件:**
- Modify: `macos/Sources/Features/Workspace/PolterttyRootView.swift`

- [ ] **Step 11.1: 新增 TmuxSessionManager 作为可选状态**

在 `PolterttyRootView` 中追加：

```swift
@State private var tmuxSessionManager: TmuxSessionManager? = nil
```

- [ ] **Step 11.2: 在 workspace 打开时根据 mode 初始化**

在处理 workspace 激活/打开的逻辑处（`onAppear` 或 workspace 切换 handler）追加：

```swift
// 打开 workspace 时根据 mode 初始化
func activateWorkspace(_ workspace: WorkspaceModel) {
    switch workspace.mode {
    case .native:
        tmuxSessionManager = nil
        // 现有 native 初始化逻辑不变
    case .tmux(_, let startupCommand):
        let manager = TmuxSessionManager(ghosttyApp: ghostty)
        manager.tabBarViewModel = tabBarViewModel
        try? manager.attach(command: startupCommand)
        tmuxSessionManager = manager
    }
}
```

- [ ] **Step 11.3: 修改 terminalAreaView 增加 tmux 模式分支**

找到 `terminalAreaView` 中渲染终端内容的部分，修改如下：

```swift
// 终端内容：根据 workspace mode 渲染
if let tmux = tmuxSessionManager,
   let windowId = tmux.tabBarViewModel?.activeTmuxWindowId(),
   let layout = tmux.windowLayouts[windowId] {
    // tmux 模式：递归 pane 布局
    TmuxPaneLayoutView(
        layout: layout,
        activePaneId: tmux.activePaneId,
        sessionManager: tmux
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
} else if tabBarViewModel.tabs.count <= 1 {
    terminalView  // 现有 native 单 tab
} else if let activeSurface = tabBarViewModel.activeSurface {
    Ghostty.SurfaceWrapper(surfaceView: activeSurface)  // 现有 native 多 tab
        .environmentObject(ghostty)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
} else {
    terminalView
}
```

- [ ] **Step 11.4: 验证编译**

```bash
make check
```

- [ ] **Step 11.5: 集成构建测试**

```bash
make dev
```
预期：构建成功，可启动 app

- [ ] **Step 11.6: Commit**

```bash
git add macos/Sources/Features/Workspace/PolterttyRootView.swift
git commit -m "feat(tmux): integrate TmuxSessionManager into PolterttyRootView with mode switching"
```

---

## 手动验证清单

完成所有 task 后：

- [ ] 创建 tmux 模式 workspace（session 名 `test`，命令 `tmux new -As test`）
- [ ] 确认 app 启动后连接 tmux session
- [ ] 在 tmux 内 `Ctrl+b c` 新建 window，确认 poltertty tab bar 出现新 tab
- [ ] 点击 tab bar `+` 按钮，确认 tmux 内新建 window
- [ ] 在 tmux 内 `Ctrl+b %` 分屏，确认 poltertty 渲染两个 pane
- [ ] 拖拽分割线，确认 pane 尺寸变化
- [ ] 关闭 workspace window，重新打开，确认自动 attach 到已有 session
- [ ] 创建 native 模式 workspace，确认现有功能不受影响
