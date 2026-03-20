import SwiftUI

struct TmuxSessionRow: View {
    let session: TmuxSession
    @ObservedObject var viewModel: TmuxPanelViewModel

    @State private var isExpanded: Bool = true
    @State private var showRenameAlert: Bool = false
    @State private var newName: String = ""

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(session.windows) { window in
                TmuxWindowRow(window: window, viewModel: viewModel)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "terminal")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                Text(session.id)
                    .font(.system(size: 12))
                    .lineLimit(1)
                if session.attached {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
                Spacer()
            }
        }
        .contextMenu {
            Button("Attach") {
                Task { await viewModel.attachSession(session.id) }
            }
            Button("New Window") {
                Task { await viewModel.newWindow(sessionName: session.id) }
            }
            Divider()
            Button("Rename...") {
                newName = session.id
                showRenameAlert = true
            }
            Button("Kill Session", role: .destructive) {
                Task { await viewModel.killSession(session.id) }
            }
        }
        .alert("Rename Session", isPresented: $showRenameAlert) {
            TextField("Session name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                Task { await viewModel.renameSession(old: session.id, new: name) }
            }
        }
    }
}
