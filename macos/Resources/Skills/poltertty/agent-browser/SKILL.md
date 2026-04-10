---
name: poltertty/agent-browser
version: "1.0.0"
description: >
  Poltertty 内置浏览器面板的 Agent 操作指南。仅在 Poltertty 终端内生效（通过
  环境变量 POLTERTTY_CTRL_PORT 是否存在判断）。当用户需要让
  AI Agent 控制浏览器、做网页自动化、抓取页面内容、填写表单、点击元素、截图、
  执行 JavaScript 时，必须使用此 skill。涵盖所有 13 个 browser_* Ctrl API 工具
  的调用方式、参数说明、典型工作流及注意事项。如果用户提到"浏览器面板"、
  "agent 浏览器"、"browser_*"、"让 agent 打开网页"，立即使用此 skill。
---

## 环境检查（必须首先执行）

在使用任何 browser_* 工具前，先确认 `POLTERTTY_CTRL_PORT` 环境变量存在：

```bash
echo $POLTERTTY_CTRL_PORT
```

- **有值**（如 `9876`）：说明当前在 Poltertty 终端内，可继续使用 browser_* 工具
- **为空**：说明不在 Poltertty 环境，**停止使用此 skill**，告知用户需要在 Poltertty 终端中运行 Claude Code 才能使用内置浏览器

## 调用方式

所有 browser_* 工具通过 JSON-RPC 调用 Ctrl Server：

```bash
curl -s -X POST http://localhost:$POLTERTTY_CTRL_PORT/v1/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"<工具名>","arguments":{...}}}'
```

返回格式：
```json
{"id":1,"jsonrpc":"2.0","result":{"content":[{"type":"text","text":"{...}"}]}}
```

实际结果在 `result.content[0].text` 中（JSON 字符串，需再次解析）。


# Poltertty Agent Browser

Poltertty 通过 **Ctrl API**（MCP 工具调用协议）向 AI Agent 暴露了一套完整的浏览器自动化工具。每个 Workspace 有独立的浏览器状态，标签页互不干扰。

---

## 核心工作流

```
browser_open_split          ← 打开浏览器面板（首次使用）
  → browser_navigate        ← 导航到目标 URL
  → browser_wait load       ← 等待页面加载完成
  → browser_snapshot        ← 获取交互元素（返回 e1, e2... 引用）
  → browser_click / fill    ← 用引用操作元素
  → browser_snapshot        ← 操作后重新快照（引用已失效）
```

**关键规则**：每次页面导航或 DOM 变化后，必须重新调用 `browser_snapshot`，旧的 `@eN` 引用会失效。

---

## 完整 API 参考

所有工具均支持可选参数 `workspaceId`（默认当前活跃 Workspace）和 `tabId`（默认当前活跃标签页）。

### 面板与标签页管理

| 工具 | 必填参数 | 说明 |
|------|---------|------|
| `browser_open_split` | — | 打开浏览器面板，可选 `url` 参数 |
| `browser_new_tab` | — | 新建标签页，可选 `url` |
| `browser_close_tab` | `tabId` | 关闭指定标签页 |
| `browser_focus_tab` | `tabId` | 切换到指定标签页 |
| `browser_list_tabs` | — | 列出所有标签页，返回 `[{tabId, title, url, active}]` |

### 导航与等待

| 工具 | 必填参数 | 说明 |
|------|---------|------|
| `browser_navigate` | `url` | 导航到 URL |
| `browser_wait` | `condition` | 等待条件满足（见下方说明） |

**`browser_wait` 的 condition 类型**：
- `load` — 等待 `document.readyState === 'complete'`
- `url` — 等待当前 URL 包含指定 `value` 字符串
- `selector` — 等待 CSS 选择器元素出现且可见（宽高 > 0）
- `text` — 等待页面 body 文本包含指定 `value` 字符串

可选 `timeout` 参数（默认 10s），轮询间隔 300ms。

### 元素交互

| 工具 | 必填参数 | 说明 |
|------|---------|------|
| `browser_snapshot` | — | 提取页面交互元素，返回带编号引用（e1, e2...） |
| `browser_click` | `ref` 或 `selector` | 点击元素 |
| `browser_fill` | `ref`/`selector` + `value` | 填充输入框（兼容 React controlled input） |

