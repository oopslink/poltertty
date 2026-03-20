// macos/Sources/Features/Tmux/TmuxSessionPicker.swift
import SwiftUI

struct TmuxSessionPicker: View {
    @StateObject private var viewModel = TmuxSessionPickerViewModel()
    let onOpen: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("New Tab with tmux Session")
                .font(.system(size: 14, weight: .semibold))

            if viewModel.isLoading {
                ProgressView()
                    .frame(height: 120)
            } else if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.system(size: 12))
            } else {
                Picker("", selection: $viewModel.mode) {
                    Text("Attach to existing").tag(TmuxSessionPickerViewModel.Mode.attachExisting)
                    Text("Create new").tag(TmuxSessionPickerViewModel.Mode.createNew)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if viewModel.mode == .attachExisting {
                    existingSessionList
                } else {
                    newSessionForm
                }
            }

            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Open") {
                    Task {
                        guard let name = await viewModel.resolveSessionName() else { return }
                        onOpen(name)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canOpen)
            }
        }
        .padding(24)
        .frame(width: 360)
        .task {
            await viewModel.loadSessions()
        }
    }

    @ViewBuilder
    private var existingSessionList: some View {
        if viewModel.sessions.isEmpty {
            Text("没有可用的 tmux session")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
                .frame(height: 80)
        } else {
            List(viewModel.sessions, selection: $viewModel.selectedSessionName) { session in
                HStack {
                    Text(session.id)
                        .font(.system(size: 12))
                    Spacer()
                    if session.attached {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .help("已有 client 连接")
                    }
                }
                .tag(session.id)
                .contentShape(Rectangle())
            }
            .listStyle(.bordered)
            .frame(height: min(CGFloat(viewModel.sessions.count) * 28 + 8, 160))
        }
    }

    @ViewBuilder
    private var newSessionForm: some View {
        HStack {
            Text("Session name:")
                .font(.system(size: 12))
            TextField("留空自动命名", text: $viewModel.newSessionName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
        }
    }
}
