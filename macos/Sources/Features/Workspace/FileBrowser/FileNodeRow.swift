// macos/Sources/Features/Workspace/FileBrowser/FileNodeRow.swift
import SwiftUI
import AppKit

struct FileNodeRow: View {
    let node: FileNode
    let depth: Int
    let gitStatus: GitStatus?
    let isSelected: Bool
    let onToggleExpand: () -> Void
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void
    let onOpenInTerminal: () -> Void
    let onCopyPath: () -> Void
    let onNewFile: () -> Void
    let onNewDirectory: () -> Void
    let onDelete: () -> Void
    let onStartRename: () -> Void

    var isRenaming: Bool = false
    var renameText: Binding<String>? = nil
    var onCommitRename: ((String) -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            // Indentation
            Rectangle()
                .fill(Color.clear)
                .frame(width: CGFloat(depth) * 16, height: 1)

            // Chevron for directories
            if node.isDirectory {
                Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .frame(width: 12)
                    .foregroundColor(.secondary)
                    .contentShape(Rectangle())
                    .onTapGesture { onToggleExpand() }
            } else {
                Spacer().frame(width: 12)
            }

            // File/folder icon via NSWorkspace
            FileIconView(url: node.url)
                .frame(width: 16, height: 16)

            // Name or rename TextField
            if isRenaming, let binding = renameText {
                TextField("", text: binding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        if !binding.wrappedValue.isEmpty {
                            onCommitRename?(binding.wrappedValue)
                        }
                    }
            } else {
                Text(node.name)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Git status badge
            if let status = gitStatus {
                Text(status.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: status.colorHex) ?? .secondary)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
        .gesture(TapGesture(count: 2).onEnded { onDoubleClick() })
        .simultaneousGesture(TapGesture(count: 1).onEnded { onSingleClick() })
        .contextMenu {
            Button("Open in Terminal") { onOpenInTerminal() }
            Button("Copy Path") { onCopyPath() }
            Divider()
            Button("New File") { onNewFile() }
            Button("New Directory") { onNewDirectory() }
            Divider()
            Button("Rename") { onStartRename() }
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}

// MARK: - File Icon using NSWorkspace

private struct FileIconView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyDown
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = NSWorkspace.shared.icon(forFile: url.path)
    }
}
