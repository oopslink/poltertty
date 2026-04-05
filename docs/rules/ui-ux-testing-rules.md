# UI/UX 测试规范

本文档规定 Poltertty macOS App 的 UI/UX 人工测试流程，涵盖截图、面板操作、区域裁切和验证方法。

---

## 1. 前置条件

### 构建并启动 App

```bash
# 构建（需指定 native 架构，否则 arm64 机器上会报 x86_64 链接错误）
make dev

# 启动
APP_PATH=$(find .build/DerivedData -name "Poltertty.app" -path "*/Debug/Poltertty.app" | head -1)
open "$APP_PATH"

# 等待启动，确认 Ctrl API 端口
sleep 3
lsof -i -n -P | grep ghostty | grep LISTEN
# 示例输出：ghostty 31409 oopslink 15u TCP *:57571 (LISTEN)
```

### 确认 App 处于正确状态

```bash
PORT=57571  # 替换为实际端口

# 健康检查
curl -s http://localhost:$PORT/v1/health

# 获取 instance 信息（含所有 workspace）
curl -s -X POST http://localhost:$PORT/v1/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_instance_info","arguments":{}}}' \
  | python3 -c "import sys,json; print(json.dumps(json.loads(json.load(sys.stdin)['result']['content'][0]['text']), indent=2))"
```

---

## 2. Ctrl API 完整参考

Ctrl API 通过 `POST /v1/mcp` 暴露 MCP tools。以下是所有可用工具。

### 辅助函数

```bash
# 调用工具的通用函数
ctrl() {
  local PORT=$1; local TOOL=$2; local ARGS=${3:-'{}'}
  curl -s -X POST http://localhost:$PORT/v1/mcp \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"$TOOL\",\"arguments\":$ARGS}}" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',{}).get('content',[{}])[0].get('text','ERROR: '+str(d.get('error',''))))"
}

# 获取端口
PORT=$(lsof -i -n -P 2>/dev/null | grep ghostty | grep LISTEN | awk '{print $9}' | sed 's/.*://' | head -1)
```

### Workspace 管理

| Tool | 参数 | 说明 |
|------|------|------|
| `get_instance_info` | — | 返回版本、端口、所有 workspace |
| `open_workspace` | `directory`(必填), `name`(可选) | 打开目录为新 workspace 窗口，返回 `workspaceId` 和第一个 `paneId` |

```bash
# 打开目录
ctrl $PORT open_workspace '{"directory":"/path/to/project","name":"my-project"}'
# → {"workspaceId":"...","paneId":"..."}
```

### Pane 操作

| Tool | 参数 | 说明 |
|------|------|------|
| `list_panes` | `workspaceId`(可选) | 列出所有 pane，含 title、annotation |
| `create_tab` | `workspaceId`(可选) | 创建新 tab，返回 `paneId` |
| `split_pane` | `paneId`, `direction`(left/right/up/down), `command`(可选) | 分裂 pane |
| `focus_pane` | `paneId` | 切换焦点到指定 pane |
| `send_text` | `paneId`(可选), `text` | 向 pane 写入文本（不触发键事件，**无法发送 Enter**） |
| `send_key` | `key`, `paneId`(可选) | 发送真实键盘事件（走完整键处理管线） |
| `set_pane_annotation` | `paneId`, `annotation` | 设置 pane 备注标签 |
| `get_pane_annotation` | `paneId` | 读取 pane 备注标签 |

#### `send_key` 支持的 key 名称

| key | 含义 |
|-----|------|
| `enter` / `return` | 回车（执行命令） |
| `escape` / `esc` | Escape |
| `tab` | Tab |
| `backspace` | 退格 |
| `up` / `down` / `left` / `right` | 方向键 |
| `ctrl+c` | 中断（SIGINT） |
| `ctrl+u` | 清除当前行 |
| `ctrl+d` | EOF |
| `ctrl+l` | 清屏 |
| `ctrl+<任意字母>` | 对应 Ctrl 组合键 |

> **关键经验**：`send_text` 的 `\n` 不触发 shell 执行命令。必须先 `send_text` 输入命令内容，再用 `send_key enter` 提交。

```bash
# 正确方式：启动 claude
PANE="..."
ctrl $PORT send_text "{\"paneId\":\"$PANE\",\"text\":\"claude\"}"
ctrl $PORT send_key  "{\"paneId\":\"$PANE\",\"key\":\"enter\"}"

# 中断运行中的命令
ctrl $PORT send_key "{\"paneId\":\"$PANE\",\"key\":\"ctrl+c\"}"
```

