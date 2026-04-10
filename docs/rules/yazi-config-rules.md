# Yazi v26.x 配置参考手册

> 适用版本: yazi v26.1.22+（Poltertty 内嵌版本）
> 最后更新: 2026-04-09

## 1. 概述

Poltertty 内嵌 yazi 作为 workspace 左侧面板的文件浏览器。yazi 二进制文件打包在 `Poltertty.app/Contents/Resources/bin/` 中，配置文件位于 `macos/Resources/yazi-config/`。

yazi v26.x 相较旧版有大量 **breaking changes**，本文档记录所有已知的不兼容变更和正确用法，避免重复踩坑。

## 2. 配置文件结构

```
macos/Resources/yazi-config/
  yazi.toml          # 主配置：[mgr], [preview], [opener], [plugin]
  keymap.toml        # 快捷键映射
  theme.toml         # 主题（颜色、边框样式）
  init.lua           # 配置根目录初始化脚本（yazi 启动时自动执行）
  plugins/
    restrict-nav.yazi/
      main.lua       # 插件入口（必须是 main.lua）
    git-diff.yazi/
      main.lua       # 插件入口（必须是 main.lua）
```

### 关键区分：init.lua vs main.lua

| 文件 | 位置 | 用途 |
|------|------|------|
| `init.lua` | 配置根目录 `yazi-config/init.lua` | yazi 启动时自动执行的全局初始化脚本 |
| `main.lua` | 插件目录 `plugins/xxx.yazi/main.lua` | 插件入口文件，v26.x **必须**用此文件名 |

**注意**: v26.x 之前插件入口文件是 `init.lua`，现在**必须**改为 `main.lua`。配置根目录的初始化脚本仍然是 `init.lua`。

## 3. yazi.toml 各节详解

### 3.1 [mgr]（原 [manager]）

**Breaking Change**: v26.x 将 `[manager]` 重命名为 `[mgr]`。

```toml
# 正确 (v26.x)
[mgr]
ratio = [0, 1, 3]

# 错误 (旧版写法，v26.x 会忽略)
# [manager]
# ratio = [0, 1, 3]
```

`ratio` 定义三列宽度比例 `[parent, current, preview]`：
- `[0, 1, 3]` — 隐藏父目录面板，当前列和预览列比例 1:3（Poltertty 默认 "Preview" 布局）
- `[0, 1, 0]` — 仅显示当前列，无预览（Poltertty "Focus" 布局）

Poltertty 通过 `YaziSurfaceStore.configDir(for:)` 动态生成带有不同 ratio 的临时配置目录。

### 3.2 [preview]

```toml
[preview]
wrap = "yes"
```

**Breaking Change**: `wrap` 的值是**字符串** `"yes"` / `"no"`，不是布尔值 `true` / `false`。写成 `wrap = true` 会被忽略。

### 3.3 [opener]

```toml
[opener]
edit = [
    { run = 'poltertty-open "$@"', desc = "Open in Poltertty tab", for = "unix" },
]
open = [
    { run = 'open "$@"', desc = "Open with system default", for = "macos" },
]
```

`opener` 节定义文件打开方式。Poltertty 使用自定义的 `poltertty-open` 脚本在新 tab 中打开文件。

### 3.4 [plugin]

```toml
[plugin]
prepend_previewers = [
    { mime = "text/*", run = "git-diff" },
]
```

`prepend_previewers` 在默认 previewer 列表**前面**追加自定义 previewer。`run` 的值对应 `plugins/` 下的目录名（不含 `.yazi` 后缀）。

## 4. keymap.toml 配置

### 4.1 Breaking Change: [manager] → [mgr]

```toml
# 正确 (v26.x)
[[mgr.prepend_keymap]]
on   = [ "<Enter>" ]
run  = "open"
desc = "Open file in Poltertty tab"

# 错误 (旧版写法)
# [[manager.prepend_keymap]]
```

### 4.2 prepend_keymap vs keymap

| 写法 | 效果 |
|------|------|
| `[[mgr.prepend_keymap]]` | **追加**到默认快捷键列表前面，保留所有默认键位 |
| `[[mgr.keymap]]` | **替换**全部默认快捷键，只保留你显式定义的键位 |

**规则**: 除非你明确要替换所有默认键位，否则**始终使用 `prepend_keymap`**。

同样的规则适用于其他 section:
- `[[input.prepend_keymap]]` / `[[input.keymap]]`
- `[[completion.prepend_keymap]]` / `[[completion.keymap]]`

