// macos/Sources/Features/Agent/Monitor/AgentGraphView.swift
import SwiftUI

// MARK: - 单节点视图

struct AgentGraphNode: View {
    let name: String
    let state: AgentState
    let elapsed: String
    let toolCount: Int
    let width: CGFloat
    let isSession: Bool           // session 节点不可点击，背景色不同
    let onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    AgentStateDot(state: state)
                    Text(name)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                HStack(spacing: 4) {
                    Text(elapsed)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    if toolCount > 0 {
                        Label("\(toolCount)", systemImage: "wrench.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(width: width, height: 52, alignment: .leading)
            .background(isSession
                ? Color(.controlColor).opacity(0.5)
                : Color(.controlColor).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .disabled(onTap == nil)
    }
}

// MARK: - 图形容器

struct AgentGraphView: View {
    let session: AgentSession
    let tick: Date
    let onSubagentTap: (SubagentInfo) -> Void

    // 布局常量
    private let sessionNodeW: CGFloat = 100
    private let subNodeW: CGFloat = 110
    private let nodeH: CGFloat = 52
    private let gap: CGFloat = 8
    private let hGap: CGFloat = 20   // session 右边 → 垂直干线；垂直干线 → subagent 左边

    // subagents 按 startedAt 排序
    private var subagents: [SubagentInfo] {
        Array(session.subagents.values).sorted { $0.startedAt < $1.startedAt }
    }

    // Canvas 高度 = max(session 节点高, 所有 subagent 节点堆叠高)
    private var totalHeight: CGFloat {
        let n = subagents.count
        if n == 0 { return nodeH }
        return max(nodeH, CGFloat(n) * nodeH + CGFloat(n - 1) * gap)
    }

    private var sessionCY: CGFloat { totalHeight / 2 }

    private func subCY(at index: Int) -> CGFloat {
        CGFloat(index) * (nodeH + gap) + nodeH / 2
    }

    private var branchX: CGFloat { sessionNodeW + hGap }
    private var subLeft: CGFloat { branchX + hGap }

    // 耗时格式化（与现有一致）
    private func elapsedString(from start: Date, to end: Date) -> String {
        let s = max(0, Int(end.timeIntervalSince(start)))
        return s < 60 ? "\(s)s" : "\(s/60)m\(s%60)s"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // ── 连接线 Canvas ──────────────────────────────────────
            Canvas { context, _ in
                var path = Path()
                let sCY   = sessionCY
                let bX    = branchX
                let sL    = subLeft
                let cys   = subagents.indices.map { subCY(at: $0) }

                // session 右边中心 → branchX
                path.move(to: CGPoint(x: sessionNodeW, y: sCY))
                path.addLine(to: CGPoint(x: bX, y: sCY))

                if cys.count > 1, let first = cys.first, let last = cys.last {
                    // 垂直干线（仅多个 subagent 时绘制）
                    path.move(to: CGPoint(x: bX, y: first))
                    path.addLine(to: CGPoint(x: bX, y: last))
                }

                // 各分支水平线 → subagent 左边中心
                for cy in cys {
                    path.move(to: CGPoint(x: bX, y: cy))
                    path.addLine(to: CGPoint(x: sL, y: cy))
                }

                context.stroke(path, with: .color(.secondary.opacity(0.3)), lineWidth: 1)
            }
            .frame(height: totalHeight)

            // ── Session 节点（垂直居中）─────────────────────────────
            AgentGraphNode(
                name: session.definition.name,
                state: session.state,
                elapsed: elapsedString(from: session.startedAt, to: tick),
                toolCount: session.subagents.values.reduce(0) { $0 + $1.toolCalls.count },
                width: sessionNodeW,
                isSession: true,
                onTap: nil
            )
            .offset(y: sessionCY - nodeH / 2)

            // ── Subagent 节点（从上到下排列）──────────────────────
            ForEach(Array(subagents.enumerated()), id: \.element.id) { index, sub in
                AgentGraphNode(
                    name: sub.name,
                    state: sub.state,
                    elapsed: elapsedString(from: sub.startedAt, to: sub.finishedAt ?? tick),
                    toolCount: sub.toolCalls.count,
                    width: subNodeW,
                    isSession: false,
                    onTap: { onSubagentTap(sub) }
                )
                .offset(x: subLeft, y: CGFloat(index) * (nodeH + gap))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: totalHeight)
    }
}