### Agent Dashboard

| Tool | 参数 | 说明 |
|------|------|------|
| `show_agent_dashboard` | — | 打开并置顶 Agent Dashboard 浮动窗口 |

```bash
ctrl $PORT show_agent_dashboard '{}'
```

### Git 工具

| Tool | 参数 | 说明 |
|------|------|------|
| `get_git_status` | `directory`(可选) | 返回分支、staged/unstaged/untracked 文件 |
| `list_worktrees` | `directory`(可选) | 列出 git worktrees |
| `create_worktree` | `directory`, `path`, `branch`(可选), `baseBranch`(可选) | 创建新 worktree |

### Debug 工具（仅 Debug build）

| Tool | 参数 | 说明 |
|------|------|------|
| `click_window` | `x`, `y` | 模拟鼠标点击（窗口坐标，y 从上） |
| `git_panel_state` | `workspaceId`(可选) | 读取 Git 面板内部状态 |
| `test_fullscreen_diff` | `workspaceId`(可选) | 触发全屏 diff 测试截图 |

### 扩充 Ctrl API 的规则

当测试流程需要某个操作但 API 不支持时，**直接扩充**，不要绕路：

1. 在 `CtrlToolHandler.swift` 添加 `case "tool_name": return try await callToolName(arguments:)`
2. 在同文件添加 `// MARK: - tool_name` + 实现函数
3. 在 `CtrlServer.swift` 的 `handleToolsList` 中注册 schema
4. `make dev` 验证构建

常见需要扩充的场景：
- 需要模拟复杂键盘输入 → 扩展 `send_key` 支持更多 key 名称
- 需要读取面板状态 → 添加对应 `get_xxx_state` tool
- 需要触发菜单动作 → 添加对应 tool（避免 AppleScript 菜单路径变化）

---

## 3. 截图

### 规则

**禁止**使用 Ctrl API 的 `capture_screenshot`（已移除）。
原因：该接口使用 `bitmapImageRepForCachingDisplay` 进行 CPU 渲染，无法捕获 Metal/GPU 渲染的终端内容区，结果是白图。

**必须**使用系统 `screencapture` 命令。

### 标准截图流程

```bash
# 1. 将 App 带到前台
osascript -e 'tell application "System Events" to tell process "ghostty" to set frontmost to true'
sleep 0.8   # 等待渲染稳定（0.5s 有时不够，用 0.8s 更安全）

# 2. 截取全屏
screencapture -x /tmp/poltertty_shot.png

# 3. 用 Read 工具查看
```

### 截取指定区域

macOS Retina 屏幕下截图为 2x 分辨率（逻辑坐标 × 2 = 物理像素）。

```bash
# 截取窗口区域（菜单栏高度 34pt，窗口从 y=34 开始）
screencapture -x -R "0,34,1512,876" /tmp/poltertty_window.png
```

使用 `sips` 或 `PIL` 裁切局部区域放大检查：

```python
from PIL import Image
img = Image.open("/tmp/poltertty_shot.png")
print(img.size)  # 查看实际像素尺寸（Retina 下约 3024x1964）

# 裁切 tab bar 区域（根据实际截图坐标调整）
region = img.crop((x1, y1, x2, y2))
region.save("/tmp/crop_region.png")
```

> **坐标参考**（Poltertty 全屏 @2x）：
> - 左侧 workspace 图标栏：x=0~80
> - 面板 tab bar：x=80~760, y=140~230
> - 面板 changes 列表：x=80~700, y=230~1900
> - 底部状态栏：x=0~3024, y=1900~1964
> - Agent Dashboard 浮动窗口：约 x=700~1900, y=100~900（随窗口位置变化）

---

## 4. 打开面板

### 规则

**禁止**使用 AppleScript `keystroke` 发送快捷键。
原因：`keystroke` 被 macOS 系统层拦截，会触发系统快捷键而非 App 快捷键。

**必须**使用 AppleScript `click menu item` 直接触发菜单 Action。

### 各面板打开方法

```applescript
-- 通用模板
tell application "System Events"
    tell process "ghostty"
        set frontmost to true
        delay 0.5
        click menu item "<菜单项名>" of menu "Workspace" of menu bar 1
    end tell
end tell
```

