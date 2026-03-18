// macos/Sources/Features/Agent/Monitor/SessionOverviewContent.swift
import SwiftUI

struct SessionOverviewContent: View {
    let session: AgentSession

    private var subagents: [SubagentInfo] {
        Array(session.subagents.values).sorted { $0.startedAt < $1.startedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statRow("总耗时", value: elapsedSinceStart)
                statRow("Cost",   value: costLabel)
                statRow("Context", value: String(format: "%.0f%%", session.tokenUsage.contextUtilization * 100))
                contextBar
                    .padding(.bottom, 8)
                Divider().padding(.vertical, 6)

                Text("SUBAGENTS")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 4)

                ForEach(subagents) { sub in
                    overviewRow(sub)
                }

                Divider().padding(.vertical, 6)
                Text("点击 subagent 查看详情 · Cmd+Click 并排对比")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            .padding(12)
        }
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 10, design: .monospaced)).foregroundStyle(.primary)
        }
        .padding(.bottom, 3)
    }

    private var contextBar: some View {
        let u = CGFloat(session.tokenUsage.contextUtilization)
        let color: Color = u < 0.55 ? (Color(hex: "#4caf50") ?? .green) : u < 0.75 ? .yellow : .red
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Color(.separatorColor)).frame(height: 3)
                RoundedRectangle(cornerRadius: 2).fill(color)
                    .frame(width: geo.size.width * u, height: 3)
            }
        }
        .frame(height: 3)
    }

    private func overviewRow(_ sub: SubagentInfo) -> some View {
        HStack(spacing: 6) {
            stateIcon(sub.state)
            Text(sub.name)
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: "#569cd6") ?? .blue)
                .lineLimit(1).truncationMode(.tail)
            stateBadge(sub.state)
            Spacer()
            Text(elapsed(sub)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func stateIcon(_ state: AgentState) -> some View {
        let (sym, col): (String, Color) = {
            switch state {
            case .done:    return ("checkmark", Color(hex: "#4caf50") ?? .green)
            case .error:   return ("xmark",     Color(hex: "#f44336") ?? .red)
            case .working: return ("circle.fill", Color(hex: "#ff9800") ?? .orange)
            default:       return ("circle", .secondary)
            }
        }()
        return Image(systemName: sym).font(.system(size: 9)).foregroundStyle(col)
    }

    private func stateBadge(_ state: AgentState) -> some View {
        let (label, bg, fg): (String, Color, Color) = {
            switch state {
            case .done:    return ("done",    Color(hex: "#1a2e1a") ?? .clear, Color(hex: "#4caf50") ?? .green)
            case .error:   return ("error",   Color(hex: "#2e1a1a") ?? .clear, Color(hex: "#f44336") ?? .red)
            case .working: return ("running", Color(hex: "#1a2535") ?? .clear, Color(hex: "#90bfff") ?? .blue)
            default:       return ("idle",    Color(.separatorColor).opacity(0.4), .secondary)
            }
        }()
        return Text(label)
            .font(.system(size: 8, weight: .medium))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(bg).foregroundStyle(fg)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var elapsedSinceStart: String {
        let secs = max(0, Int(Date().timeIntervalSince(session.startedAt)))
        if secs < 60 { return "\(secs)s" }
        return "\(secs/60)m \(secs%60)s"
    }

    private var costLabel: String {
        let d = NSDecimalNumber(decimal: session.tokenUsage.cost).doubleValue
        return d > 0 ? String(format: "$%.4f", d) : "—"
    }

    private func elapsed(_ sub: SubagentInfo) -> String {
        let end = sub.finishedAt ?? Date()
        let s = max(0, Int(end.timeIntervalSince(sub.startedAt)))
        return s < 60 ? "\(s)s" : "\(s/60)m\(s%60)s"
    }
}
