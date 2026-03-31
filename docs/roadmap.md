# Poltertty 开发路线图

> 基于竞品分析（2025 年 3 月），聚焦"Ghostty 原生体验 + Workspace 管理 + AI Agent 协作层"定位。

---

## 总览

```
Phase 1 ──── Session 持久化 · Yazi 集成 · Worktree 绑定
Phase 2 ──── Agent 调度台 · Ctrl API 扩展
Phase 3 ──── Layout-as-Code · Quick Terminal 融合
```

---

## Phase 1：核心基础

### 1.1 Session 持久化与恢复

**价值**：Ghostty 社区 #1 未满足需求（561 upvote），tmux 用户迁移的最后心理障碍。

**功能范围**：
- 每个 Workspace 在关闭时自动保存快照：pane 布局、工作目录、tab 名称
- App 重启后提示恢复上次 Session，支持选择性恢复
- Workspace 创建表单新增"从快照创建"选项
- 快速切换器中显示每个 Workspace 的上次保存时间与活跃 pane 数

**技术基础**：`saveSnapshot`/`RestoreView` 已存在，需扩展为持久化到磁盘的完整 layout 序列化。

**成功标准**：关闭并重开 App，工作目录与 pane 布局完整恢复，无需任何手动操作。

---

### 1.2 Yazi 替换内置文件管理器

**价值**：Yazi 是 2024-2025 年增长最快的 TUI 文件管理器（Rust，Ghostty/Kitty 图像协议支持），社区主流偏向"终端模拟器作为平台，文件管理交给专业工具"。当前内置文件浏览器维护成本高且功能难以追上专业工具。

**功能范围**：
- **启动方式**：点击侧边栏 File Browser 图标，在右侧 panel 中打开 yazi，而非原生 SwiftUI 树
- **图像预览**：Ghostty 已支持 Kitty 图像协议，yazi 图片预览开箱即用
- **双向联动**：
  - yazi 中打开文件 → 在新 tab 中启动 `$EDITOR`
  - Workspace 切换时，yazi 自动 `cd` 到对应 workspace 目录（通过 `ya pub-sub` 事件）
- **快捷键**：侧边栏 File Browser 按钮 / 可配置快捷键 直接聚焦到 yazi pane
- **降级处理**：若系统未安装 yazi，面板显示安装引导，提供 `brew install yazi` 一键提示

**迁移策略**：
- 移除 `FileBrowser/` 目录下的 SwiftUI 实现（`FileBrowserPanel`、`FileBrowserViewModel`、`FileNodeRow` 等）
- 保留 `GitStatusService`（Git Panel 仍需使用）
- 保留 `SyntaxHighlightView`（可复用于 Git diff 预览）

**成功标准**：侧边栏 File Browser 入口打开 yazi，图片预览正常，切换 Workspace 时 yazi 目录自动跟随。

---

### 1.3 Workspace ↔ Git Worktree 绑定

**价值**：多 Agent 并行工作流的基础设施——每个 Agent 在独立 worktree，Poltertty 提供跨 worktree 的统一视图，这是 lazygit 无法覆盖的场景。

**功能范围**：
- Workspace 创建时新增"绑定 Git Worktree"选项：选择已有 worktree 或新建
- 侧边栏 Workspace 条目右侧显示 branch 名 + dirty 状态指示点（红点 = 有未提交修改）
- Git Panel 新增"所有 Workspace 变更汇总"标签页：一行一个 worktree，展示变更文件数与 branch
- 切换 Workspace 时，yazi（1.2 落地后）自动 cd 到该 worktree 根目录

**成功标准**：同时运行三个 AI Agent 于三个 worktree，Poltertty 侧边栏能一眼看出哪个有变更、哪个 branch 落后于 main。

---

## Phase 2：Agent 协作层

### 2.1 Agent Monitor → 多 Agent 调度台

**价值**：2025 年开发者最大痛点——管理并行 AI Agent 时没有统一视图（Claude Squad、Agent Deck 等外部工具的出现即是证明）。Poltertty 在终端内做比外部工具更有整合优势。

**功能范围**：
- 侧边栏新增 **Agents** 区块，列出所有已注册 Agent session，每条显示：
  - Agent 名称（可自定义标签）
  - 状态徽标：`运行中` / `等待输入` / `已完成` / `出错`
  - 所属 Workspace / Worktree