| 面板 | 菜单 | 菜单项名 | 快捷键（参考） |
|------|------|---------|--------------|
| 文件浏览器 | Workspace | `Toggle File Browser` | Cmd+\ |
| Git 面板 | Workspace | `Toggle Git Tab` | Cmd+Shift+G |
| 工作区侧边栏 | Workspace | `Toggle Sidebar` | Cmd+B |
| Agent Dashboard | Agent > Observability | — | 用 Ctrl API `show_agent_dashboard` |
| Agent Monitor | Agent > Observability | — | 用菜单 `Agents In Workspace` |

> **Agent Dashboard** 推荐通过 Ctrl API 打开，避免菜单路径变化：
> ```bash
> ctrl $PORT show_agent_dashboard '{}'
> ```

---

## 5. Agent Dashboard 测试流程

### 标准流程：启动多个 agents 验证 Dashboard

```bash
#!/bin/bash
set -e

# 0. 构建并启动
make dev
APP_PATH=$(find .build/DerivedData -name "Poltertty.app" -path "*/Debug/Poltertty.app" | head -1)
open "$APP_PATH"
sleep 5

# 1. 获取端口
PORT=$(lsof -i -n -P 2>/dev/null | grep ghostty | grep LISTEN | awk '{print $9}' | sed 's/.*://' | head -1)
echo "Port: $PORT"

# 2. 打开项目 workspace
RESULT=$(curl -s -X POST http://localhost:$PORT/v1/mcp \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"open_workspace\",\"arguments\":{\"directory\":\"$(pwd)\",\"name\":\"test\"}}}" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result']['content'][0]['text'])")
WS_ID=$(echo $RESULT | python3 -c "import sys,json; print(json.loads(input())['workspaceId'])")
PANE1=$(echo $RESULT | python3 -c "import sys,json; print(json.loads(input())['paneId'])")
echo "Workspace: $WS_ID, Pane1: $PANE1"

# 3. 在第一个 pane 启动 claude（send_text + send_key enter）
curl -s -X POST http://localhost:$PORT/v1/mcp \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"send_text\",\"arguments\":{\"paneId\":\"$PANE1\",\"text\":\"claude\"}}}" > /dev/null
sleep 0.3
curl -s -X POST http://localhost:$PORT/v1/mcp \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"send_key\",\"arguments\":{\"paneId\":\"$PANE1\",\"key\":\"enter\"}}}" > /dev/null

# 4. 创建更多 tab 并启动 agents
for i in 2 3; do
  PANE=$(curl -s -X POST http://localhost:$PORT/v1/mcp \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":$((i+10)),\"method\":\"tools/call\",\"params\":{\"name\":\"create_tab\",\"arguments\":{\"workspaceId\":\"$WS_ID\"}}}" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.loads(d['result']['content'][0]['text'])['paneId'])" 2>/dev/null)
  sleep 1
  curl -s -X POST http://localhost:$PORT/v1/mcp \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":$((i+20)),\"method\":\"tools/call\",\"params\":{\"name\":\"send_text\",\"arguments\":{\"paneId\":\"$PANE\",\"text\":\"claude\"}}}" > /dev/null
  sleep 0.3
  curl -s -X POST http://localhost:$PORT/v1/mcp \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":$((i+30)),\"method\":\"tools/call\",\"params\":{\"name\":\"send_key\",\"arguments\":{\"paneId\":\"$PANE\",\"key\":\"enter\"}}}" > /dev/null
  echo "Started agent $i in $PANE"
done

# 5. 等待 agents 初始化（约 15s）
echo "Waiting for agents to initialize..."
sleep 15

# 6. 验证 pane 标题（有 claude 时显示 ✳ Claude Code）
curl -s -X POST http://localhost:$PORT/v1/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":99,"method":"tools/call","params":{"name":"list_panes","arguments":{}}}' \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
panes = json.loads(d['result']['content'][0]['text'])
running = [p for p in panes if 'Claude Code' in p.get('title','')]
print(f'Running agents: {len(running)}/{len(panes)}')
for p in panes:
    print(f'  {p[\"id\"][:8]} | {p.get(\"title\",\"\")}')
"

# 7. 打开 Dashboard 截图
curl -s -X POST http://localhost:$PORT/v1/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":100,"method":"tools/call","params":{"name":"show_agent_dashboard","arguments":{}}}' > /dev/null
sleep 0.8
osascript -e 'tell application "System Events" to tell process "ghostty" to set frontmost to true'
sleep 0.8
screencapture -x /tmp/dashboard_test.png

# 8. 裁切 Dashboard 区域
python3 << 'PYEOF'
from PIL import Image
img = Image.open("/tmp/dashboard_test.png")
w, h = img.size
print(f"Screenshot: {w}x{h}")
img.crop((700, 100, 1900, 860)).save("/tmp/dashboard_crop.png")
print("Saved: /tmp/dashboard_crop.png")
PYEOF

echo "✅ 用 Read 工具查看 /tmp/dashboard_crop.png"
```

