import SwiftUI

struct TmuxPaneRow: View {
    let pane: TmuxPane
    @ObservedObject var viewModel: TmuxPanelViewModel

    var body: some View {
        HStack(spacing: 4) {
            Text("%\(pane.id)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
            Text(pane.title)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundColor(pane.active ? .primary : .secondary)
            if pane.active {
                Image(systemName: "circle.fill")
                    .font(.system(size: 5))
                    .foregroundColor(.accentColor)
            }
            Spacer()
        }
        .padding(.leading, 8)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Select Pane") {
                Task { await viewModel.selectPane(paneId: pane.id) }
            }
            Divider()
            Button("Split Horizontal") {
                Task { await viewModel.splitPane(paneId: pane.id, horizontal: true) }
            }
            Button("Split Vertical") {
                Task { await viewModel.splitPane(paneId: pane.id, horizontal: false) }
            }
            Divider()
            Button("Kill Pane", role: .destructive) {
                Task { await viewModel.killPane(paneId: pane.id) }
            }
        }
    }
}
