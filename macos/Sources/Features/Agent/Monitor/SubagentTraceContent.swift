// macos/Sources/Features/Agent/Monitor/SubagentTraceContent.swift
import SwiftUI

struct SubagentTraceContent: View {
    let subagent: SubagentInfo
    @State private var tick = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if subagent.toolCalls.isEmpty {
                    if subagent.isHistorical {
                        // 历史记录：toolCalls 为空是因为持久化不保留详情（isHistorical 标记由 toAgentSession() 设置）
                        Text("历史记录不保留工具调用详情")
                            .font(.system(size: 10)).foregroundStyle(.tertiary).padding(12)
                        if let output = subagent.output {
                            Text("最终输出：")
                                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                            Text(output)
                                .font(.system(size: 10)).foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .padding(.horizontal, 12).padding(.top, 4)
                        }
                    } else {
                        Text(subagent.state.isActive ? "等待工具调用…" : "无工具调用记录")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                            .padding(12)
                    }
                } else {
                    Text("Tool calls (\(subagent.toolCalls.count))")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
                    ForEach(Array(subagent.toolCalls.enumerated()), id: \.element.id) { idx, call in
                        callRow(call, isLast: idx == subagent.toolCalls.count - 1)
                    }
                }
            }
        }
        .onReceive(timer) { t in if subagent.state.isActive { tick = t } }
    }

    private func callRow(_ call: ToolCallRecord, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Spacer().frame(width: 12)
                treeConnector(last: isLast && call.toolInput == nil)
                if call.isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9)).foregroundStyle(Color(hex: "#4caf50") ?? .green)
                } else {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                }
                Text(call.toolName)
                    .font(.system(size: 10, weight: call.isDone ? .regular : .medium))
                    .foregroundStyle(call.isDone ? Color.secondary : Color.primary)
                Spacer()
                Text(durationFor(call))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(call.isDone ? Color.secondary.opacity(0.6) : Color.orange)
            }
            .frame(height: 18)
            // tool input 参数展示
            if let input = call.toolInput, !input.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    Spacer().frame(width: 26)  // 与 toolName 对齐
                    Text(input)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .lineLimit(6)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(Color(.textBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .padding(.bottom, 4)
            }
        }
        .padding(.trailing, 12)
    }

    private func treeConnector(last: Bool) -> some View {
        Canvas { ctx, size in
            var path = Path()
            let mid = size.width / 2
            path.move(to: .init(x: mid, y: 0))
            path.addLine(to: .init(x: mid, y: last ? size.height/2 : size.height))
            path.move(to: .init(x: mid, y: size.height/2))
            path.addLine(to: .init(x: size.width, y: size.height/2))
            ctx.stroke(path, with: .color(.secondary.opacity(0.35)), lineWidth: 1)
        }
        .frame(width: 10, height: 18)
    }

    private func durationFor(_ call: ToolCallRecord) -> String {
        guard call.isDone else {
            let s = max(0, Int(tick.timeIntervalSince(call.startedAt)))
            return s < 60 ? "\(s)s" : "\(s/60)m\(s%60)s"
        }
        let calls = subagent.toolCalls
        guard let idx = calls.firstIndex(where: { $0.id == call.id }) else { return "" }
        let end: Date = idx + 1 < calls.count ? calls[idx+1].startedAt : (subagent.finishedAt ?? Date())
        let s = max(0, Int(end.timeIntervalSince(call.startedAt)))
        return s < 60 ? "\(s)s" : "\(s/60)m\(s%60)s"
    }
}
