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

    let isMultiSelected: Bool           // 是否有多个节点被选中（影响右键菜单）
    let selectedCount: Int              // 当前选中数量
    let selectedURLs: [URL]            // 所有选中节点的 URL（用于拖拽载荷）
    let onMoveSelected: (() -> Void)?   // 触发"移动到…"面板

    var isRenaming: Bool = false
    var renameText: Binding<String>? = nil
    var onCommitRename: ((String) -> Void)? = nil
    var onCancelRename: (() -> Void)? = nil

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
                RenameTextField(
                    text: binding,
                    onCommit: { name in onCommitRename?(name) },
                    onCancel: { onCancelRename?() }
                )
                .frame(height: 16)
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
        .onDrag {
            // 始终传当前行 URL 作为拖拽载荷。
            // 多选时 dropDestination 会检查此 URL 是否属于选中集，
            // 若是则在 drop 侧移动全部选中项，无需在此传递多个 URL。
            NSItemProvider(contentsOf: node.url) ?? NSItemProvider()
        } preview: {
            if isMultiSelected && selectedCount > 1 {
                Label("\(selectedCount) 个项目", systemImage: "doc.on.doc")
                    .padding(8)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .cornerRadius(6)
            } else {
                Label(node.name, systemImage: node.isDirectory ? "folder" : "doc")
                    .padding(8)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .cornerRadius(6)
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .gesture(TapGesture(count: 2).onEnded { onDoubleClick() })
        .simultaneousGesture(TapGesture(count: 1).onEnded { onSingleClick() })
        .contextMenu {
            if isMultiSelected {
                // 多选菜单
                Button("删除 \(selectedCount) 个项目…", role: .destructive) { onDelete() }
                Button("移动到…") { onMoveSelected?() }
            } else {
                // 单选菜单（保持原有）
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

    private var rowBackground: some View {
        Group {
            if isSelected {
                Color.accentColor.opacity(0.28)
            } else if isHovering {
                Color.primary.opacity(0.06)
            } else {
                Color.clear
            }
        }
    }
}

// MARK: - Rename TextField (AppKit-level for reliable focus)

private final class AutoFocusTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else {
                return
            }
            _ = window.makeFirstResponder(self)
            self.selectText(nil)
        }
    }
}

private struct RenameTextField: NSViewRepresentable {
    @Binding var text: String
    var onCommit: (String) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> AutoFocusTextField {
        let field = AutoFocusTextField()
        field.isBordered = false
        field.backgroundColor = .clear
        field.font = .systemFont(ofSize: 12)
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingMiddle
        field.maximumNumberOfLines = 1
        field.delegate = context.coordinator
        field.stringValue = text
        return field
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func updateNSView(_ nsView: AutoFocusTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.currentEditor() == nil, nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RenameTextField

        init(_ parent: RenameTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if !parent.text.isEmpty { parent.onCommit(parent.text) }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
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
