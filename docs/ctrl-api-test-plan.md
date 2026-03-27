# Poltertty Ctrl API 功能测试计划

基于 Ctrl API（MCP HTTP Server）对 Poltertty 全部功能性特性进行系统测试，并附 UX 体验分析。

---

## 测试前提

### 环境准备

```bash
# 获取当前 CtrlServer 端口
PORT=$(echo $POLTERTTY_CTRL_PORT)

# 基础健康检查
curl -s http://localhost:$PORT/v1/health
# 期望响应：{}

# 获取实例信息（所有后续测试的起点）
curl -s -X POST http://localhost:$PORT/v1/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_instance_info","arguments":{}},"id":1}'
```

期望响应包含：`instanceId`、`version`、`port`、`workspaces[]`

### 辅助脚本

```bash
# 封装 MCP 工具调用
mcp() {
  local tool=$1
  local args=${2:-'{}'}
  curl -s -X POST http://localhost:$PORT/v1/mcp \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"$tool\",\"arguments\":$args},\"id\":1}" \
    | python3 -m json.tool
}

# 截图并打开预览
screenshot() {
  local pane_id=$1
  local result=$(mcp capture_screenshot "{\"target\":\"pane\",\"paneId\":\"$pane_id\"}")
  local path=$(echo $result | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['content'][0]['text'])" | grep -o '"path":"[^"]*"' | cut -d'"' -f4)
  open "$path"
}
```

---

## T01 — Ctrl API 自身

### T01-1 健康检查

```bash
curl -s http://localhost:$PORT/v1/health
# 期望：{} 且 HTTP 200
```

### T01-2 工具列表完整性

```bash
curl -s -X POST http://localhost:$PORT/v1/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":1}'
```

期望包含 9 个生产工具：`get_instance_info`、`create_tab`、`list_panes`、`focus_pane`、`send_text`、`split_pane`、`set_pane_annotation`、`get_pane_annotation`、`capture_screenshot`

### T01-3 SSE 事件流

```bash
# 订阅 SSE（保持连接）
curl -s -N -H "Accept: text/event-stream" http://localhost:$PORT/v1/mcp &
SSE_PID=$!

# 触发 pane 创建操作（见 T02-1），观察是否收到 notifications/pane_created 事件

# 30 秒内应收到心跳：": ping"
sleep 31

kill $SSE_PID
```

### T01-4 Ctrl API Monitor 面板

- 手动触发：`Opt+Cmd+C` 打开 Monitor 面板
- 执行几次 MCP 工具调用
- 验证：面板显示调用记录、时间戳、工具名、JSON 高亮、状态码、耗时

### T01-5 错误处理

```bash
# 未知工具
mcp unknown_tool '{}'
# 期望：error.code = -32601 (Method not found) 或工具不存在提示

# 缺少必需参数
mcp focus_pane '{}'
# 期望：error.code = -32602 (Invalid params)

# 超大请求（>1MB）
python3 -c "print('x'*1048577)" | curl -s -X POST http://localhost:$PORT/v1/mcp \
  -H "Content-Type: application/json" -d @-
# 期望：HTTP 413
```

**UX 分析：**
> ✅ JSON 语法高亮可读性好，拖拽调整高度符合习惯。
> ⚠️ Monitor 面板无持久化，重启后历史记录清空，调试中途重启会丢失上下文。
> ⚠️ `Opt+Cmd+C` 快捷键不够直觉，建议考虑更语义化的绑定（如 `Opt+Cmd+L` for Logs）。

---

## T02 — Split Pane 管理

### T02-1 创建 Tab

```bash
# 获取 workspaceId
WS_ID=$(mcp get_instance_info | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result']['content'][0]['text'])" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d['workspaces'][0]['id'])")

# 创建新 Tab
mcp create_tab "{\"workspaceId\":\"$WS_ID\"}"
# 期望：{"paneId": "new-uuid"}
# SSE 应收到：notifications/tab_created + notifications/pane_created
```

### T02-2 列出所有 Pane

