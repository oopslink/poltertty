# Pane Indicator UI 优化设计

**日期：** 2026-04-02  
**分支：** feat/pane-indicator-polish  
**状态：** 已审批，待实现

## 背景

双击 Command 激活 pane selector 后，每个 pane 中央会显示一张浮动信息卡片（`PaneOverlayCardView`）。现有实现存在以下问题：

- 卡片字号小（11px），视觉权重不足
- 无遮罩层，终端内容与卡片争夺注意力
- `annotation` 和 `index` 未作为主角突出显示
- `gitBranch` 始终为 `nil`（已知未实现，本次不处理）
- `PaneBadgeView` 定义了但从未被渲染（死代码，本次清理）

## 目标

- **首要信息**：annotation（pane 备注名）和 index（跳转按键）最醒目
- **次要信息**：进程名、路径、时长，作为辅助参考
- 所有 pane 视觉上**一视同仁**，无聚焦/非聚焦区分

## 设计方案

### 1. 遮罩层

在 `TerminalSplitLeafContainer` 中，pane selector 激活时为每个 pane 叠加统一遮罩：

- 颜色：`Color.black.opacity(0.52)`
- 所有 pane 相同，无例外
- 与卡片同步 animate（`easeInOut(duration: 0.15)`）

### 2. 卡片布局（`PaneOverlayCardView`）

#### 有 annotation 时

```
┌──────────────────────────┐
│       poltertty          │  ← 16px, weight 800, 白色（主角）
│        ────              │  ← 细分隔线
│         [0]              │  ← key badge，30×30，accent 色
│  nvim · ~/proj · 2h30m  │  ← 10px，低对比度（辅助）
└──────────────────────────┘
```

#### 无 annotation 时

```
┌──────────────────────────┐
│          [0]             │  ← key badge 放大至 44×44，22px（主角）
│  python3 · ~/tmp · 15m  │  ← 10px，低对比度（辅助）
└──────────────────────────┘
```

### 3. 视觉参数

| 元素 | 规格 |
|------|------|
| 卡片背景 | `rgba(18,18,22,0.96)` + `.ultraThinMaterial` blur |
| 卡片边框 | `Color.primary.opacity(0.09)`，1px |
| 卡片圆角 | 14pt |
| 卡片阴影 | `radius: 24, y: 4, opacity: 0.7` |
| annotation 字号 | 16px，weight 800，white |
| 分隔线 | 28pt 宽，`Color.primary.opacity(0.1)` |
| key badge（有 annotation）| 30×30，圆角 7pt，16px weight 900 |
| key badge（无 annotation）| 44×44，圆角 10pt，22px weight 900 |
| key badge 颜色 | `Color.accentColor`，背景 opacity 0.15，边框 opacity 0.45 |
| 辅助信息 | 10px monospaced，`Color.secondary`（`.tertiary` 亦可）|
| 辅助信息内容 | `进程名 · 路径（~ 替换 $HOME） · 时长` |
| 出现动画 | `opacity + scale(0.95→1.0)`，0.15s easeInOut |
| 消失动画 | 与出现相同，由 `isActive` 变化驱动 |

### 4. 辅助信息格式

```
进程名 · ~/缩写路径 · 时长
```

- shell 空闲时（foregroundProcess == nil）：只显示 shell 名
- 路径：`$HOME` → `~`
- 时长 < 1m：不显示时长（沿用现有 `formatDuration` 逻辑）

## 变更范围

| 文件 | 变更类型 | 说明 |
|------|----------|------|
| `Features/Splits/PaneOverlayCardView.swift` | 重写 | 新卡片布局 |
| `Features/Splits/TerminalSplitTreeView.swift` | 修改 | 在 `TerminalSplitLeafContainer` 加遮罩层 |
| `Features/Splits/PaneBadgeView.swift` | 删除 | 死代码，从未被渲染 |

`PaneSelectorViewModel.swift` 无需改动。

## 不在本次范围内

- Git 分支信息显示（`gitBranch` 实现）
- 聚焦 pane 特殊高亮
- annotation 编辑 UI 改动