### 4.3 当前 Poltertty 键位

```toml
# Enter 键打开文件（在 Poltertty 新 tab 中）
[[mgr.prepend_keymap]]
on   = [ "<Enter>" ]
run  = "open"
desc = "Open file in Poltertty tab"

# h 键向上导航（限制在 workspace 根目录内）
[[mgr.prepend_keymap]]
on   = [ "h" ]
run  = "plugin restrict-nav"
desc = "Go to parent (restricted to workspace root)"
```

## 5. 插件开发规范

### 5.1 目录结构

```
plugins/
  my-plugin.yazi/
    main.lua          # 必须是 main.lua，不是 init.lua
```

### 5.2 插件模板

```lua
local M = {}

-- previewer 插件实现 peek 和 seek
function M:peek(job)
    -- job.file.path  — 文件路径（用于文件操作）
    -- job.file.url   — 文件标识（用于身份检查）
    -- job.area       — 预览区域
    -- job.area.w     — 预览区域宽度
end

function M:seek(job)
    require("code"):seek(job)
end

-- 功能插件实现 entry
function M:entry(_, _)
    -- 插件逻辑
end

return M
```

### 5.3 Lua API 变更（v26.x Breaking Changes）

#### Command API

```lua
-- 正确 (v26.x): arg() 单数形式，接受字符串或 table
Command("git"):arg({ "status", "--porcelain", "--", path })
Command("git"):arg("status")

-- 错误 (旧版): args() 复数形式
-- Command("git"):args({ "status" })
```

#### Command 执行

```lua
-- output() 返回 result（包含 .stdout, .stderr）
local result = Command("git")
    :arg({ "diff", "HEAD", "--", path })
    :stdout(Command.PIPED)
    :stderr(Command.NULL)
    :output()

if not result or #result.stdout == 0 then
    -- 处理空结果
end

-- spawn() 返回 child process
local child = Command("delta")
    :arg({ "--paging=never" })
    :stdin(Command.PIPED)
    :stdout(Command.PIPED)
    :spawn()

if child then
    child:write_all(input_data)
    child:flush()
    local output = child:wait_with_output()
end
```

#### Preview Widget API

```lua
-- 正确 (v26.x): preview_widget 单数，widget 必须链式调用 :area(job.area)
ya.preview_widget(job, ui.Text.parse(content):area(job.area))
ya.preview_widget(job, ui.Text(content):area(job.area))

-- 错误 (旧版): preview_widgets 复数，传数组
-- ya.preview_widgets(job, { ui.Text(content) })
```

**关键**: Widget 必须通过 `:area(job.area)` 显式绑定区域，否则不会渲染。

#### ya.sync 用法

```lua
-- 同步访问 yazi 内部状态（如当前工作目录）
local get_cwd = ya.sync(function(_)
    return tostring(cx.active.current.cwd)
end)

-- 在异步上下文中调用
local cwd = get_cwd()
```

#### job.file 属性

| 属性 | 类型 | 用途 |
|------|------|------|
| `job.file.path` | 路径 | 用于文件操作（读取、传给命令） |
| `job.file.url` | URL | 用于身份检查、比较 |

使用 `tostring()` 转换为字符串: `tostring(job.file.path)`

## 6. 从旧版迁移检查清单

迁移到 v26.x 时，逐项检查以下内容：

- [ ] `yazi.toml`: `[manager]` → `[mgr]`
- [ ] `keymap.toml`: `[[manager.prepend_keymap]]` → `[[mgr.prepend_keymap]]`
- [ ] `keymap.toml`: `[[manager.keymap]]` → `[[mgr.keymap]]`
- [ ] `[preview]`: `wrap = true` → `wrap = "yes"`
- [ ] 插件目录: `init.lua` → `main.lua`
- [ ] Lua: `Command:args()` → `Command:arg()`
- [ ] Lua: `ya.preview_widgets(job, { widget })` → `ya.preview_widget(job, widget)`
- [ ] Lua: Widget 添加 `:area(job.area)` 调用
- [ ] Lua: `self` 参数 → `job` 参数（previewer/entry 函数签名）
- [ ] `theme.toml`: `[manager]` 节名**未变**（theme 中仍然是 `[manager]`，不是 `[mgr]`）

### theme.toml 特殊说明

`theme.toml` 中的 `[manager]` 节名**没有**跟随改名，仍然用 `[manager]`：

```toml
# theme.toml 中保持 [manager]，不是 [mgr]
[manager]
border_style = { fg = "gray" }
```