### Dashboard 验证检查清单

每次 Agent Dashboard UI 改动后确认：

- [ ] **Stats bar**：单行紧凑格式 `N active · N working · N subagents · Nk tokens · $0.00`
- [ ] **多 agent 时**：每个 agent 有独立行，显示状态色点、图标、名称、时长、费用
- [ ] **Workspace 分组头**：显示 workspace 名称 + agent 计数 badge + 色彩 accent bar
- [ ] **状态颜色**：launching=accent色, working=绿, idle=黄, done=secondary, error=红
- [ ] **Context bar**：有 context 使用时显示进度条，颜色随使用率变化（绿→橙→红）
- [ ] **Toolbar**：`Show completed` checkbox + 视图切换 segmented picker
- [ ] **空状态**：无 agent 时显示图标 + 说明 + 快捷键提示
- [ ] **卡片视图**：切换到 cards 模式，每个 agent 正确渲染，无 sparkline 装饰
- [ ] **键盘导航**：↑↓ 切换焦点行（accent 背景 + 描边），Return/Enter 跳转并关闭 Dashboard
- [ ] **点击同步焦点**：点击行时 `focusedSessionId` 同步更新，键盘焦点跟随鼠标点击

---

## 6. SwiftUI 键盘导航实现经验

### macOS 版本兼容

| API | 最低版本 | 说明 |
|-----|---------|------|
| `.onKeyPress` | macOS 14+ | 声明式，绑定到 focusable view |
| `NSEvent.addLocalMonitorForEvents` | macOS 10.6+ | 命令式，全局监听，需手动管理生命周期 |

**结论**：Poltertty 支持 macOS 13+，必须用 `NSEvent.addLocalMonitorForEvents`。

### 标准实现模式

```swift
// 1. 状态
@State private var focusedSessionId: UUID?
@State private var keyMonitor: Any?

// 2. 生命周期绑定（在 body 最外层 VStack/view 上）
.onAppear { installKeyMonitor() }
.onDisappear { removeKeyMonitor() }

// 3. 安装监听（仅当 Dashboard 为 key window 时消费事件）
private func installKeyMonitor() {
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        guard AgentDashboardWindowController.shared.window?.isKeyWindow == true else {
            return event   // 非 key window：透传，不消费
        }
        let sessions = viewModel.activeSessions
        guard !sessions.isEmpty else { return event }
        switch event.keyCode {
        case 125: moveFocus(in: sessions, delta: 1);  return nil  // ↓
        case 126: moveFocus(in: sessions, delta: -1); return nil  // ↑
        case 36, 76: activateFocused(in: sessions);  return nil  // Return / numpad Enter
        default: return event
        }
    }
}

private func removeKeyMonitor() {
    if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
}
```

> **关键**：`return nil` 消费事件（不向后传递），`return event` 透传。
> 只有在 Dashboard 确实是 key window 时才消费方向键，防止影响其他窗口。

### @State 在 NSEvent 闭包中的可行性

SwiftUI `@State` 内部使用引用类型存储（`State<Value>.Box`）。即使 `self`（struct）被复制到闭包中，通过 `@State` property wrapper 的 mutation 仍然操作同一个引用，所以闭包内 `self.focusedSessionId = x` 能正确触发 View 更新，**无需 `DispatchQueue.main.async`**（local monitor 已在主线程回调）。

### 焦点视觉指示

```swift
let isFocused = focusedSessionId == session.id

// 背景：比 hover 略深的 accent 色
.background(
    isFocused
        ? Color(nsColor: .controlAccentColor).opacity(dark ? 0.22 : 0.14)
        : isHovered
            ? Color(nsColor: .controlAccentColor).opacity(dark ? 0.15 : 0.10)
            : Color(nsColor: .controlBackgroundColor).opacity(dark ? 0.35 : 0.5)
)
// 描边环：用 opacity 切换而非 if/else nil，避免布局跳动
.overlay(
    RoundedRectangle(cornerRadius: 5)
        .stroke(Color(.controlAccentColor).opacity(0.55), lineWidth: 1)
        .opacity(isFocused ? 1 : 0)
)
.animation(.easeOut(duration: 0.12), value: isFocused)
```

