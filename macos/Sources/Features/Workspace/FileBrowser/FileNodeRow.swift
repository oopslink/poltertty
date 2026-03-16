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

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            // Indentation
            if depth > 0 {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: CGFloat(depth) * 16, height: 1)
            }

            // Chevron for directories
            if node.isDirectory {
                Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .frame(width: 10, height: 10)
                    .foregroundColor(.secondary.opacity(0.7))
                    .contentShape(Rectangle())
                    .onTapGesture { onToggleExpand() }
            } else {
                Spacer().frame(width: 10)
            }

            // File/folder icon via NSWorkspace
            FileIconView(url: node.url)
                .frame(width: 16, height: 16)
                .clipped()

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
                    .foregroundColor(isSelected ? .primary : .primary.opacity(0.95))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            // Git status badge
            if let status = gitStatus {
                Text(status.symbol)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Color(hex: status.colorHex) ?? .secondary)
                    .padding(.trailing, 2)
            }
        }
        .frame(height: 20)
        .padding(.vertical, 1)
        .padding(.horizontal, 6)
        .background(rowBackground)
        .cornerRadius(3)
        .padding(.horizontal, 3)
        .padding(.vertical, 0.5)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
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

    private var rowBackground: some View {
        Group {
            if isSelected {
                Color.accentColor.opacity(0.15)
            } else if isHovering {
                Color.primary.opacity(0.06)
            } else {
                Color.clear
            }
        }
    }
}

// MARK: - File Icon using NSWorkspace

private struct FileIconView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyDown
        view.imageAlignment = .alignCenter
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        nsView.image = icon

        // Force the bounds to constrain the image
        if let superview = nsView.superview {
            nsView.frame = superview.bounds
        }
    }
}
