// macos/Sources/Features/Workspace/AgentButton/AgentSessionPopover.swift

import SwiftUI

struct AgentSessionPopover: View {
    let session: AgentSession

    var body: some View {
        Text(session.definition.name)
            .padding()
    }
}