```bash
mcp list_panes "{\"workspaceId\":\"$WS_ID\"}"
# 期望：数组，每项含 id/tabId/workspaceId/isActive/title/annotation
```

### T02-3 分割 Pane

```bash
# 取得一个 paneId
PANE_ID=$(mcp list_panes '{}' | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result']['content'][0]['text'])" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d[0]['id'])")

# 向右分割
mcp split_pane "{\"paneId\":\"$PANE_ID\",\"direction\":\"right\"}"
# 期望：{"newPaneId": "uuid"}
# SSE 应收到：notifications/pane_created
```

### T02-4 聚焦 Pane

```bash
# 聚焦新分割的 pane
mcp focus_pane "{\"paneId\":\"$NEW_PANE_ID\"}"
# 期望：{"ok": true}
# SSE 应收到：notifications/pane_focused
# 视觉上：状态栏高亮切换到对应 pane
```

### T02-5 发送文本

```bash
# 向指定 pane 写入命令
mcp send_text "{\"text\":\"echo 'hello from ctrl-api'\n\",\"paneId\":\"$PANE_ID\"}"
# 期望：{"ok": true}，pane 执行该命令并输出
```

### T02-6 快速切换 Pane（Fast Split Focus）

- 前置：创建多个分屏（至少 3 个）
- 手动测试：双击 `Cmd` 触发选择器，观察 Badge 闪烁动画
- 按 `2` 跳转到第二个 pane

```bash
# 通过 API 验证焦点是否切换
mcp list_panes '{}' | grep isActive
```

### T02-7 截图验证布局

```bash
mcp capture_screenshot "{\"target\":\"window\"}"
# 打开截图验证分屏布局是否符合预期
```

**UX 分析：**
> ✅ `split_pane` API 参数简洁，方向语义清晰。
> ✅ Badge 闪烁动画增强了 Fast Focus 的可见性反馈。
> ⚠️ `split_pane` 缺少指定初始命令的参数（`command`），每次分割后需再调 `send_text`，两步操作可合一。
> ⚠️ `list_panes` 无法获知 pane 的物理位置（上/下/左/右），Agent 难以推理布局。建议增加 `position` 或 `row/col` 字段。

---

## T03 — Pane 注释

### T03-1 设置注释

```bash
mcp set_pane_annotation "{\"paneId\":\"$PANE_ID\",\"annotation\":\"frontend dev server\"}"
# 期望：{"ok": true}
# 视觉上：pane 上方出现浮动注释卡片
```

### T03-2 读取注释

```bash
mcp get_pane_annotation "{\"paneId\":\"$PANE_ID\"}"
# 期望：{"annotation": "frontend dev server"}
```

### T03-3 清除注释

```bash
mcp set_pane_annotation "{\"paneId\":\"$PANE_ID\",\"annotation\":\"\"}"
mcp get_pane_annotation "{\"paneId\":\"$PANE_ID\"}"
# 期望：{"annotation": null}
```

### T03-4 list_panes 反映注释

```bash
mcp list_panes '{}' | grep annotation
# 期望：已注释的 pane 在 annotation 字段显示内容
```

### T03-5 截图验证卡片渲染

```bash
mcp set_pane_annotation "{\"paneId\":\"$PANE_ID\",\"annotation\":\"test annotation visibility\"}"
mcp capture_screenshot "{\"target\":\"pane\",\"paneId\":\"$PANE_ID\"}"
# 打开截图，验证浮动卡片是否覆盖在终端内容上方且可读
```

**UX 分析：**
> ✅ 注释卡片非常适合多 pane 场景下快速辨认用途。
> ✅ API 层面读写对称，易于 Agent 使用。
> ⚠️ 浮动卡片覆盖终端内容，若 pane 较小卡片面积占比高，可能干扰内容阅读。建议支持卡片折叠或透明度渐变。
> ⚠️ 注释无持久化，Poltertty 重启后丢失。若 Agent 重启后需要恢复上下文，需要重新设置。

---

## T04 — Agent 系统

### T04-1 基础 Hook 流程