### 已知坑：Return/Enter 不关闭 Dashboard

**问题**：用 Return/Enter 激活 agent 后，只调用了 `PaneLocator.navigate()`，Dashboard 窗口留在屏幕上。
**期望**：键盘激活应与双击行为一致（跳转 + 关闭）。
**修复**：`activateFocused()` 末尾追加 `AgentDashboardWindowController.shared.close()`。

```swift
// 错误：
PaneLocator.navigate(to: session.surfaceId)

// 正确：
PaneLocator.navigate(to: session.surfaceId)
AgentDashboardWindowController.shared.close()
```

**规则**：任何"激活并切换"的键盘操作，都应与对应的鼠标双击操作行为完全一致。

---

## 7. 通用验证检查清单

每次 UI/UX 改动后，截图并逐条确认：

### 6.1 Tab Bar 选中状态

裁切 tab bar 区域（y=140~230 @2x），检查：

- [ ] 活跃 tab 图标颜色为 `controlAccentColor`（蓝色）
- [ ] 活跃 tab 底部有 2px accent 色指示条
- [ ] 非活跃 tab 图标为 secondary 色（灰）
- [ ] badge 数字清晰可见（橙色圆角，≥10pt）

### 6.2 Stage/Unstage 按钮

裁切 changes 列表区域，检查：

- [ ] 非 hover 状态：`⊕`（stage）和 `↩`（discard）按钮极淡但存在
- [ ] 使用 `arrow.uturn.backward` 图标而非 `xmark.circle`（后者歧义大）
- [ ] hover 状态需手动交互验证（静态截图只能确认非 hover 态）

### 6.3 Worktree Selector

- [ ] 只出现在 tab bar 一处，不在 Files/Git 各自面板内重复出现
- [ ] 多 worktree 时显示下拉菜单；单 worktree 时只显示 branch 名称（无下拉）

### 6.4 底部状态栏

裁切底部区域（y=1900~1964 @2x），检查：

- [ ] 左侧显示 workspace 根目录路径（folder 图标 + 路径文字）
- [ ] 文字 opacity 足够清晰（≥0.8，非 0.6）
- [ ] 右侧显示 branch 名称和变更计数

### 6.5 字体尺寸

- [ ] badge 计数（section header、commit 数、file status）最小 10pt
- [ ] chevron 图标最小 9pt
- [ ] 正文内容（文件名、提交信息）11pt

### 6.6 空状态

切换到非 git 目录触发空状态测试：

- [ ] 文件浏览器空状态：显示图标 + 说明文字 + 操作引导
- [ ] Git 面板非 git 仓库：显示 `Not a git repository` + `git init` 提示 + 路径

---

## 9. 多窗口场景测试

涉及以下任意一类改动时，**必须**进行多窗口验证：

- 新增或修改菜单项/快捷键 action
- 新增 `NotificationCenter.default.post`
- 修改 per-window 视图的 `onReceive`
- 修改 toolbar/titlebar 初始化逻辑

### 9.1 快捷键隔离测试

验证快捷键只作用于当前焦点窗口，不广播到其他窗口。

```bash
PORT=$(lsof -i -n -P 2>/dev/null | grep ghostty | grep LISTEN | awk '{print $9}' | sed 's/.*://' | head -1)

# 1. 打开两个 workspace 窗口
WS1=$(curl -s -X POST http://localhost:$PORT/v1/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"open_workspace","arguments":{"directory":"/tmp","name":"test-ws-1"}}}' \
  | python3 -c "import sys,json; print(json.loads(json.load(sys.stdin)['result']['content'][0]['text'])['workspaceId'])")

WS2=$(curl -s -X POST http://localhost:$PORT/v1/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"open_workspace","arguments":{"directory":"/tmp","name":"test-ws-2"}}}' \
  | python3 -c "import sys,json; print(json.loads(json.load(sys.stdin)['result']['content'][0]['text'])['workspaceId'])")

echo "WS1: $WS1"
echo "WS2: $WS2"

# 2. 截图：记录两个窗口的初始状态
sleep 1
osascript -e 'tell application "System Events" to tell process "ghostty" to set frontmost to true'
sleep 0.8
screencapture -x /tmp/multi_window_before.png

# 3. 通过菜单触发侧边栏切换（焦点在 WS2 窗口）
osascript << 'OSEOF'
tell application "System Events"
    tell process "ghostty"
        set frontmost to true
        delay 0.5
        click menu item "Toggle Sidebar" of menu "Workspace" of menu bar 1
    end tell
end tell
OSEOF

sleep 0.8
screencapture -x /tmp/multi_window_after.png

echo "✅ 对比 before/after 截图：只有焦点窗口的侧边栏发生变化"
echo "   用 Read 工具查看 /tmp/multi_window_before.png 和 /tmp/multi_window_after.png"
```

