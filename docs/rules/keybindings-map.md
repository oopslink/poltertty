# Poltertty 快捷键总览

> **新增快捷键前必须先查阅本文档，避免冲突。**

---

## ⚠️ 冲突注意

分配快捷键时有两层需要避免冲突：

1. **Zig 层（终端内核）**：在 `src/config/Config.zig` 中硬编码，优先级最高，会拦截键事件，App 层收不到。
2. **App 层（Swift/AppDelegate）**：NSMenuItem keyEquivalent，只有 Zig 层未处理时才生效。

⌥⌘I 就是典型案例：Zig 层默认把它绑给了 Inspector，导致 App 层的 Shell Popup 菜单项永远收不到该事件。

---

## Zig 层默认绑定（src/config/Config.zig）

### ⌥⌘ 组合（alt + super）

| 快捷键 | 功能 |
|--------|------|
| `⌥⌘W` | 关闭当前 Tab |
| `⌥⌘⇧W` | 关闭所有窗口 |
| `⌥⌘↑` | 跳转到上方分屏 |
| `⌥⌘↓` | 跳转到下方分屏 |
| `⌥⌘←` | 跳转到左方分屏 |
| `⌥⌘→` | 跳转到右方分屏 |
| `⌥⌘I` | **Toggle Inspector（已被占用！）** |

### ⌘ 组合（super）

| 快捷键 | 功能 |
|--------|------|
| `⌘Q` | 退出 |
| `⌘K` | 清屏 |
| `⌘A` | 全选 |
| `⌘T` | 新建 Tab |
| `⌘W` | 关闭当前分屏 |
| `⌘⇧W` | 关闭当前窗口 |
| `⌘D` | 向右分屏 |
| `⌘⇧D` | 向下分屏 |
| `⌘[` | 前一个分屏 |
| `⌘]` | 下一个分屏 |
| `⌘⇧[` | 前一个 Tab |
| `⌘⇧]` | 下一个 Tab |
| `⌘Z` | Undo |
| `⌘⇧Z` | Redo |
| `⌘⌃F` | 切换全屏 |

### ⌃⇧ 组合（ctrl + shift）

| 快捷键 | 功能 |
|--------|------|
| `⌃⇧I` | Toggle Inspector（Linux/通用） |
| `⌃⇧A` | 全选 |
| `⌃⇧J` | 切换 Tab（⌃⇧⌘J 也有绑定） |

---

## App 层绑定（AppDelegate.swift，NSMenuItem）

### Workspace 菜单（⌥⌘ 系列）

| 快捷键 | 功能 |
|--------|------|
| `⌘⇧[` | 上一个 Workspace |
| `⌘⇧]` | 下一个 Workspace |
| `⌘⇧N` | 新建 Workspace |
| `⌥⌘P` | 切换 Sidebar |
| `⌥⌘F` | 切换 File Browser |
| `⌥⌘H` | 切换 Shell Popup |
| `⌥⌘G` | 切换 Lazygit Popup |

### Agent 菜单（⌥⌘ 系列）

| 快捷键 | 功能 |
|--------|------|
| `⌥⌘A` | Launch Agent |
| `⌥⌘M` | Agents In Workspace |
| `⌥⌘D` | Agent Dashboard |
| `⌥⌘N` | Agent Notification Center |
| `⌥⌘C` | Ctrl Monitor |
| `⌥⌘U` | Jump To Unread |
| `⌥⌘T` | New Tab (tmux) |

---

## 可用的 ⌥⌘ 字母（未被任何层占用）

以下字母在 Zig 层和 App 层均空闲，可安全分配：

`B` `E` `J` `K` `L` `O` `Q` `R` `S` `V` `X` `Y` `Z`

---

## 更新记录

| 日期 | 变更 |
|------|------|
| 2026-04-08 | 初始版本，整理全部已用快捷键；将 Shell Popup 从 ⌥⌘I 改为 ⌥⌘H（⌥⌘I 被 Zig 层 Inspector 占用） |