```bash
# 确认 shell integration 已加载（新 pane 内）
echo $POLTERTTY_SURFACE_ID    # 应非空
echo $POLTERTTY_CTRL_PORT     # 应非空
echo $POLTERTTY_WORKSPACE_ID  # 应非空

# 验证 wrapper 存在
ls ~/.poltertty/bin/poltertty-cli
ls ~/.poltertty/bin/poltertty-agent-wrapper

# 验证 PATH 优先级
which claude    # 应指向 ~/.poltertty/bin/poltertty-agent-wrapper 软链接
```

### T04-2 会话初始化

```bash
# 手动触发 prepare-session（模拟 wrapper）
~/.poltertty/bin/poltertty-cli prepare-session \
  --session-id "test-pts-001" \
  --agent "claude" \
  --agent-session-id "test-cc-001" \
  --cwd "$(pwd)" \
  --workspace-id "$POLTERTTY_WORKSPACE_ID" \
  --surface-id "$POLTERTTY_SURFACE_ID" \
  --port "$POLTERTTY_CTRL_PORT" \
  --pid "$$"

# 期望：输出 session 目录路径
# 验证：目录存在，meta.json 和 settings.json 均创建
ls ~/.poltertty/sessions/test-pts-001/
cat ~/.poltertty/sessions/test-pts-001/meta.json
cat ~/.poltertty/sessions/test-pts-001/settings.json
# settings.json 应包含 hooks + mcpServers.poltertty
```

### T04-3 Hook 事件投递

```bash
# 读取 token
TOKEN=$(cat ~/.poltertty/sessions/test-pts-001/meta.json | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

# 发送模拟 SessionStart hook
curl -s -X POST http://localhost:$PORT/v1/hooks/events \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "hook_event_name": "SessionStart",
    "session_id": "test-cc-001",
    "cwd": "/tmp",
    "agent_type": "claude-code"
  }'
# 期望：HTTP 202

# 发送 PreToolUse
curl -s -X POST http://localhost:$PORT/v1/hooks/events \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "hook_event_name": "PreToolUse",
    "session_id": "test-cc-001",
    "tool_name": "Bash",
    "tool_use_id": "tu-001",
    "cwd": "/tmp"
  }'
# 期望：HTTP 202，Agent Monitor 面板状态更新为 working

# 发送 Notification（idle_prompt）
curl -s -X POST http://localhost:$PORT/v1/hooks/events \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "hook_event_name": "Notification",
    "session_id": "test-cc-001",
    "notification_type": "idle_prompt",
    "cwd": "/tmp"
  }'
# 期望：HTTP 202，系统通知弹出（若当前 pane 不是目标 pane）

# 发送 SessionEnd
curl -s -X POST http://localhost:$PORT/v1/hooks/events \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "hook_event_name": "SessionEnd",
    "session_id": "test-cc-001",
    "cwd": "/tmp"
  }'
# 期望：HTTP 202，session 移到 HISTORY 区
```

### T04-4 Agent Monitor 面板状态验证

- 打开 Agent Monitor（`Cmd+Opt+M`）
- 执行 T04-3 中各 hook，逐步观察：
  - SessionStart → session 出现在列表
  - PreToolUse → 状态变为 working，工具名气泡显示
  - idle_prompt → 状态变为 idle，系统通知触发
  - SessionEnd → session 移至 HISTORY

### T04-5 Subagent 追踪

```bash
# 模拟 SubagentStart（通过 PreToolUse + SubagentStart 组合）
curl -s -X POST http://localhost:$PORT/v1/hooks/events \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "hook_event_name": "SubagentStart",
    "session_id": "test-cc-001",
    "tool_use_id": "tu-002",
    "agent_id": "sub-agent-001",
    "agent_name": "subagent",
    "cwd": "/tmp"
  }'
# 期望：Agent Monitor Drawer 中出现 subagent 节点，图形视图更新
```

### T04-6 真实 Claude Code 启动测试