**验证要点**：
- [ ] 触发快捷键前，记录两个窗口侧边栏的可见状态
- [ ] 触发后，只有当前焦点窗口状态改变，另一个窗口不变
- [ ] 切换焦点到另一窗口后再次触发，验证方向正确

### 9.2 新 Workspace 窗口 Tab 初始位置

每次修改 toolbar/titlebar 初始化逻辑后验证。

```bash
PORT=$(lsof -i -n -P 2>/dev/null | grep ghostty | grep LISTEN | awk '{print $9}' | sed 's/.*://' | head -1)

# 打开新 workspace 窗口
curl -s -X POST http://localhost:$PORT/v1/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"open_workspace","arguments":{"directory":"/tmp","name":"tab-pos-test"}}}' > /dev/null

# 立即截图（不等待，捕获第一帧状态）
sleep 0.3
osascript -e 'tell application "System Events" to tell process "ghostty" to set frontmost to true'
sleep 0.3
screencapture -x /tmp/tab_position_test.png

python3 << 'PYEOF'
from PIL import Image
img = Image.open("/tmp/tab_position_test.png")
w, h = img.size
# 裁切 titlebar 区域（Retina 2x，titlebar 约在 y=200~270）
img.crop((0, 200, w, 280)).save("/tmp/tab_position_titlebar.png")
print(f"截图尺寸: {w}x{h}")
print("Saved: /tmp/tab_position_titlebar.png")
PYEOF

echo "✅ 检查 tab 是否在 titlebar 右侧（非紧贴 workspace 名称）"
```

**验证要点**：
- [ ] Tab 出现在 titlebar 右侧（workspace 名与 tab 之间有明显间距）
- [ ] 重复打开 5 次，每次 tab 位置一致，无概率性偏左

## 10. 常见问题

| 问题 | 原因 | 解决方法 |
|------|------|---------|
| 截图全白 | 使用了 CPU 渲染截图（旧 `capture_screenshot`） | 改用 `screencapture` |
| 快捷键触发了系统功能 | `keystroke` 被系统拦截 | 改用 `click menu item` |
| App 未在前台，截图错误 | `set frontmost to true` 未生效 | 增加 `delay 0.8` 等待渲染 |
| `make dev` 架构报错 | zig build 默认 universal，arm64 机器链接 x86_64 | `scripts/build.sh` 已修复为 `-Dxcframework-target=native` |
| Ctrl API 端口不固定 | 每次启动随机分配 | 每次通过 `lsof -i -n -P \| grep ghostty \| grep LISTEN` 获取 |
| `send_text` 发 `\n` 不执行命令 | `ghostty_surface_text` 不触发键事件 | 改用 `send_text` 输入内容 + `send_key enter` 提交 |
| `send_text` 发 `\r` 也不执行 | 同上，`ghostty_surface_text` 绕过键处理管线 | 同上 |
| App 启动进引导页，workspace 为空 | 首次启动无历史 workspace | 用 `open_workspace` API 手动打开目录 |
| 键盘 Return 激活后 Dashboard 不关闭 | `activateFocused` 只调用了 navigate | 追加 `AgentDashboardWindowController.shared.close()` |

---

## 11. 侧边栏 Workspace 元数据测试

### 设计稿参考

`.superpowers/brainstorm/42210-1775360708/sidebar-metadata-design.png`

### 11.1 测试数据准备

```bash
# 启动一个本地服务（模拟监听端口）
python3 -m http.server 9731 &
MOCK_SERVER_PID=$!

# 启动 App
make dev
APP_PATH=$(find .build/DerivedData -name "Poltertty.app" -path "*/Debug/Poltertty.app" | head -1)
open "$APP_PATH"
sleep 3

PORT=$(lsof -i -n -P 2>/dev/null | grep ghostty | grep LISTEN | awk '{print $9}' | sed 's/.*://' | head -1)
echo "Ctrl API Port: $PORT"
```

### 11.2 展开状态截图与检查（方案 A）