这是一个容易搞混的地方，只有 `yazi.toml` 和 `keymap.toml` 中的 `manager` 改为了 `mgr`。

## 7. Poltertty 特有配置机制

### 7.1 动态配置目录生成

Poltertty 不直接使用 bundled 配置目录，而是通过 `YaziSurfaceStore.configDir(for:)` 在 `/tmp/` 下动态生成配置目录：

1. 在 `/tmp/poltertty-yazi-{ratio-key}/` 创建临时目录
2. 将 `keymap.toml`、`theme.toml`、`plugins/`、`init.lua` 以**符号链接**指向 bundled 目录
3. 动态生成 `yazi.toml`，替换 `ratio` 值为当前布局预设

这样每次切换布局预设时，只需生成新的 `yazi.toml`，其他文件通过 symlink 共享。

### 7.2 环境变量

| 环境变量 | 用途 | 设置位置 |
|----------|------|----------|
| `YAZI_CONFIG_HOME` | 指定 yazi 配置目录 | `YaziSurfaceStore.surface(for:)` |
| `YAZI_DELTA_PATH` | delta 二进制路径（git-diff 插件用） | 同上 |
| `YAZI_ROOT_DIR` | workspace 根目录（restrict-nav 插件用） | 同上 |
| `POLTERTTY_WS_ID` | workspace UUID（init.lua 写入 YAZI_ID 用） | 同上 |
| `PATH` | 包含 bundled bin 目录 | 同上 |

### 7.3 YAZI_ID 通信机制

Poltertty 需要向特定 yazi 实例发送 `cd` 命令（切换目录）。流程：

1. yazi 启动时，`init.lua` 读取 `POLTERTTY_WS_ID` 和 `YAZI_ID` 环境变量
2. 将 `YAZI_ID` 写入 `/tmp/poltertty-yazi-{wsId}.id`
3. Swift 端通过 `YaziSurfaceStore.cdToDirectory()` 读取该文件获取 `YAZI_ID`
4. 调用 `ya emit-to <YAZI_ID> cd <path>` 精准控制目标实例

### 7.4 布局预设

当前定义在 `YaziSurfaceStore.ratioPresets` 中：

| 预设名 | ratio | 说明 |
|--------|-------|------|
| Preview | `[0, 1, 3]` | 隐藏父目录，预览占大部分宽度 |
| Focus | `[0, 1, 0]` | 仅当前列，无预览 |

所有预设都将 parent 设为 0，配合 `restrict-nav` 插件防止用户浏览到 workspace 根目录之外。

## 8. 常见问题排查

### Q: 插件不生效 / 报错找不到模块

**原因**: 插件入口文件名不对。v26.x 要求 `main.lua`，不是 `init.lua`。

**检查**: `ls plugins/xxx.yazi/main.lua`

### Q: 快捷键配置不生效

**原因 1**: 使用了旧的 `[[manager.prepend_keymap]]` 写法。
**修复**: 改为 `[[mgr.prepend_keymap]]`。

**原因 2**: 使用了 `[[mgr.keymap]]` 替换了所有默认键位。
**修复**: 改为 `[[mgr.prepend_keymap]]`，除非确实要替换全部。

### Q: 预览不换行

**原因**: `wrap` 写成了布尔值 `true`。
**修复**: `wrap = "yes"`（字符串）。

### Q: ratio 配置被忽略

**原因**: 使用了旧的 `[manager]` 节名。
**修复**: 改为 `[mgr]`。

### Q: preview_widget 不显示内容

**原因**: 缺少 `:area(job.area)` 调用。
**修复**: `ui.Text(content):area(job.area)`

### Q: 布局切换后 yazi 状态丢失

**说明**: 这是预期行为。Poltertty 通过销毁并重建 surface 来切换布局，因为 yazi 不支持运行时动态修改 ratio。`YaziSurfaceStore.cycleRatio()` 会 `removeValue` 旧 surface，下次访问时 lazy 创建新实例。

### Q: dev 构建时配置文件不同步

**检查**: 确保 `make dev` 或 Xcode build phase 会将 `macos/Resources/yazi-config/` 拷贝到 Debug bundle。相关 commit: `857fdaf3d fix(build): dev 构建自动同步 yazi-config 到 Debug bundle`。

### Q: Command:arg() 传参报错

**原因**: 使用了旧的 `Command:args()` API。
**修复**: 改为 `Command:arg()`，支持单个字符串或 table。
