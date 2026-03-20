import SwiftUI

struct TmuxWindowRow: View {
    let window: TmuxWindow
    @ObservedObject var viewModel: TmuxPanelViewModel

    @State private var isExpanded: Bool = false
    @State private var showRenameAlert: Bool = false
    @State private var newName: String = ""

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(window.panes) { pane in
                TmuxPaneRow(pane: pane, viewModel: viewModel)
            }
        } label: {
            HStack(spacing: 4) {
                Text("\(window.windowIndex): \(window.name)")
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .foregroundColor(window.active ? .primary : .secondary)
                if window.active {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundColor(.accentColor)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                Task { await viewModel.switchToWindow(sessionName: window.sessionName, windowIndex: window.windowIndex) }
            }
        }
        .contextMenu {
            Button("Switch to Window") {
                Task { await viewModel.switchToWindow(sessionName: window.sessionName, windowIndex: window.windowIndex) }
            }
            Button("New Window") {
                Task { await viewModel.newWindow(sessionName: window.sessionName) }
            }
            Divider()
            Button("Rename...") {
                newName = window.name
                showRenameAlert = true
            }
            Button("Kill Window", role: .destructive) {
                Task { await viewModel.killWindow(sessionName: window.sessionName, windowIndex: window.windowIndex) }
            }
        }
        .alert("Rename Window", isPresented: $showRenameAlert) {
            TextField("Window name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                Task { await viewModel.renameWindow(sessionName: window.sessionName, windowIndex: window.windowIndex, newName: name) }
            }
        }
    }
}
