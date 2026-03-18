// macos/Sources/Features/Agent/Monitor/SubagentOutputContent.swift
import SwiftUI

struct SubagentOutputContent: View {
    let session: AgentSession
    let subagent: SubagentInfo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // ── Prompt 区 ──────────────────────────────────
                if let prompt = subagent.prompt, !prompt.isEmpty {
                    section(title: "PROMPT") {
                        Text(prompt)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // ── Output 区 ──────────────────────────────────
                section(title: "OUTPUT") {
                    switch subagent.state {
                    case .error(let msg):
                        errorView(msg)
                    case .done:
                        outputOrFallback
                    case .working, .launching:
                        runningView
                    default:
                        Text("等待输出…").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Section wrapper

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            content()
        }
    }

    // MARK: - Output states

    private var outputOrFallback: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let output = subagent.output, !output.isEmpty {
                Text(output)
                    .font(.system(size: 10))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Label("已完成", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(hex: "#4caf50") ?? .green)
                completedCallsView
            }
        }
    }

    private func errorView(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("中断于错误", systemImage: "xmark.circle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color(hex: "#f44336") ?? .red)
            Text(msg)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(hex: "#f44336") ?? .red)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "#1e0f0f") ?? .clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            completedCallsView
        }
    }

    private var runningView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("运行中", systemImage: "bolt.circle.fill")
                .font(.system(size: 10)).foregroundStyle(Color(hex: "#ff9800") ?? .orange)
            completedCallsView
        }
    }

    @ViewBuilder
    private var completedCallsView: some View {
        let done = subagent.toolCalls.filter { $0.isDone }
        let total = subagent.toolCalls.count
        if !done.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("工具调用 (\(done.count)/\(total))")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                ForEach(done) { call in
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 8)).foregroundStyle(Color(hex: "#4caf50") ?? .green)
                        Text(call.toolName).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                if total > done.count {
                    HStack(spacing: 4) {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 8)).foregroundStyle(.orange)
                        Text("进行中: \(total - done.count) 个").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}
