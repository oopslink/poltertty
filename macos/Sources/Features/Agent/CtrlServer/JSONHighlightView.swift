// macos/Sources/Features/Agent/CtrlServer/JSONHighlightView.swift
import SwiftUI
import AppKit

/// 用于 Ctrl API Monitor detail pane 的 JSON 语法高亮视图。
/// 复用 SyntaxHighlighter（JSContext + highlight.js），不含行号 gutter。
/// 背景固定为 AtomOneDark 深色（与 FileBrowser 高亮风格一致）。
struct JSONHighlightView: NSViewRepresentable {
    let content: String
    let isError: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = AtomOneDark.background
        scrollView.drawsBackground = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.drawsBackground = true
        textView.backgroundColor = AtomOneDark.background
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.highlighter = SyntaxHighlighter()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coord = context.coordinator
        guard coord.lastContent != content || coord.lastIsError != isError else { return }
        coord.lastContent = content
        coord.lastIsError = isError

        let attributed: NSAttributedString
        if isError {
            attributed = NSAttributedString(
                string: content,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: NSColor.systemRed,
                ]
            )
        } else {
            attributed = coord.highlighter?.highlight(content, language: "json")
                ?? NSAttributedString(
                    string: content,
                    attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                        .foregroundColor: AtomOneDark.defaultText,
                    ]
                )
        }

        DispatchQueue.main.async {
            guard let textView = scrollView.documentView as? NSTextView else { return }
            textView.textStorage?.setAttributedString(attributed)
        }
    }

    class Coordinator {
        var textView: NSTextView?
        var highlighter: SyntaxHighlighter?
        var lastContent: String?
        var lastIsError: Bool?
    }
}