```bash
# 打开新 pane，运行 claude 验证全链路
mcp create_tab "{\"workspaceId\":\"$WS_ID\"}"
# 获取新 pane ID，发送 claude 命令
mcp send_text "{\"text\":\"claude --help\n\",\"paneId\":\"$NEW_PANE_ID\"}"
# 验证：wrapper 介入但 fallback 正常（--help 无需 session）

# 真正启动 agent（需要在项目目录）
mcp send_text "{\"text\":\"cd /path/to/your/project && claude\n\",\"paneId\":\"$NEW_PANE_ID\"}"
# 验证 Agent Monitor 收到 SessionStart 事件
```

**UX 分析：**
> ✅ 四层 settings 合并对用户完全透明，无需手动配置 hooks 或 MCP。
> ✅ Hook 注入 + wrapper 的无侵入设计不污染用户的全局 claude settings。
> ⚠️ wrapper 的 fallback 条件复杂（5 个条件），首次排查问题时不直观。建议 Monitor 面板增加"Hook 状态诊断"入口，显示当前 pane 的注入状态。
> ⚠️ `idle_prompt` 通知在 pane 可见时被抑制，但当 Poltertty 不在前台时仍无法感知 Agent 等待状态。

---

## T05 — Agent Dashboard

### T05-1 打开 Dashboard

- `Cmd+Opt+D` 打开 Agent Dashboard
- 验证：显示所有 workspace 的 session（含 HISTORY）

### T05-2 跨 workspace 汇总

```bash
# 创建第二个 workspace 并在其中触发一个 session（参考 T04-3）
# 返回 Dashboard 验证两个 workspace 的 session 均显示
```

### T05-3 Table / Card 模式切换

- 手动切换 Table 和 Card 视图
- 验证两种视图数据一致

### T05-4 跳转至 Pane（脉冲高亮）

```bash
# 确保有一个活跃 session（T04-3 后）
# 在 Dashboard 中双击对应行
# 期望：
#   1. Dashboard 关闭
#   2. 对应 workspace 和 pane 获得焦点
#   3. Pane 边框出现脉冲高亮动画
```

```bash
# 通过 API 验证焦点确实切换
mcp list_panes '{}' | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); [print(p['id'], p['isActive']) for p in d]"
```

**UX 分析：**
> ✅ 脉冲高亮动画是定位 pane 的极好设计，跨 workspace 场景尤其有用。
> ⚠️ Dashboard 失去焦点后自动关闭，偶尔会在切换应用时误关，建议改为 Esc 显式关闭，或提供"固定窗口"选项。
> ⚠️ Table 视图缺少列排序功能，session 多时难以按状态/时间筛选。

---

## T06 — Workspace 管理

### T06-1 获取 Workspace 信息

```bash
mcp get_instance_info
# 验证 workspaces 数组中有 id 和 isActive 字段
# 验证当前活跃 workspace 的 isActive = true
```

### T06-2 多 Workspace 切换

```bash
# 获取所有 workspace ID
mcp get_instance_info | python3 -c "
import sys, json
d = json.load(sys.stdin)
text = d['result']['content'][0]['text']
info = json.loads(text)
for ws in info['workspaces']:
    print(ws['id'], 'active=' + str(ws['isActive']))
"
```

- 手动切换 workspace（`Cmd+K` Quick Switcher）
- 再次调用 `get_instance_info`，验证 `isActive` 更新

### T06-3 Workspace 分组

- 手动：拖拽 workspace 到分组
- 验证：折叠/展开分组、组名在 Quick Switcher 中可搜索

### T06-4 截图验证 Sidebar 布局

```bash
mcp capture_screenshot '{"target":"window"}'
# 验证：worktree 左侧 accent 色边框、分组层级清晰
```

**UX 分析：**
> ✅ Workspace 概念对多项目开发者是核心价值，持久化设计合理。
> ⚠️ `get_instance_info` 返回的 workspace 列表仅含 `id` 和 `isActive`，缺少 `name`、`rootPath` 等元数据，Agent 无法通过 API 识别 workspace 用途，需配合 pane annotation 才能建立上下文。建议在 workspace 信息中增加 `name` 和 `rootDirectory` 字段。

---

## T07 — Git Worktree 管理

### T07-1 Worktree 侧边栏显示

