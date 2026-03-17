// macos/Sources/Features/Agent/Monitor/SubagentListView.swift
import SwiftUI

struct SubagentListView: View {
    let subagents: [SubagentInfo]
    @State private var expanded = Set<String>()

    var body: some View {
        if subagents.isEmpty {
            Text("No subagents").font(.system(size: 11)).foregroundStyle(.tertiary)
                .padding(.horizontal, 12).padding(.vertical, 4)
        } else {
            ForEach(subagents) { agent in
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        AgentStateDot(state: agent.state)
                        Text(agent.name).font(.system(size: 11))
                        Text(agent.agentType).font(.system(size: 10)).foregroundStyle(.tertiary)
                        Spacer()
                        Image(systemName: expanded.contains(agent.id) ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if expanded.contains(agent.id) { expanded.remove(agent.id) }
                        else { expanded.insert(agent.id) }
                    }
                    if expanded.contains(agent.id) {
                        Text("Transcript unavailable")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                            .padding(.horizontal, 12).padding(.bottom, 6)
                    }
                }
            }
        }
    }
}
