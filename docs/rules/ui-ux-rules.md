# UI/UX 设计原则

Poltertty 所有 UI 开发必须遵守以下原则。

---

## 设计工具：Impeccable 设计系统

所有 UI/UX 设计与审查工作**必须优先使用 Impeccable 设计 skill**，而非直接动手修改代码。

### 工作流程

1. **分析阶段**：使用 `/audit` 或 `/critique` 先评估现状，再确定改进方向
2. **设计阶段**：根据需求选择对应 skill（见下表）进行设计
3. **复杂决策**：涉及整体方向或多个方案权衡时，使用 `superpowers:brainstorming` 的可视化伴侣进行交互
4. **实现阶段**：按设计结论编写代码

### Impeccable 21 个设计 Skill 索引

| Skill | 命令 | 适用场景 |
|-------|------|---------|
| Polish | `/polish` | 整体 UI 优化，综合提升质量 |
| Audit | `/audit` | 审查设计问题并量化评分 |
| Critique | `/critique` | 批判性设计反馈，找出根本问题 |
| Typeset | `/typeset` | 排版优化：字体、行高、字间距 |
| Colorize | `/colorize` | 色彩系统优化，增强视觉层次 |
| Animate | `/animate` | 添加动效与过渡 |
| Overdrive | `/overdrive` | 极致视觉强化，突破常规 |
| Bolder | `/bolder` | 加强视觉力度，增强存在感 |
| Quieter | `/quieter` | 减弱视觉噪音，降低干扰 |
| Arrange | `/arrange` | 布局与间距优化 |
| Distill | `/distill` | 简化设计，去除冗余 |
| Harden | `/harden` | 强化设计一致性与健壮性 |
| Normalize | `/normalize` | 规范化设计，对齐设计系统 |
| Clarify | `/clarify` | 提升文案与界面清晰度 |
| Adapt | `/adapt` | 适配不同屏幕/主题/场景 |
| Extract | `/extract` | 提取并整合可复用设计元素 |
| Delight | `/delight` | 添加细节惊喜与情感化设计 |
| Optimize | `/optimize` | 性能与可用性优化 |
| Onboard | `/onboard` | 新用户引导与 onboarding 流程优化 |
| Frontend Design | `/frontend-design` | 前端设计模式与组件架构 |
| Teach Impeccable | `/teach-impeccable` | 学习设计词汇与方法论 |

### 何时使用 `superpowers:brainstorming`

以下情况**必须**先通过 brainstorming 可视化伴侣进行方案探讨，再进入实现：

- 新功能的整体 UI 结构尚未确定
- 存在 2 个以上设计方案需要权衡
- 涉及全局性改动（如主题系统、导航结构、信息架构）
- 用户明确要求讨论而非直接实现

---

## 键盘优先

所有 UI 功能必须考虑键盘操作可达性，不能只依赖鼠标/点击：

- **弹出层**：popover、sheet、overlay 等弹出层必须支持 `Esc` 关闭
- **列表 / 树**：列表、树形控件必须支持方向键导航和回车展开/确认
- **常用操作**：频繁使用的操作需提供快捷键，并在 tooltip 或帮助面板中注明
- **帮助面板**：新增快捷键后同步更新 `ShortcutHelpView` 的条目

## UI 文本语言规范

UI 文本**优先使用英文**。同一上下文（toolbar、列头、菜单、卡片等）内语言必须统一，禁止中英混排。

### 原则

- **英文优先**：按钮、标签、菜单项、列头、提示文字等一律使用英文
- **同一上下文统一**：同一组件内所有文本使用同一种语言

### 例外：允许使用中文的情形

仅以下情况可使用中文：

- 用户自行输入/命名的内容（工作区名称、文件路径等）
- 有明确产品决策需要中文的特定页面（需在代码注释中注明原因）

### 示例

```swift
// ❌ 中英混排
Text("AGENT")
Text("状态")
Text("TOKEN / 费用")

// ✅ 统一英文
Text("AGENT")
Text("STATUS")
Text("TOKEN / COST")
```

---

## SwiftUI 填充父容器：frame 传播链

面板类视图（用于 `HSplitView`、`VSplitView` 或其他全高/全宽容器的子视图）必须在**每一层**确保 frame 向上传播，否则父容器会将内容居中。

### 规则

- 面板 `body` 的**根视图**（通常是 `VStack` 或 `HStack`）必须加 `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)`
- `ScrollView` 内容的 VStack/HStack **不应**加 `maxHeight: .infinity`（ScrollView 提案高度为 unbounded，该修饰符无意义）；应把 frame 加在 **ScrollView 本身**
- 重构宿主容器结构后，必须从外到内检查整条 frame 传播链

### 示例

```swift
// ❌ 错误：外层 VStack 无 frame，HSplitView 将其垂直居中
var body: some View {
    VStack(alignment: .leading, spacing: 0) {
        ScrollView([.horizontal, .vertical]) {
            VStack { ... }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) // 内层加了也没用
        }
    }
}

// ✅ 正确：每层都有 frame
var body: some View {
    VStack(alignment: .leading, spacing: 0) {
        ScrollView([.horizontal, .vertical]) {
            VStack { ... }
                .frame(maxWidth: .infinity, alignment: .leading) // 内层只需 maxWidth
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) // ScrollView 本身填满
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) // 根视图填满
}
```

---

## 固定尺寸面板的内容溢出

固定高度或固定宽度的面板，内容超出时必须使用 `ScrollView` 处理，禁止用 `.clipped()` 截断内容。