- 点击 Agent 条目 → 立即聚焦到对应 tab/pane
- Agent 任务完成时触发 macOS 通知（标题 = Agent 标签，内容 = 最后一行输出）
- 支持在调度台中发送快捷指令（如"继续"/"中止"）到对应 pane

**Ctrl API 配合**（见 2.2）：Agent 通过 `set_agent_label` 自报状态，Poltertty 订阅后更新 UI。

**成功标准**：同时跑 5 个 Claude Code session，不打开任何一个 tab，能从 Agents 面板知道每个的进度并在出错时立即定位。

---

### 2.2 Ctrl API 扩展

**价值**：巩固 Poltertty 作为 AI Agent 协作层的护城河，让 Agent 能以编程方式操控完整的开发环境。

**现有接口**：`ping`、`new_tab`、`send_text`、`list_panes`、`focus_pane`、`split_pane`

**新增接口**：

| 接口 | 功能 |
|------|------|
| `create_workspace` | 创建新 Workspace，可指定名称、目录、绑定 worktree |
| `set_agent_label` | Agent 设置自身标签与状态（供调度台展示） |
| `get_workspace_state` | 获取完整状态快照（布局 + 目录 + Agent 列表） |
| `notify` | 向用户发送带标题的 macOS 通知 |
| `open_in_file_browser` | 在 yazi pane 中定位到指定路径 |
| SSE 事件：`agent_status_changed` | 订阅 Agent 状态变更推送 |
| SSE 事件：`workspace_switched` | 订阅 Workspace 切换事件 |

**成功标准**：外部 Agent 可通过 MCP 工具完整创建 Workspace、绑定 worktree、注册自身标签、完成后通知用户——无需用户手动操作任何 UI。

---

## Phase 3：Power User 与体验打磨

### 3.1 Layout-as-Code

**价值**：Zellij 最受称道的功能，被 tmux 迁移者反复提及；Kitty 0.43 也刚加入。给 power user 提供自动化入口。

**功能范围**：
- 支持用 YAML/TOML 文件描述 Workspace 布局（tabs、splits、目录、初始命令）
- CLI 参数：`Poltertty --workspace-file ./my-project.yaml`
- 内置布局模板（`ai-parallel`：3 个并排 worktree + 1 个 Git Panel）
- Ctrl API：`load_workspace_file` 接口，Agent 可动态加载布局

**布局文件示例**：
```yaml
name: my-api-project
worktree: ~/projects/api
tabs:
  - name: server
    dir: ~/projects/api
    command: cargo watch
  - name: agent
    split: vertical
    panes:
      - dir: ~/projects/api
      - dir: ~/projects/api/.worktrees/feat-auth
```

**成功标准**：一条命令从零启动包含 3 个 tab + 预设目录的完整开发环境。

---

### 3.2 Quick Terminal + Workspace 切换融合

**价值**：Ghostty Quick Terminal（悬浮终端）是最受好评的功能之一；让它能直接看到 Workspace 状态，是独特的 macOS-native 体验。

**功能范围**：
- Quick Terminal 底部常驻 Workspace 切换条（紧凑版，仅显示名称 + 状态点）
- `Cmd+数字` 在 Quick Terminal 中直接切换到对应 Workspace
- Quick Terminal 中可查看 Agents 面板（只读，不操作）

**成功标准**：不离开当前 App，通过 Quick Terminal 快捷键切换到目标 Workspace 并立即开始工作。

---

## 不在路线图内

以下方向经竞品分析明确排除：

| 方向 | 排除原因 |
|------|---------|
| 内置 AI（云端） | Warp 最大教训：终端数据上传红线；Poltertty 定位是 Agent 控制台，不是 AI 终端 |
| 全功能 Git 客户端 | lazygit 生态成熟，Git Panel 只做"Agent 变更 review 辅助" |
| 订阅制/账号体系 | 用户对终端类产品的账号要求极度反感 |

---

## 依赖关系

```
1.2 Yazi 集成
    └── 1.3 Worktree 绑定（yazi cd 跟随需要 1.2 先落地）
            └── 2.1 Agent 调度台（跨 worktree 状态需要 1.3 数据）

1.1 Session 持久化（独立，可并行）

2.2 Ctrl API 扩展（与 2.1 并行，互为前提）

3.1 Layout-as-Code（依赖 1.1 的序列化方案）
3.2 Quick Terminal 融合（依赖 2.1 的 Agents 面板）
```
