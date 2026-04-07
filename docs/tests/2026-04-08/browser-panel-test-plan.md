# Browser Panel（2.5）测试计划

**日期**：2026-04-08  
**范围**：Roadmap 2.5 Agent Browser — 一期 UI + 二期 Ctrl API + CLI  
**PR**：feature/browser-panel-api

---

## 测试分层

| 层级 | 工具 | 文件 | 覆盖范围 |
|------|------|------|---------|
| 单元测试 | Swift Testing | `macos/Tests/Workspace/BrowserTabManagerTests.swift` | Tab 生命周期、快照序列化 |
| 单元测试 | Swift Testing | `macos/Tests/Workspace/BrowserSurfaceStoreTests.swift` | 多 workspace 隔离、懒创建、删除清理 |
| e2e 测试 | Shell + Ctrl API | `docs/tests/2026-04-08/browser-ctrl-api-test.sh` | 全部 browser_* 工具的真实调用链 |

---

## 单元测试清单

### BrowserTabManagerTests（已存在）

| # | 测试用例 | 预期结果 |
|---|---------|---------|
| 1 | `newTab` 创建 tab 并设为 active | `tabs.count == 1`, `activeTabId` 匹配 |
| 2 | `newTab(url:)` 设置 URL | `tabs[0].url == url` |
| 3 | 连续 `newTab` 后 active 指向最新 | `activeTabId == id2` |
| 4 | `closeTab` 删除非 active tab | `tabs.count == 1`, active 不变 |
| 5 | `closeTab` active tab → 切换到左邻居 | `activeTabId == id1` |
| 6 | `closeTab` 最左端 → 切换到右邻居 | `activeTabId == id2` |
| 7 | 关闭最后一个 tab → 自动创建空白 tab | `tabs.count == 1`, `url == nil` |
| 8 | `focusTab` 更新 activeId | `activeTabId == id1` |
| 9 | `focusTab` 不存在的 ID → 无操作 | activeId 不变 |
| 10 | `currentSnapshot` 包含所有 tab | count / url / title 正确 |
| 11 | `prepareRestore` 有快照 → 设置 prompt | `showRestorePrompt == true`, tabs 为空 |
| 12 | `prepareRestore` 空数组 → 不设置 prompt | `showRestorePrompt == false` |
| 13 | `loadSnapshot` 创建正确 tab | ids / activeId 对应 |
| 14 | `loadSnapshot` activeId 不存在 → fallback 到第一个 | `activeTabId == snaps[0].id` |
| 15 | `loadSnapshot` 清除旧 tabs | `tabs.count == 1` (只有 restore 的) |

### BrowserSurfaceStoreTests（新增）

| # | 测试用例 | 预期结果 |
|---|---------|---------|
| 1 | `manager(for:)` 首次调用创建实例 | `managers[wsId] != nil` |
| 2 | 同一 wsId 返回同一实例 | `mgr1 === mgr2` |
| 3 | 不同 wsId 返回不同实例 | `mgr1 !== mgr2` |
| 4 | 无快照 → 自动创建空白 tab | `tabs.count == 1`, `url == nil` |
| 5 | 有快照 → 设置 restore prompt，不创建 tab | `showRestorePrompt == true`, `tabs.isEmpty` |
| 6 | 空数组快照 → 等同于无快照 | 空白 tab 被创建 |
| 7 | nil 快照 → 等同于无快照 | 空白 tab 被创建 |
| 8 | 已存在 manager 不受后续 snapshots 影响 | 实例不变，tabs 不被重置 |
| 9 | `removeManager` 删除条目 | `managers[wsId] == nil` |
| 10 | `removeManager` 清除 webView.navigationDelegate | delegate 为 nil |
| 11 | `removeManager` 不存在的 wsId → 无崩溃 | 正常执行 |
| 12 | 多 workspace 独立操作 | 互不影响 |

---

## Ctrl API E2E 测试清单

