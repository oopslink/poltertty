// macos/Sources/Features/Splits/AnnotationPopoverView.swift

import SwiftUI

/// 注释编辑 popover，从 status bar 的 tag 按钮弹出。
struct AnnotationPopoverView: View {
    let surfaceId: UUID
    @EnvironmentObject private var paneSelectorVM: PaneSelectorViewModel
    @State private var text: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 8) {
            TextField("Set pane label...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit { save(); dismiss() }
                .onExitCommand { dismiss() }
        }
        .padding(12)
        .frame(width: 220)
        .onAppear {
            text = paneSelectorVM.annotations[surfaceId] ?? ""
        }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            paneSelectorVM.annotations.removeValue(forKey: surfaceId)
        } else {
            paneSelectorVM.annotations[surfaceId] = trimmed
        }
    }
}