```bash
# 在一个 git 仓库目录中的 pane 内添加 worktree
mcp send_text "{\"text\":\"git worktree add ../.worktrees/test-branch -b test-branch\n\",\"paneId\":\"$PANE_ID\"}"
# 期望：侧边栏自动出现新 worktree 条目（实时刷新）
```

### T07-2 文件浏览器跟随 Worktree

- 点击侧边栏 worktree 条目
- 验证：文件浏览器根目录切换到对应 worktree 路径

### T07-3 缺失 Worktree 标记

```bash
# 从外部删除 worktree
mcp send_text "{\"text\":\"rm -rf ../.worktrees/test-branch\n\",\"paneId\":\"$PANE_ID\"}"
# 期望：侧边栏条目变为"缺失"状态标记（不直接消失）
```

### T07-4 截图验证 Worktree UI

```bash
mcp capture_screenshot '{"target":"window"}'
# 验证：worktree 区域左侧 accent 色边框可见
```

**UX 分析：**
> ✅ Worktree 是 AI agent 并行开发的关键基础设施，侧边栏集成大幅降低使用门槛。
> ⚠️ Worktree 操作（创建/删除）目前无 API 接口，Agent 只能通过 `send_text` 调用 git 命令，间接验证。建议增加 `list_worktrees`、`create_worktree` MCP 工具。
> ⚠️ 缺失 worktree 的标记虽直观，但没有提供"清理"快捷操作，需要用户手动执行 `git worktree prune`。

---

## T08 — Git Panel

### T08-1 Git 状态验证

```bash
# 在 git 仓库 pane 内修改一个文件
mcp send_text "{\"text\":\"echo 'test' >> /tmp/test.txt && git -C \$(pwd) add /tmp/test.txt\n\",\"paneId\":\"$PANE_ID\"}"

# 切换到 git pane（g 快捷键），截图验证 staged 文件出现
mcp capture_screenshot "{\"target\":\"pane\",\"paneId\":\"$PANE_ID\"}"
```

### T08-2 Diff 全屏验证（截图）

```bash
# 打开 Git Panel，点击一个文件进入 Diff 视图，再点击全屏按钮
# 通过截图验证：全屏时 commit 侧边栏仍然可见
mcp capture_screenshot '{"target":"window"}'
```

### T08-3 状态栏 Git 状态更新

```bash
# 在 git 仓库目录内执行 git 操作
mcp send_text "{\"text\":\"git -C \$(pwd) status\n\",\"paneId\":\"$PANE_ID\"}"
# 截图验证状态栏显示正确的分支名和变更数
mcp capture_screenshot "{\"target\":\"pane\",\"paneId\":\"$PANE_ID\"}"
```

### T08-4 CWD 追踪（前台进程）

```bash
# 在 pane 内 cd 到不同 git 仓库
mcp send_text "{\"text\":\"cd ~/another-git-repo\n\",\"paneId\":\"$PANE_ID\"}"
# 等待约 2s（前台 CWD 轮询间隔）
sleep 3
mcp capture_screenshot "{\"target\":\"pane\",\"paneId\":\"$PANE_ID\"}"
# 验证状态栏切换到新目录的 git 状态
```

**UX 分析：**
> ✅ stage/unstage/discard 内联在文件浏览器中，比切换到独立 Git 客户端效率高很多。
> ✅ Diff 全屏保留侧边栏的设计决策正确，避免在大量 commit 中"迷路"。
> ⚠️ Git Panel 目前无法通过 API 查询状态（仅有 DEBUG 工具 `git_panel_state`），Agent 无法验证 stage 操作是否成功，需依赖 `send_text` 调用 git 命令间接确认。
> ⚠️ `f/g` 快捷键切换文件浏览器和 Git Panel 不够直觉，新用户难以发现。建议在面板 header 区展示快捷键提示。

---

## T09 — 文件浏览器

### T09-1 基础浏览

```bash
# 确认 pane 工作目录
mcp send_text "{\"text\":\"pwd\n\",\"paneId\":\"$PANE_ID\"}"
mcp capture_screenshot "{\"target\":\"pane\",\"paneId\":\"$PANE_ID\"}"
# 验证：文件浏览器显示对应目录树
```

