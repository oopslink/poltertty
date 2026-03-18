// macos/Sources/Features/Agent/Monitor/SubagentMessagesView.swift
import SwiftUI

struct SubagentMessagesView: View {
    let session: AgentSession
    let subagent: SubagentInfo

    @State private var transcript: SubagentTranscript? = nil
    @State private var isLoading = true
    @State private var tick = Date()
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                tokenSummary
                debugIdBar
                Divider().padding(.vertical, 6)
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding(20)
                } else if let t = transcript, !t.turns.isEmpty {
                    messageList(t)
                } else {
                    Text("暂无对话记录")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(20)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await loadTranscript() }
        .onReceive(timer) { t in
            if subagent.state.isActive {
                tick = t
                Task { await loadTranscript() }
            }
        }
    }

    // MARK: - Token Summary

    private var tokenSummary: some View {
        let usage = transcript?.totalUsage ?? TurnUsage.zero
        return HStack(spacing: 0) {
            tokenCell(label: "IN", value: usage.inputTokens)
            Divider().frame(height: 20)
            tokenCell(label: "OUT", value: usage.outputTokens)
            Divider().frame(height: 20)
            tokenCell(label: "CACHE", value: usage.cacheReadTokens + usage.cacheWriteTokens)
            Spacer()
        }
        .padding(.bottom, 6)
    }

    private func tokenCell(label: String, value: Int) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
            Text(formatTokens(value))
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
        }
        .frame(minWidth: 60)
        .padding(.vertical, 4)
    }

    private func formatTokens(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fK", Double(n) / 1000) : "\(n)"
    }

    // MARK: - Debug ID Bar

    private var debugIdBar: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let agentId = subagent.agentId {
                debugIdRow(label: "Agent", value: agentId)
            }
            if let sessionId = session.claudeSessionId {
                debugIdRow(label: "Session", value: sessionId)
            }
        }
        .padding(.bottom, 4)
    }

    private func debugIdRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                .frame(width: 44, alignment: .leading)
            Text(value.count > 16 ? String(value.prefix(16)) + "…" : value)
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    // MARK: - Message List

    private func messageList(_ transcript: SubagentTranscript) -> some View {
        LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(transcript.turns) { turn in
                TurnView(turn: turn)
            }
        }
    }

    // MARK: - Load

    private func loadTranscript() async {
        let result = await SubagentTranscriptReader.read(session: session, subagent: subagent)
        await MainActor.run {
            transcript = result
            isLoading = false
        }
    }
}

// MARK: - TurnView

private struct TurnView: View {
    let turn: TranscriptTurn
    @State private var expandedToolIds: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(turn.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(turn.role == .user
            ? Color(.controlColor).opacity(0.3)
            : Color(.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func blockView(_ block: TranscriptBlock) -> some View {
        switch block {
        case .text(let t):
            Text(t)
                .font(.system(size: 10))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .toolUse(let id, let name, let inputJSON):
            VStack(alignment: .leading, spacing: 0) {
                Button(action: { toggleExpand(id) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.fill")
                            .font(.system(size: 8)).foregroundStyle(.secondary)
                        Text(name)
                            .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: expandedToolIds.contains(id) ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8)).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())

                if expandedToolIds.contains(id) {
                    Text(inputJSON)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .padding(.top, 3).padding(.leading, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

        case .toolResult(_, let content):
            if !content.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("── result ──")
                        .font(.system(size: 8)).foregroundStyle(.tertiary.opacity(0.5))
                    Text(content)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .lineLimit(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, 12)
            }
        }
    }

    private func toggleExpand(_ id: String) {
        if expandedToolIds.contains(id) {
            expandedToolIds.remove(id)
        } else {
            expandedToolIds.insert(id)
        }
    }
}
