import SwiftUI

struct TmuxPanelView: View {
    @ObservedObject var viewModel: TmuxPanelViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("tmux")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    Task { await viewModel.newSession(name: "new") }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("New Session")

                Button {
                    viewModel.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            // Banner
            if let banner = viewModel.bannerMessage {
                Text(banner)
                    .font(.system(size: 11))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.85))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Main content
            switch viewModel.state {
            case .loading:
                Spacer()
                ProgressView()
                    .scaleEffect(0.7)
                Spacer()

            case .empty:
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No tmux sessions")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Button("New Session") {
                        Task { await viewModel.newSession(name: "main") }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer()

            case .loaded(let sessions):
                List {
                    ForEach(sessions) { session in
                        TmuxSessionRow(session: session, viewModel: viewModel)
                    }
                }
                .listStyle(.sidebar)

            case .error(let error):
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    errorText(for: error)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                Spacer()
            }
        }
        .animation(.easeInOut(duration: 0.15), value: viewModel.bannerMessage)
        .onAppear { viewModel.resume() }
        .onDisappear { viewModel.pause() }
    }

    @ViewBuilder
    private func errorText(for error: TmuxError) -> some View {
        switch error {
        case .notInstalled:
            Text("tmux not found.\nInstall with: brew install tmux")
        case .serverNotRunning(let stderr):
            if stderr.isEmpty {
                Text("No tmux server running.\nRun `tmux` in a terminal to start one.")
            } else {
                Text("No tmux server running.")
            }
        case .timeout:
            Text("tmux timed out.\nRetrying automatically...")
        }
    }
}
