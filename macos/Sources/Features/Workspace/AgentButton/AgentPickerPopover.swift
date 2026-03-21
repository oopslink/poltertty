// macos/Sources/Features/Workspace/AgentButton/AgentPickerPopover.swift

import SwiftUI

struct AgentPickerPopover: View {
    let surfaceId: UUID
    @Binding var isPresented: Bool

    var body: some View {
        Text("Pick an agent")
            .padding()
    }
}
