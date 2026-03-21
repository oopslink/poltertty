# TODO: OSC 9/99/777 通知桥接调研

## 背景

通知中心目前有两个信号源（HTTP Hook + 外部会话发现）。OSC 序列（9/99/777）是终端通知的标准机制，接入后可以让任意终端程序通过 OSC 发送通知。

## 需要调研的问题

1. **Ghostty OSC 解析位置**：OSC 解析在 `src/terminal/osc.zig` 中，Swift 层能否通过现有 `ghostty_surface_*` C API 拿到 OSC 事件？
2. **桥接层改造成本**：如果需要在 Zig 层加 callback，会产生多大的上游 rebase 冲突面？
3. **替代方案**：是否可以在 PTY 读取层拦截 ESC 序列，在 Swift 侧解析（绕过 Zig 层）？

## 相关 OSC 代码

- 9: 系统通知（iTerm2 / ConEmu）
- 99: 自定义通知（带 id/title/body）
- 777: 通知（rxvt-unicode 风格）

## 风险

- 修改 Zig 层会增加上游 rebase 冲突面
- Ghostty 上游可能自身添加 OSC 通知支持，需关注上游 roadmap
