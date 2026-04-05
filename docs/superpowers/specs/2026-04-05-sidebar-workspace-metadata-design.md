# 侧边栏 Workspace 元数据增强设计

**日期**：2026-04-05  
**状态**：已批准

---

## 目标

在侧边栏不切换 Workspace 的情况下，直接感知每个 Workspace 的运行状态：监听端口、PR 状态、Agent 活跃情况。

---

## 数据层

### 新增类型

```swift
struct WorkspaceMetadata {
    var listeningPorts: [Int] = []   // 当前监听的 TCP 端口列表
    var prStatus: PRStatus? = nil    // nil = 无关联 PR
    var agentState: AgentState = .none
}

enum PRStatus {
    case open(number: Int)
    case draft(number: Int)
    case merged(number: Int)
}

enum AgentState {
    case none     // 无 Agent session
    case idle     // 有 session，空闲
    case working  // 有 session，运行中
}
```

### WorkspaceMetadataStore

`@MainActor ObservableObject` 单例，统一管理三条元数据更新通道。

```swift
@Published var metadata: [UUID: WorkspaceMetadata] = [:]
```

**端口通道（5s 轮询）**

1. 后台运行 `lsof -iTCP -sTCP:LISTEN -Pn`，解析 PID → 端口列表
2. 对每个 PID 查 `lsof -p <pid> -d cwd -F n`，得到进程工作目录
3. 按前缀匹配 workspace `rootDir`，将端口归属到对应 workspace
4. 无法归属的端口丢弃

**PR 通道（60s TTL）**

1. workspace 首次激活时触发查询
2. 后台运行 `gh pr status --json number,state,isDraft`，按 workspace `rootDir` 执行
3. 解析结果映射到 `PRStatus`；`gh` 不存在或仓库无 PR 时静默留 `nil`
4. 60s 后自动重新查询

**Agent 通道（订阅）**

订阅 `ExternalSessionDiscovery.shared.sessions`，按 `rootDirectory` 前缀匹配 workspace，映射到：
- session 存在且状态为 working → `.working`
- session 存在且状态为 idle/done → `.idle`
- 无 session → `.none`

所有后台 I/O 在 `Task.detached` 中运行，结果通过 `await MainActor.run` 写回。

---

## UI 层

### 展开状态：ExpandedWorkspaceItem（方案 A）

在路径行下方新增徽标行，仅在有数据时渲染（无数据不占高度）：

```
[名称]  poltertty  ●
[路径]  ~/works/codes/poltertty
[徽标]  :5173  #152 Open  ⬤ Working
```

**徽标样式**

| 类型 | 颜色 | 内容示例 |
|------|------|---------|
| 端口 | 蓝色系 | `:5173` `:8080` |
| PR Open | 绿色系 | `#152 Open` |
| PR Draft | 灰色系 | `#89 Draft` |
| PR Merged | 紫色系 | `#77 Merged` |
| Agent Working | 黄色+脉冲点 | `⬤ Working` |
| Agent Idle | 灰色 | `⬤ Idle` |

**端口点击行为**：调用 `BrowserSurfaceStore` 在 Browser Panel 中打开 `http://localhost:<port>`。

**多端口截断**：超过 3 个时显示 `+N`。

**参数变更**：
```swift
var metadata: WorkspaceMetadata = .init()  // 默认空值，向后兼容
```

### 折叠状态：CollapsedWorkspaceIcon（方案 X）

图标下方新增固定 3 点行（5×5px），无数据时对应点透明：

```
[PO]   ← 32×32 图标
 ● ● ●  ← 左=端口、中=agent、右=PR
```

| 位置 | 含义 | 颜色 |
|------|------|------|
| 左点 | 有监听端口 | 蓝色 |
| 中点 | Agent Working | 黄色+脉冲 |
| 中点 | Agent Idle | 灰色 |
| 右点 | PR Open | 绿色 |
| 右点 | PR Draft | 灰色 |

点行占高 8px，icon 区总高度 32 → 40px，避免与右上角未读角标叠压。

### WorkspaceSidebar

```swift
@ObservedObject var metadataStore = WorkspaceMetadataStore.shared
```

向 `ExpandedWorkspaceItem` 和 `CollapsedWorkspaceIcon` 传入：
```swift
metadata: metadataStore.metadata[workspace.id] ?? .init()
```

---

## 边界处理

| 情形 | 处理方式 |
|------|---------|
| `gh` CLI 不存在 | 静默忽略，PR 徽标留空 |
| rootDir 无 git 仓库 | 同上 |
| 端口无法归属 workspace | 丢弃，不显示 |
| Workspace 关闭 | 取消对应轮询 Task，清空 metadata |
| lsof 权限不足 | 只扫描当前用户进程，足够开发场景 |
| 超过 3 个端口 | 显示前 3 个 + `+N` |

---

## 测试范围

- `WorkspaceMetadataStore` 单元测试：mock `lsof` / `gh` 输出，验证解析与归属逻辑
- `ExternalSessionDiscovery` → `AgentState` 映射逻辑单元测试
- SwiftUI Preview：`ExpandedWorkspaceItem` / `CollapsedWorkspaceIcon` 覆盖空/满数据两种状态

---

## 不在本次范围内

- 折叠状态点击端口点（tooltip 提示端口号即可）
- 通知系统集成（已有独立 AgentNotificationStore）
- OSC 序列支持（2.4 独立功能）
