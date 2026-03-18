// macos/Sources/Features/Agent/Monitor/SubagentPromptContent.swift
import SwiftUI

struct SubagentPromptContent: View {
    let subagent: SubagentInfo

    var body: some View {
        ScrollView {
            if let prompt = subagent.prompt, !prompt.isEmpty {
                Text(prompt)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else {
                Text("Prompt 未记录")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .padding(12)
            }
        }
    }
}
