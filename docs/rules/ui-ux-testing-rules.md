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
# 通过 Ctrl API 确认 workspace 已加载
curl -s http://localhost:<PORT>/v1/health
curl -s -X POST http://localhost:<PORT>/v1/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_instance_info","arguments":{}}}' \
  | python3 -c "import sys,json; print(json.dumps(json.loads(json.load(sys.stdin)['result']['content'][0]['text']), indent=2))"
```

---

## 2. 截图

### 规则

**禁止**使用 Ctrl API 的 `capture_screenshot`（已移除）。
原因：该接口使用 `bitmapImageRepForCachingDisplay` 进行 CPU 渲染，无法捕获 Metal/GPU 渲染的终端内容区，结果是白图。

**必须**使用系统 `screencapture` 命令。

### 标准截图流程

```bash
# 1. 将 App 带到前台
osascript -e 'tell application "System Events" to tell process "ghostty" to set frontmost to true'
sleep 0.5   # 等待渲染稳定

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

---

## 3. 打开面板

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

| 面板 | 菜单项名 | 快捷键（参考） |
|------|---------|--------------|
| 文件浏览器 | `Toggle File Browser` | Cmd+\ |
| Git 面板 | `Toggle Git Tab` | Cmd+Shift+G |
| 工作区侧边栏 | `Toggle Sidebar` | Cmd+B |

### Bash 内联写法

```bash
# 打开文件浏览器
osascript << 'EOF'
tell application "System Events"
    tell process "ghostty"
        set frontmost to true
        delay 0.5
        click menu item "Toggle File Browser" of menu "Workspace" of menu bar 1
    end tell
end tell
EOF
sleep 1 && screencapture -x /tmp/poltertty_filebrowser.png

# 打开 Git 面板
osascript << 'EOF'
tell application "System Events"
    tell process "ghostty"
        set frontmost to true
        delay 0.5
        click menu item "Toggle Git Tab" of menu "Workspace" of menu bar 1
    end tell
end tell
EOF
sleep 1 && screencapture -x /tmp/poltertty_git.png
```

---

## 4. 验证检查清单

每次 UI/UX 改动后，截图并逐条确认：

### 4.1 Tab Bar 选中状态

裁切 tab bar 区域（y=140~230 @2x），检查：

- [ ] 活跃 tab 图标颜色为 `controlAccentColor`（蓝色）
- [ ] 活跃 tab 底部有 2px accent 色指示条
- [ ] 非活跃 tab 图标为 secondary 色（灰）
- [ ] badge 数字清晰可见（橙色圆角，≥10pt）

### 4.2 Stage/Unstage 按钮

裁切 changes 列表区域，检查：

- [ ] 非 hover 状态：`⊕`（stage）和 `↩`（discard）按钮极淡但存在
- [ ] 使用 `arrow.uturn.backward` 图标而非 `xmark.circle`（后者歧义大）
- [ ] hover 状态需手动交互验证（静态截图只能确认非 hover 态）

### 4.3 Worktree Selector

- [ ] 只出现在 tab bar 一处，不在 Files/Git 各自面板内重复出现
- [ ] 多 worktree 时显示下拉菜单；单 worktree 时只显示 branch 名称（无下拉）

### 4.4 底部状态栏

裁切底部区域（y=1900~1964 @2x），检查：

- [ ] 左侧显示 workspace 根目录路径（folder 图标 + 路径文字）
- [ ] 文字 opacity 足够清晰（≥0.8，非 0.6）
- [ ] 右侧显示 branch 名称和变更计数

### 4.5 字体尺寸

- [ ] badge 计数（section header、commit 数、file status）最小 10pt
- [ ] chevron 图标最小 9pt
- [ ] 正文内容（文件名、提交信息）11pt

### 4.6 空状态

切换到非 git 目录触发空状态测试：

```bash
# 在 Ctrl API 中或通过 App 打开一个非 git 目录的 workspace
# 然后截图检查：
```

- [ ] 文件浏览器空状态：显示图标 + 说明文字 + 操作引导
- [ ] Git 面板非 git 仓库：显示 `Not a git repository` + `git init` 提示 + 路径

---

## 5. 完整测试脚本示例

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

---

## 6. 常见问题

| 问题 | 原因 | 解决方法 |
|------|------|---------|
| 截图全白 | 使用了 CPU 渲染截图（旧 `capture_screenshot`） | 改用 `screencapture` |
| 快捷键触发了系统功能 | `keystroke` 被系统拦截 | 改用 `click menu item` |
| App 未在前台，截图错误 | `set frontmost to true` 未生效 | 增加 `delay 0.5` 等待渲染 |
| `make dev` 架构报错 | zig build 默认 universal，arm64 机器链接 x86_64 | `scripts/build.sh` 已修复为 `-Dxcframework-target=native` |
| Ctrl API 端口不固定 | 每次启动随机分配 | 每次通过 `lsof -i -n -P \| grep ghostty \| grep LISTEN` 获取 |