```bash
# 确保侧边栏展开
osascript << 'OSEOF'
tell application "System Events"
    tell process "ghostty"
        set frontmost to true
        delay 0.5
        click menu item "Toggle Sidebar" of menu "Workspace" of menu bar 1
    end tell
end tell
OSEOF
sleep 0.8

screencapture -x /tmp/sidebar_expanded_metadata.png

# 裁切侧边栏区域（展开状态约 x=0~220，全高）
python3 << 'PYEOF'
from PIL import Image
img = Image.open("/tmp/sidebar_expanded_metadata.png")
w, h = img.size
print(f"Screenshot: {w}x{h}")
# 侧边栏区域（Retina 2x，展开宽度约 360px）
sidebar = img.crop((0, 60, 380, h - 60))
sidebar.save("/tmp/sidebar_expanded_crop.png")
print("Saved: /tmp/sidebar_expanded_crop.png")
PYEOF
```

**展开状态（方案 A）检查清单：**

- [ ] 端口徽标格式为 `:PORT`（如 `:9731`），monospaced 字体
- [ ] 端口徽标颜色：蓝色系底色（rgba 约 23,51,95,0.18），蓝色文字
- [ ] 端口徽标可点击，hover 时有 tooltip `在 Browser Panel 打开 http://localhost:PORT`
- [ ] 超过 3 个端口时显示前 3 个 + `+N` 文字
- [ ] PR Open 徽标：绿色系，格式 `#N Open`
- [ ] PR Draft 徽标：灰色系，格式 `#N Draft`
- [ ] PR Merged 徽标：紫色系，格式 `#N Merged`
- [ ] 无 PR 时 PR 位置完全留空（不显示空占位）
- [ ] Agent Working 徽标：黄色脉冲点 + `Working`，点有闪烁动画
- [ ] Agent Idle 徽标：灰色静态点 + `Idle`
- [ ] 无 Agent 时不显示 Agent 徽标
- [ ] **无任何元数据时**：徽标行完全不渲染，workspace 行高与无数据时一致（不留空行）
- [ ] 徽标行在 rootDir 路径行正下方，间距与设计稿一致（约 3pt）

### 11.3 折叠状态截图与检查（方案 X）

```bash
# 切换到折叠状态
osascript << 'OSEOF'
tell application "System Events"
    tell process "ghostty"
        set frontmost to true
        delay 0.5
        click menu item "Toggle Sidebar" of menu "Workspace" of menu bar 1
    end tell
end tell
OSEOF
sleep 0.5

# 再次切换：让侧边栏折叠（若当前为展开则先收起，再展开折叠态）
# 注意：折叠按钮在侧边栏内，通过 Ctrl API 截图验证
screencapture -x /tmp/sidebar_collapsed_metadata.png

python3 << 'PYEOF'
from PIL import Image
img = Image.open("/tmp/sidebar_collapsed_metadata.png")
w, h = img.size
print(f"Screenshot: {w}x{h}")
# 折叠状态侧边栏约 x=0~100（Retina 2x 约 104px）
sidebar = img.crop((0, 60, 110, h - 60))
sidebar.save("/tmp/sidebar_collapsed_crop.png")
print("Saved: /tmp/sidebar_collapsed_crop.png")
PYEOF
```

**折叠状态（方案 X）检查清单：**

- [ ] 图标下方有三点行，高度约 8pt，三点水平间距约 4pt
- [ ] 左点（端口）：蓝色（有端口）/ 透明（无端口），hover tooltip 显示端口列表如 `:3000 :8080`
- [ ] 中点（Agent）：黄色脉冲（Working）/ 灰色（Idle）/ 透明（None）
- [ ] 右点（PR）：绿色（Open）/ 灰色（Draft）/ 紫色（Merged）/ 透明（无 PR）
- [ ] 已有的红色未读通知角标（右上角）不受影响，不与三点行重叠
- [ ] 无任何元数据时三点行所有点透明（点行区域高度仍占位，图标不跳动）

### 11.4 交互测试：端口点击打开 Browser Panel

```bash
# 用 click_window 模拟点击端口徽标（需先通过截图确认坐标）
PORT_CTRL=$(lsof -i -n -P 2>/dev/null | grep ghostty | grep LISTEN | awk '{print $9}' | sed 's/.*://' | head -1)

# 截图获取端口徽标位置（展开侧边栏）
osascript -e 'tell application "System Events" to tell process "ghostty" to set frontmost to true'
sleep 0.8
screencapture -x /tmp/before_port_click.png

# 点击端口徽标（坐标需根据实际截图调整，端口徽标约在 sidebar 第一个 workspace 行的 y ≈ 200）
curl -s -X POST http://localhost:$PORT_CTRL/v1/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"click_window","arguments":{"x":65,"y":200}}}' > /dev/null
sleep 0.8
screencapture -x /tmp/after_port_click.png
```

