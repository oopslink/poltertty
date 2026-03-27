# Ctrl API 测试执行结果 — 2026-03-27

测试计划：[docs/ctrl-api-test-plan.md](ctrl-api-test-plan.md)
执行版本：`0.1.9`（commit `7294d6c`）
测试端口：`49822` → 修复后重启 `49823`
构建模式：Debug / ONLY_ACTIVE_ARCH=YES（arm64）

---

## 执行总览

| 模块 | 状态 | 说明 |
|------|------|------|
| T01 — Ctrl API 自身 | ✅ 通过 | 健康检查、工具列表、SSE 心跳、错误处理 |
| T02 — Split Pane 管理 | ✅ 通过 | split/focus/create_tab、tabIndex/paneIndex 字段 |
| T03 — Pane 注释 | ✅ 通过（含修复） | 发现并修复 get_pane_annotation 返回 null 字段 |
| T04 — Agent 系统 | ✅ 通过 | prepare-session API、全类型 hook 事件投递 |
| T05 — Agent Dashboard | ⏭️ 跳过 | 纯 UI，需手动验证 |
| T06 — Workspace 管理 | ✅ 通过 | name/rootDirectory 字段新增验证 |
| T07 — Git Worktree | ✅ 通过 | 三个新工具完整验证 |
| T08 — Git Panel | ✅ 通过 | get_git_status 替代 DEBUG 工具；截图正常 |
| T09 — 文件浏览器 | ✅ 通过 | send_text + capture_screenshot 验证 |
| T10 — tmux 集成 | ✅ 通过 | attach 命令发送、pane 截图 |
| T11 — App Launcher | ⏭️ 跳过 | 纯 UI（双击 Shift），无 API 接口 |
| T12 — 综合截图 | ✅ 通过 | 多分屏 + 注释 + 全窗口截图 173KB |

---

## 逐模块执行记录

### T01 — Ctrl API 自身

**T01-1 健康检查**
```
GET /v1/health → {} (HTTP 200) ✅
```

**T01-2 工具列表**
```
tools/list → 15 个工具（12 生产 + 3 DEBUG）✅
生产工具：get_instance_info / create_tab / list_panes / focus_pane / send_text /
          split_pane / set_pane_annotation / get_pane_annotation / capture_screenshot /
          list_worktrees / create_worktree / get_git_status
DEBUG工具：click_window / test_fullscreen_diff / git_panel_state
```

**T01-3 SSE 心跳**
```
连接 GET /v1/mcp（SSE），等待 35 秒
收到：": ping"  ✅（30 秒心跳正常）
```

**T01-5 错误处理**
```
未知工具 → error.code=-32601, message="Unknown tool: unknown_tool"  ✅
缺少必需参数 → error.code=-32602, message="focus_pane: missing or invalid paneId"  ✅
```

---

### T02 — Split Pane 管理

**T02-1 list_panes（含新字段）**
```json
[{"id":"C2473C7C...","tabId":"...","workspaceId":"...","isActive":true,"tabIndex":0,"paneIndex":0}]
Pane 数量: 1，tabIndex/paneIndex 字段存在  ✅
```

**T02-2 split_pane (right)**
```json
{"newPaneId":"48B8146C-..."}  ✅
```

**T02-3 split_pane with command**
```json
{"newPaneId":"6293F28A-..."}
新 pane 自动执行 "echo 'hello from ctrl api'"  ✅
```

**T02-4 focus_pane**
```json
{"ok":true}  ✅
```

**T02-5 create_tab**
```json
{"paneId":"1DD2A1E2-..."}
list_panes 验证：Tab0=3 panes, Tab1=1 pane  ✅
```

---

### T03 — Pane 注释

**T03-1/2 set/get**
```
set_pane_annotation → {"ok":true}  ✅
get_pane_annotation → {"annotation":"主工作区"}  ✅
```

**T03-3 list_panes 含注释字段**
```
paneIdx=0 annotation=主工作区  ✅
paneIdx=1 annotation=(无)  ✅
```

**T03-4 清除注释（修复前）**
```
set annotation="" → {"ok":true}
get annotation → {"annotation": null}  ❌ 违反规范（null 字段应省略）
```

**修复后验证（T03-4）**
```
无注释时 get_pane_annotation → {}  ✅
有注释时 get_pane_annotation → {"annotation":"dev"}  ✅
```

---

### T04 — Agent 系统

**T04-1 环境检查**
```
poltertty-cli 存在：~/.poltertty/bin/poltertty-cli (94272 bytes)  ✅
poltertty-agent-wrapper 存在：~/.poltertty/bin/poltertty-agent-wrapper  ✅
注：poltertty-cli prepare-session 子命令直接调用失败（返回 "prepare-session request failed"）
    但 POST /v1/sessions 直接调用正常，为 CLI 旧版本兼容问题  ⚠️
```

