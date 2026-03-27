# UI/UX 设计原则

Poltertty 所有 UI 开发必须遵守以下原则。

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