### T09-2 文件路径注入

- 手动：在文件浏览器中选中文件，按 `Space`
- 验证：文件路径被注入到当前活跃 terminal

### T09-3 过滤 Chips 验证

```bash
# 确保有 unstaged 文件
mcp send_text "{\"text\":\"echo 'modified' >> some-file.txt\n\",\"paneId\":\"$PANE_ID\"}"
# 点击"仅显示未提交文件" Chip
mcp capture_screenshot "{\"target\":\"pane\",\"paneId\":\"$PANE_ID\"}"
# 验证：仅显示有 git 变更的文件
```

### T09-4 多选操作

- `Cmd+A` 全选，截图验证高亮
- `Shift+Click` 区间选择
- 右键验证批量操作菜单

**UX 分析：**
> ✅ `Space` 注入路径的设计极度高效，是 terminal-native 工作流的典型体验。
> ⚠️ 文件浏览器无对应 API（无 `list_files`、`open_file` 等工具），Agent 只能通过 `send_text` 调用 ls/cat，无法直接与文件树 UI 交互。
> ⚠️ 批量移动面板（Move Panel）在拖拽多文件时的目标路径选择体验较弱，无预览确认。

---

## T10 — tmux 集成

### T10-1 tmux 会话发现

```bash
# 确保有 tmux 会话
tmux new-session -d -s test-session
# 打开 tmux 管理面板（Cmd+Shift+X），验证 test-session 出现
mcp capture_screenshot '{"target":"window"}'
```

### T10-2 Tab Attach

```bash
# 通过 API 创建新 Tab
mcp create_tab "{\"workspaceId\":\"$WS_ID\"}"
# 在新 Tab 的 pane 中 attach tmux
mcp send_text "{\"text\":\"tmux attach -t test-session\n\",\"paneId\":\"$NEW_PANE_ID\"}"
# 截图验证 Window Bar 出现在 pane 内
mcp capture_screenshot "{\"target\":\"pane\",\"paneId\":\"$NEW_PANE_ID\"}"
```

### T10-3 状态栏 tmux 按钮

```bash
mcp capture_screenshot "{\"target\":\"pane\",\"paneId\":\"$PANE_ID\"}"
# 验证状态栏底部显示 tmux attach 按钮（若当前目录有 tmux 会话）
```

**UX 分析：**
> ✅ tmux Tab Attach 是解决"tmux 会话管理与 terminal UI 割裂"的优雅方案。
> ⚠️ tmux Window Bar 占用 pane 顶部空间，在小尺寸分屏中压缩终端可视区域。建议支持折叠或悬浮模式。
> ⚠️ 关闭 tmux attach tab 的确认对话框过于频繁，tmux 会话并不会因此丢失，可考虑降级为 toast 提示而非阻断弹窗。

---

## T11 — App Launcher

### T11-1 双击 Shift 触发

- 手动：双击 `Shift` 键
- 验证：Launcher 浮层出现

### T11-2 模糊搜索

- 输入 `spit`（拼写错误）
- 期望：`Split Pane` 相关命令仍出现（Levenshtein 容错）

### T11-3 菜单路径副标题

- 搜索 `new tab`
- 验证：每个结果显示完整菜单路径（如 `Shell > New Tab`）

### T11-4 关闭行为

- 打开 Launcher 后点击外部区域
- 验证：自动关闭，terminal 焦点恢复

**UX 分析：**
> ✅ 双击 Shift 触发设计自然，不与常用快捷键冲突。
> ✅ 编辑距离搜索对拼写不准确的用户非常友好。
> ⚠️ Launcher 无法通过 API 触发或查询，纯 UI 功能，Agent 无法使用。
> ⚠️ 搜索结果缺少最近使用（MRU）排序，高频命令每次都需要手动输入。

---

## T12 — 截图综合验证

用截图对多个特性做视觉回归验证：

