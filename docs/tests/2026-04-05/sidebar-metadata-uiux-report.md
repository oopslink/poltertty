# Sidebar Workspace Metadata UI/UX 测试报告

**日期:** 2026-04-05  
**分支:** feature/sidebar-workspace-metadata  
**构建:** Debug (xcodebuild)

---

## 自动化验证结果

### ✅ 构建验证
- `xcodebuild -target Ghostty -configuration Debug -arch arm64` → **BUILD SUCCEEDED**
- 无编译错误

### ✅ 应用启动
- Poltertty.app 成功启动，无崩溃

### ✅ 展开状态侧边栏渲染
- 截图: `sidebar-expanded.png`
- 侧边栏正常渲染，所有 workspace 条目显示
- **无数据时徽标行不显示（符合设计：`if !metadata.listeningPorts.isEmpty || metadata.prStatus != nil || metadata.agentState != .none`）**
- workspace 路径行正常显示

---

## 手动测试清单（需要实际端口/PR/Agent 数据）

### 展开状态（方案 A）
- [ ] 端口徽标：蓝色系，monospaced 字体，格式 `:3000` — 需启动监听端口服务后验证
- [ ] PR 徽标：Open=绿色背景 `#N Open`，Draft=灰色 `#N Draft` — 需在有 PR 的 workspace 目录验证
- [ ] Agent 徽标：黄色脉冲点 + `Working`；灰色点 + `Idle` — 需启动 agent 后验证
- [ ] 无数据时徽标行完全不显示 ✅（已通过截图验证）
- [ ] 最多 3 个端口徽标，超出显示 `+N` — 需 4+ 个监听端口验证

### 折叠状态（方案 X）
- [ ] 图标下方三点行高度 8px，间距 4px — 需手动点击折叠按钮后截图
- [ ] 左=蓝色（有端口时），中=黄色脉冲（working）/灰（idle），右=绿（open）/灰（draft）
- [ ] 无数据的点透明（占位不显示）
- [ ] 已有红色未读角标在右上角不受影响

---

## 代码结构验证

| 组件 | 文件 | 状态 |
|------|------|------|
| WorkspaceMetadata 类型 | `Metadata/WorkspaceMetadata.swift` | ✅ |
| PortScanner + 测试 | `Metadata/PortScanner.swift` | ✅ |
| PRStatusFetcher + 测试 | `Metadata/PRStatusFetcher.swift` | ✅ |
| WorkspaceMetadataStore | `Metadata/WorkspaceMetadataStore.swift` | ✅ |
| ExpandedWorkspaceItem 徽标行 | `WorkspaceSidebar.swift` | ✅ |
| CollapsedWorkspaceIcon 三点行 | `WorkspaceSidebar.swift` | ✅ |
| 接线 + 通知 | `WorkspaceSidebar.swift` + `PolterttyRootView.swift` | ✅ |
