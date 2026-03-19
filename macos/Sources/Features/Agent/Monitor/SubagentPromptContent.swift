// macos/Sources/Features/Agent/Monitor/SubagentPromptContent.swift
import SwiftUI

struct SubagentPromptContent: View {
    let session: AgentSession
    let subagent: SubagentInfo

    @State private var transcriptPrompt: String? = nil
    @State private var isLoading = false

    private var displayPrompt: String? {
        if let p = subagent.prompt, !p.isEmpty { return p }
        return transcriptPrompt
    }

    var body: some View {
        ScrollView {
            if let prompt = displayPrompt {
                Text(prompt)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(20)
            } else {
                Text("Prompt 未记录")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .padding(12)
            }
        }
        .task {
            if subagent.prompt == nil || subagent.prompt!.isEmpty {
                isLoading = true
                transcriptPrompt = await SubagentTranscriptReader.readInitialPrompt(
                    session: session, subagent: subagent
                )
                isLoading = false
            }
        }
    }
}