> 在 Poltertty terminal 中运行：
> ```bash
> bash docs/tests/2026-04-08/browser-ctrl-api-test.sh
> ```

| # | 工具 | 输入 | 预期响应 |
|---|------|------|---------|
| 1 | `browser_list_tabs` | `{}` | 数组（可空） |
| 2 | `browser_new_tab` | `{}` | `{tabId: uuid}` |
| 3 | `browser_new_tab` | `{url: "https://example.com"}` | `{tabId: uuid}` |
| 4 | `browser_list_tabs` | `{}` | 至少 2 个 tab |
| 5 | `browser_focus_tab` | `{tabId: <id>}` | `{ok: true}` |
| 6 | `browser_navigate` | `{url: "https://example.com"}` | `{ok: true}` |
| 7 | `browser_wait` | `{condition: "load", timeout: 15}` | `{ok: true}` |
| 8 | `browser_snapshot` | `{}` | `{elements: [...], url, title}` |
| 9 | `browser_get_text` | `{}` | `{text: "..."}` |
| 10 | `browser_eval` | `{script: "return document.title"}` | 非空 JSON 字符串 |
| 11 | `browser_eval` | `{script: "/* no return */"}` | `"null"` |
| 12 | `browser_screenshot` | `{format: "path"}` | `{path: "..."}` + 文件存在 |
| 13 | `browser_screenshot` | `{format: "base64"}` | `{base64: "...", mimeType: "image/png"}` |
| 14 | `browser_wait` | `{condition: "text", value: "Example", timeout: 10}` | `{ok: true}` |
| 15 | `browser_wait` | `{condition: "url", value: "example.com", timeout: 5}` | `{ok: true}` |
| 16 | `browser_close_tab` | `{tabId: <id>}` | `{ok: true}` |
| 17 | `browser_open_split` | `{}` | `{ok: true, workspaceId: uuid}` |
| 18 | `browser_open_split` | `{url: "https://example.com"}` | `{ok: true}` |
| 19 | `browser_wait` (不存在的文本) | `{condition: "text", value: "__NONEXISTENT__", timeout: 2}` | error code -32603, message 含 "timeout" |
| 20 | `browser_eval` (缺 script) | `{}` | error code -32602 |

---

## 手动 UI 验证清单

以下需要目视确认：

| # | 操作 | 预期行为 |
|---|------|---------|
| 1 | `⌥⌘B` | 右侧 Browser Panel 滑入，宽度 400px |
| 2 | `⌥⌘B` 再次 | Browser Panel 收起 |
| 3 | `⌥⇧⌘B` | Browser Panel 展开占满屏幕，终端区域隐藏 |
| 4 | Browser Panel 工具栏地址栏输入 `localhost:3000` → Enter | 导航到该 URL |
| 5 | Port badge 点击（侧边栏 `:3000`） | Browser Panel 打开并导航到 `http://localhost:3000` |
| 6 | 工具栏 `+` 按钮 | 新建空白 tab |
| 7 | tab `×` 按钮 | 关闭该 tab |
| 8 | resize 分割线拖拽 | Browser Panel 宽度跟随 |
| 9 | 关闭 Browser Panel → 重新打开 | 上次 URL 恢复提示横幅出现 |
| 10 | Restore → 确认 | tabs 恢复，URL 加载 |
| 11 | Restore → Dismiss | 跳过，打开新空白 tab |
| 12 | 切换 Workspace | Browser Panel 跟随，保留该 workspace 的 tabs |
| 13 | 多窗口同时打开 Browser Panel | 互不干扰，各自保留状态 |

---

## 回归检查点（development-rules）

- [ ] 光标无空心方块（未修改 `syncFocusToSurfaceTree`）
- [ ] 上下分屏焦点切换正常（未修改 `localEventLeftMouseDown`）
- [ ] 多窗口通知隔离（`.openBrowserPanel` 携带 workspaceId）
- [ ] 初始渲染时序正确（无新增 `async` 布局延迟）