```bash
# 场景：多分屏 + 注释 + Git 状态栏 + 文件浏览器
# Step 1：创建 2x2 分屏布局
mcp create_tab "{\"workspaceId\":\"$WS_ID\"}"
NEW_TAB_PANE=$(mcp create_tab "{\"workspaceId\":\"$WS_ID\"}" | ...)
mcp split_pane "{\"paneId\":\"$NEW_TAB_PANE\",\"direction\":\"right\"}"
mcp split_pane "{\"paneId\":\"$NEW_TAB_PANE\",\"direction\":\"down\"}"

# Step 2：设置注释
mcp set_pane_annotation "{\"paneId\":\"$PANE_A\",\"annotation\":\"frontend\"}"
mcp set_pane_annotation "{\"paneId\":\"$PANE_B\",\"annotation\":\"backend api\"}"
mcp set_pane_annotation "{\"paneId\":\"$PANE_C\",\"annotation\":\"tests\"}"

# Step 3：模拟 agent 活跃（发送 PreToolUse hook）
# ...（参考 T04-3）

# Step 4：截取全窗口
mcp capture_screenshot '{"target":"window"}'
# 验证：注释卡片、状态栏 Agent 指示、Git 状态、分屏布局 全部正确渲染
```

---

## UX 综合评分与问题优先级

### 高优先级（影响 Agent 工作流）

| # | 问题 | 建议 |
|---|------|------|
| H1 | `list_panes` 无物理位置信息 | 增加 `layout` 或 `position` 字段 |
| H2 | `get_instance_info` workspace 缺少 `name`/`rootDirectory` | 扩展 workspace 元数据 |
| H3 | Git Panel 无 API 接口 | 增加 `get_git_status`、`stage_file` 工具 |
| H4 | Worktree 无 API 接口 | 增加 `list_worktrees`、`create_worktree` 工具 |
| H5 | `split_pane` 无法同时指定初始命令 | 增加可选 `command` 参数 |

### 中优先级（影响人工操作效率）

| # | 问题 | 建议 |
|---|------|------|
| M1 | Pane 注释不持久化 | 存入 workspace snapshot |
| M2 | Ctrl API Monitor 无持久化 | 支持导出或跨会话查看 |
| M3 | Agent Dashboard 失焦自动关闭 | 改为 Esc 显式关闭 |
| M4 | tmux Window Bar 占位大 | 支持折叠/悬浮 |
| M5 | App Launcher 无 MRU 排序 | 记录最近使用频率 |

### 低优先级（体验打磨）

| # | 问题 | 建议 |
|---|------|------|
| L1 | Pane 注释卡片遮挡内容 | 支持折叠或透明度 |
| L2 | `f/g` 快捷键发现性差 | 在面板 header 显示提示 |
| L3 | tmux 关闭 Tab 确认弹窗频繁 | 降级为 toast |
| L4 | `Opt+Cmd+C` 快捷键语义不直觉 | 考虑 `Opt+Cmd+L`（Logs） |

---

## 附录：常用测试片段

```bash
# 快速获取第一个 pane ID
first_pane() {
  mcp list_panes '{}' | python3 -c "
import sys, json
d = json.load(sys.stdin)
text = d['result']['content'][0]['text']
panes = json.loads(text)
print(panes[0]['id'] if panes else 'NO_PANES')
"
}

# 截图并自动打开
screenshot_open() {
  local target=${1:-window}
  local result=$(mcp capture_screenshot "{\"target\":\"$target\"}")
  local path=$(echo $result | python3 -c "
import sys, json
d = json.load(sys.stdin)
text = d['result']['content'][0]['text']
import re
m = re.search(r'\"path\":\"([^\"]+)\"', text)
print(m.group(1) if m else 'NO_PATH')
")
  open "$path"
}

# 发送 hook 事件（需要先设置 TOKEN 和 PORT）
send_hook() {
  local event=$1
  local extra=${2:-''}
  curl -s -X POST http://localhost:$PORT/v1/hooks/events \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"hook_event_name\":\"$event\",\"session_id\":\"test-cc-001\",\"cwd\":\"/tmp\"$extra}"
}
```