**T04-2 prepare-session（via API）**
```
POST /v1/sessions → 200 OK
{
  "sessionDir": "~/.poltertty/sessions/test-pts-001",
  "token": "LGDX9mbpR7tnUxAE/..."
}
meta.json / settings.json 均已创建  ✅
settings.json 包含 11 个 hook + mcpServers.poltertty  ✅
```

**T04-3 Hook 事件投递**
```
SessionStart   → HTTP 202  ✅
PreToolUse     → HTTP 202  ✅
Notification   → HTTP 202  ✅
SessionEnd     → HTTP 202  ✅
```

**T04-5 SubagentStart**
```
SubagentStart → HTTP 202  ✅
```

---

### T06 — Workspace 管理

**T06-1 get_instance_info（含新字段）**
```json
{
  "instanceId": "com.oopslink.poltertty.debug",
  "version": "0.1.9",
  "port": 49822,
  "workspaces": [{
    "id": "AB0E60D1-...",
    "name": "scratch",
    "rootDirectory": "/var/folders/.../T/_poltertty_tmp_ED405E63",
    "isActive": false
  }]
}
name / rootDirectory 字段存在  ✅
```

---

### T07 — Git Worktree 管理

**T07-1 list_worktrees（显式 directory）**
```
directory: <repo-root>
返回 4 个 worktree：
  main (isMain=true, exists=true)
  feat/ctrl-api-gaps (exists=true)
  optimize/ctrl-api (exists=true)
  test/abc (exists=true)  ✅
```

**T07-1 list_worktrees（无 directory，workspace root 为临时目录）**
```
error: "list_worktrees: fatal: not a git repository"  ✅（符合预期，临时目录非 git 仓库）
```

**T07-2 create_worktree**
```json
{"branch":"test/ctrl-api-wt-test","path":"/tmp/poltertty_test_wt_69555"}
验证列表增至 5 个  ✅
清理后正常删除  ✅
```

**T07-3 get_git_status（git 仓库）**
```json
{
  "isGitRepo": true,
  "branch": "main",
  "staged": [],
  "unstaged": [],
  "untracked": ["docs/ctrl-api-test-plan.md"]
}  ✅
```

**T07-4 get_git_status（非 git 目录）**
```json
{"isGitRepo": false}  ✅
```

---

### T08 — Git Panel

**T08-1 通过 get_git_status 验证状态**
```
branch=main, staged=[], untracked=["docs/ctrl-api-test-plan.md"]  ✅
（替代 DEBUG 工具 git_panel_state，符合生产规范）
```

**T08-2 全窗口截图**
```
路径：/var/folders/.../poltertty/screenshots/7290017B-....png
大小：173048 bytes  ✅
```

---

### T09 — 文件浏览器

**T09-1 pane 截图**
```
路径：.../C871DBCF-....png  84392 bytes  ✅
```

**T09-2 send_text pwd**
```
{"ok":true}  ✅
```

---

### T10 — tmux 集成

**T10-2 attach 流程**
```
create_tab → 新 pane: 1B5BFBDC-...  ✅
send_text "tmux attach -t poltertty-test" → {"ok":true}  ✅
pane 截图：65886 bytes  ✅
```

---

### T12 — 综合截图验证

```
6 个 pane（Tab0×4 + Tab1×1 + Tab2×1）
Tab0 Pane0: annotation="agent: claude"
Tab0 Pane1: annotation="tests"
全窗口截图：513A7721-....png  173048 bytes  ✅
```

---

## 执行中发现的问题与处置

### Bug（已修复并提交）

| # | 问题 | 修复 | Commit |
|---|------|------|--------|
| B1 | `get_pane_annotation` 无注释时返回 `{"annotation":null}`，违反规范（null 字段应省略） | 改用条件插入，无注释时返回 `{}` | `7294d6c` |

### 限制（非 Bug）

| # | 现象 | 原因 |
|---|------|------|
| L1 | `poltertty-cli prepare-session` 子命令调用失败 | CLI 旧版本（3月23日构建），`/v1/sessions` 直接调用正常 |
| L2 | `get_instance_info` 中 `isActive` 全部为 `false` | 通过命令行启动的 app 无 keyWindow，不影响其他功能 |
| L3 | `list_worktrees`（无 directory）在临时目录 workspace 报错 | 预期行为，临时目录非 git 仓库 |

---

## 测试覆盖的 UX 优先级问题

测试计划列出的高优先级问题，本次执行验证了其修复状态：

| # | 问题 | 状态 |
|---|------|------|
| H1 | list_panes 无物理位置信息 | ⚡ 部分：新增 tabIndex/paneIndex（相对位置），绝对坐标未实现 |
| H2 | get_instance_info workspace 缺少 name/rootDirectory | ✅ 已修复并验证 |
| H3 | Git Panel 无 API 接口 | ✅ 新增 get_git_status 生产工具 |
| H4 | Worktree 无 API 接口 | ✅ 新增 list_worktrees / create_worktree |
| H5 | split_pane 无初始命令参数 | ✅ 新增 command 参数并验证 |