**Browser Panel 打开检查：**

- [ ] 点击端口徽标后，Browser Panel 自动出现（`browserPanelVisible` 变为 true）
- [ ] Browser Panel 中打开了新 tab，URL 为 `http://localhost:PORT`
- [ ] 若 Browser Panel 已打开，新 tab 追加到现有 tab 列表

### 11.5 生成测试报告

测试完成后将截图收集到 `docs/tests/YYYY-MM-DD/` 并生成 Markdown 报告：

```bash
DATE=$(date +%Y-%m-%d)
mkdir -p docs/tests/$DATE

cp /tmp/sidebar_expanded_crop.png   docs/tests/$DATE/sidebar-expanded.png
cp /tmp/sidebar_collapsed_crop.png  docs/tests/$DATE/sidebar-collapsed.png
cp /tmp/before_port_click.png       docs/tests/$DATE/before-port-click.png
cp /tmp/after_port_click.png        docs/tests/$DATE/after-port-click.png
```

报告文件路径：`docs/tests/YYYY-MM-DD/sidebar-metadata-report.md`

报告格式：

```markdown
# 侧边栏元数据 UI/UX 测试报告

**日期**：YYYY-MM-DD  
**构建**：Debug / `make dev`  
**设计稿**：`.superpowers/brainstorm/42210-1775360708/sidebar-metadata-design.png`

## 测试环境

- macOS 版本：
- 分辨率：（screencapture 输出尺寸）
- 测试数据：python3 -m http.server 9731（端口 :9731 模拟）

## 展开状态（方案 A）

| 检查项 | 结果 | 备注 |
|--------|------|------|
| 端口徽标格式 `:PORT` | ✅/❌ | |
| 端口徽标色彩（蓝色系） | ✅/❌ | |
| PR Open 绿色 `#N Open` | ✅/❌ | |
| PR Draft 灰色 `#N Draft` | ✅/❌ | |
| 无元数据时徽标行不渲染 | ✅/❌ | |
| Agent Working 脉冲动画 | ✅/❌ | |
| 行高与设计稿一致 | ✅/❌ | |

截图：`sidebar-expanded.png`  
设计稿对照：见 `.superpowers/brainstorm/42210-1775360708/sidebar-metadata-design.png` 方案 A 区域

## 折叠状态（方案 X）

| 检查项 | 结果 | 备注 |
|--------|------|------|
| 三点行高度 8pt / 间距 4pt | ✅/❌ | |
| 左点蓝色（有端口）/ 透明（无端口） | ✅/❌ | |
| 中点黄色脉冲（Working） | ✅/❌ | |
| 右点绿色（PR Open） | ✅/❌ | |
| 未读角标不受影响 | ✅/❌ | |

截图：`sidebar-collapsed.png`

## 交互：端口点击

| 检查项 | 结果 | 备注 |
|--------|------|------|
| 点击端口 → Browser Panel 打开 | ✅/❌ | |
| 新 tab URL = http://localhost:PORT | ✅/❌ | |

截图：`before-port-click.png` / `after-port-click.png`

## 与设计稿差异

（列出与设计稿不一致的地方，每条说明是否需要修正）

## 结论

**通过 / 需修正**
```

---

## 8. 旧测试脚本示例（Git 面板）

```bash
#!/bin/bash
PORT=57571   # 从 lsof 获取实际端口

# 1. 打开 Git 面板
osascript << 'OSEOF'
tell application "System Events"
    tell process "ghostty"
        set frontmost to true
        delay 0.5
        click menu item "Toggle Git Tab" of menu "Workspace" of menu bar 1
    end tell
end tell
OSEOF

sleep 1

# 2. 截图
screencapture -x /tmp/test_git_panel.png

# 3. 裁切各区域
python3 << 'PYEOF'
from PIL import Image
img = Image.open("/tmp/test_git_panel.png")
w, h = img.size
print(f"Screenshot size: {w}x{h}")

img.crop((80, 140, 760, 230)).save("/tmp/check_tabbar.png")       # tab bar
img.crop((80, 230, 700, h-80)).save("/tmp/check_changes.png")     # changes list
img.crop((0, h-80, w, h)).save("/tmp/check_statusbar.png")        # status bar
print("Crops saved.")
PYEOF

echo "✅ 截图完成，用 Read 工具查看 /tmp/check_*.png"
```