**snapshot 返回格式**：
```json
{
  "elements": [
    {"ref": "e1", "tag": "button", "text": "登录", "type": "submit"},
    {"ref": "e2", "tag": "input", "placeholder": "用户名", "name": "username"},
    {"ref": "e3", "tag": "a", "text": "注册", "href": "/signup"}
  ],
  "url": "https://example.com/login",
  "title": "登录页面"
}
```

`browser_fill` 会触发 React 的 `onChange`，原理是调用 native setter + 分发 `input`/`change` 事件。

### 信息提取与截图

| 工具 | 必填参数 | 说明 |
|------|---------|------|
| `browser_get_text` | — | 获取元素或整页文本，可选 `ref`/`selector` |
| `browser_screenshot` | — | 截图，可选 `format`（`path` 或 `base64`，默认 path） |
| `browser_eval` | `script` | 在页面上下文中执行任意 JavaScript |

---

## 典型场景示例

### 场景一：打开网页并提取内容

```
browser_open_split(url: "https://example.com")
browser_wait(condition: "load")
browser_get_text()                     ← 获取整页文本
browser_screenshot(format: "path")    ← 截图留存
```

### 场景二：登录表单

```
browser_navigate(url: "https://app.example.com/login")
browser_wait(condition: "load")
browser_snapshot()
← 得到: e1=用户名输入框, e2=密码输入框, e3=登录按钮
browser_fill(ref: "e1", value: "username")
browser_fill(ref: "e2", value: "password")
browser_click(ref: "e3")
browser_wait(condition: "url", value: "/dashboard")
browser_snapshot()                     ← 登录后重新快照
```

### 场景三：多标签页并行操作

```
browser_new_tab(url: "https://site-a.com")
← 返回 tabId: "uuid-a"

browser_new_tab(url: "https://site-b.com")
← 返回 tabId: "uuid-b"

browser_snapshot(tabId: "uuid-a")     ← 操作 A 标签页
browser_get_text(tabId: "uuid-b")     ← 读取 B 标签页内容
```

### 场景四：JavaScript 注入

```
browser_eval(script: "document.querySelectorAll('img').length")
← 返回图片数量

browser_eval(script: """
  JSON.stringify(
    Array.from(document.querySelectorAll('a'))
      .map(a => ({text: a.textContent, href: a.href}))
  )
""")
```

---

## 架构说明

- **工具调用路径**：Ctrl API → `CtrlToolHandler` → `BrowserTabManager`（`@MainActor`）→ `WKWebView`
- **Workspace 隔离**：每个 Workspace 有独立的 `BrowserTabManager`，通过 `workspaceId` 参数路由
- **面板控制**：`browser_open_split` 内部通过 `NotificationCenter.post(.openBrowserPanel)` 触发 SwiftUI 更新
- **元素引用缓存**：snapshot 将 DOM 元素缓存到 `window.__polterttyRefs`，click/fill 通过 ref 查找

---

## 返回值约定

- **成功**：`{"ok": true}` 或具体数据如 `{"tabId": "..."}`, `{"text": "..."}`, `{"path": "..."}`
- **失败**：抛出 `RPCError`，被转为 JSON-RPC 2.0 error 响应

---

## 错误处理

调用失败时返回 JSON-RPC error：
```json
{"jsonrpc":"2.0","error":{"message":"browser_fill: {\"error\":\"ref e22 not found, re-run browser_snapshot\"}","code":-32603},"id":2}
```

常见错误及处理方式：
- **ref not found** → 引用已过期，重新调用 `browser_snapshot` 获取新引用
- **连接拒绝** (curl: Connection refused) → Ctrl Server 未启动或端口已变化，重新检查 `$POLTERTTY_CTRL_PORT`
- **超时** (browser_wait) → 页面加载慢或条件不满足，增大 `timeout` 参数或改用其他 condition

---

## 注意事项

1. **必须先打开面板**：首次使用前调用 `browser_open_split`，否则 `BrowserTabManager` 可能未初始化
2. **快照失效**：导航、点击链接、表单提交后旧引用即失效，必须重新 snapshot
3. **等待是关键**：SPA 应用导航后用 `browser_wait(condition: "url")` 或 `browser_wait(condition: "selector")` 确认页面就绪
4. **截图格式**：需要传给 Vision 模型时用 `format: "base64"`；保存到磁盘用 `format: "path"`
