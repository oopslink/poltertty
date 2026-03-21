// macos/Sources/Features/Workspace/AgentButton/AgentPickerPopover.swift

import SwiftUI

struct AgentPickerPopover: View {
    let surfaceId: UUID
    @Binding var isPresented: Bool

    @ObservedObject private var registry = AgentRegistry.shared
    @State private var selectedDefinition: AgentDefinition?
    @State private var permissionMode: ClaudePermissionMode = .auto

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Agent 列表
            ForEach(registry.definitions) { def in
                Button(action: { selectedDefinition = def }) {
                    HStack {
                        Text(def.icon)
                            .foregroundColor(def.iconColor.flatMap { Color(hex: $0) } ?? .secondary)
                        Text(def.name)
                            .foregroundColor(.primary)
                        Spacer()
                        if selectedDefinition?.id == def.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .background(selectedDefinition?.id == def.id ? Color.accentColor.opacity(0.1) : .clear)
            }

            Divider()
                .padding(.vertical, 4)

            // 权限模式下拉框
            HStack {
                Text("Permission")
                    .foregroundColor(.secondary)
                    .fixedSize()
                Spacer()
                Picker("", selection: $permissionMode) {
                    ForEach(ClaudePermissionMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            Divider()
                .padding(.vertical, 4)

            // Launch 按钮
            HStack {
                Spacer()
                Button("Launch") {
                    launchAgent()
                }
                .disabled(selectedDefinition == nil)
                .keyboardShortcut(.return, modifiers: [])
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .frame(width: 200)
        .padding(.top, 8)
        .font(.system(size: 11))
        .onAppear {
            selectedDefinition = registry.definitions.first
        }
    }

    private func launchAgent() {
        guard let def = selectedDefinition else { return }
        isPresented = false
        NotificationCenter.default.post(
            name: .launchAgentFromStatusBar,
            object: nil,
            userInfo: [
                "surfaceId": surfaceId,
                "definitionId": def.id,
                "permissionMode": permissionMode.rawValue,
            ]
        )
    }
}
