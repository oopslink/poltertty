// macos/Sources/Features/Workspace/FileBrowser/SyntaxHighlightView.swift
import SwiftUI
import AppKit
import JavaScriptCore

// MARK: - SyntaxHighlightView

/// Uses a container NSView with a gutter (line numbers) and a scroll view side by side.
/// NSRulerView is NOT used because SwiftUI's NSViewRepresentable prevents NSScrollView
/// from properly tiling ruler views (the ruler covers the text area).
struct SyntaxHighlightView: NSViewRepresentable {
    let text: String
    let language: String?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SyntaxContainerView {
        let container = SyntaxContainerView()
        context.coordinator.container = container
        context.coordinator.highlighter = SyntaxHighlighter()
        return container
    }

    func updateNSView(_ container: SyntaxContainerView, context: Context) {
        let coord = context.coordinator
        guard coord.lastText != text || coord.lastLanguage != language else { return }
        coord.lastText = text
        coord.lastLanguage = language

        let attributed = coord.highlighter?.highlight(text, language: language)
            ?? plainAttributedString(text)

        DispatchQueue.main.async {
            container.textView.textStorage?.setAttributedString(attributed)
            container.textView.needsDisplay = true
            container.gutterView.needsDisplay = true
        }
    }

    private func plainAttributedString(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: AtomOneDark.defaultText,
        ])
    }

    class Coordinator {
        var container: SyntaxContainerView?
        var highlighter: SyntaxHighlighter?
        var lastText: String?
        var lastLanguage: String?
    }
}

// MARK: - SyntaxContainerView

/// Container that places a line-number gutter and a text scroll view side by side.
/// Manages layout manually to avoid NSRulerView/SwiftUI conflicts.
final class SyntaxContainerView: NSView {
    static let gutterWidth: CGFloat = 44

    let gutterView: LineNumberGutterView
    let scrollView: NSScrollView
    let textView: NSTextView

    override init(frame: NSRect) {
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
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.drawsBackground = true
        textView.backgroundColor = AtomOneDark.background
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        self.scrollView = scrollView
        self.textView = textView

        let gutter = LineNumberGutterView(textView: textView, scrollView: scrollView)
        self.gutterView = gutter

        super.init(frame: frame)

        // Clip subviews to prevent rendering outside SwiftUI-allocated bounds
        wantsLayer = true
        layer?.masksToBounds = true

        addSubview(gutterView)
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let gw = Self.gutterWidth
        gutterView.frame = NSRect(x: 0, y: 0, width: gw, height: bounds.height)
        scrollView.frame = NSRect(x: gw, y: 0, width: bounds.width - gw, height: bounds.height)
    }
}

// MARK: - SyntaxHighlighter (JSContext + highlight.js)

final class SyntaxHighlighter {
    private let context: JSContext?
    private let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    init() {
        guard
            let jsURL = Bundle.main.url(forResource: "highlight.min", withExtension: "js"),
            let jsSource = try? String(contentsOf: jsURL),
            let ctx = JSContext()
        else {
            context = nil
            return
        }
        ctx.exceptionHandler = { _, _ in }
        ctx.evaluateScript(jsSource)
        context = ctx
    }

    /// Returns highlighted NSAttributedString, or nil on failure.
    func highlight(_ code: String, language: String?) -> NSAttributedString? {
        guard let ctx = context else { return nil }

        let escaped = code
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")

        let script: String
        if let lang = language {
            script = "hljs.highlight(`\(escaped)`, {language: `\(lang)`, ignoreIllegals: true}).value"
        } else {
            script = "hljs.highlightAuto(`\(escaped)`).value"
        }

        guard let html = ctx.evaluateScript(script)?.toString(), !html.isEmpty else {
            return nil
        }

        return parseHighlightHTML(html)
    }

    // MARK: - HTML span parser

    private func parseHighlightHTML(_ html: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var remaining = html[html.startIndex...]

        while !remaining.isEmpty {
            if remaining.hasPrefix("<span") {
                remaining = consumeSpan(remaining, into: result)
            } else if remaining.hasPrefix("<") {
                // Skip any other tag
                if let end = remaining.range(of: ">") {
                    remaining = remaining[end.upperBound...]
                } else {
                    break
                }
            } else {
                // Plain text until next tag
                let end = remaining.range(of: "<")?.lowerBound ?? remaining.endIndex
                let text = decodeEntities(String(remaining[..<end]))
                if !text.isEmpty {
                    result.append(styledString(text, color: AtomOneDark.defaultText))
                }
                remaining = remaining[end...]
            }
        }

        return result
    }

    private func consumeSpan(_ input: Substring, into result: NSMutableAttributedString) -> Substring {
        var remaining = input

        // Extract class name
        let className: String
        if let classRange = remaining.range(of: "class=\""),
           let classEnd = remaining[classRange.upperBound...].range(of: "\"") {
            let raw = String(remaining[classRange.upperBound..<classEnd.lowerBound])
            // Strip "hljs-" prefix
            className = raw.hasPrefix("hljs-") ? String(raw.dropFirst(5)) : raw
        } else {
            className = ""
        }

        // Find opening >
        guard let tagEnd = remaining.range(of: ">") else { return remaining.dropFirst() }
        remaining = remaining[tagEnd.upperBound...]

        let color = AtomOneDark.color(for: className)
        let isBold = AtomOneDark.isBold(className)
        let isItalic = AtomOneDark.isItalic(className)

        // Collect inner content (handles nested spans)
        var depth = 1
        var scanPos = remaining.startIndex
        while scanPos < remaining.endIndex && depth > 0 {
            if remaining[scanPos...].hasPrefix("<span") {
                depth += 1
                scanPos = remaining[scanPos...].range(of: ">")?.upperBound ?? remaining.endIndex
            } else if remaining[scanPos...].hasPrefix("</span>") {
                depth -= 1
                if depth == 0 { break }
                scanPos = remaining.index(scanPos, offsetBy: 7, limitedBy: remaining.endIndex) ?? remaining.endIndex
            } else {
                scanPos = remaining.index(after: scanPos)
            }
        }

        let innerHTML = String(remaining[..<scanPos])

        // Recurse into inner content
        let inner = parseHighlightHTML(innerHTML)
        let styled = NSMutableAttributedString(attributedString: inner)
        styled.enumerateAttributes(in: NSRange(location: 0, length: styled.length)) { attrs, range, _ in
            if attrs[.foregroundColor] == nil || (attrs[.foregroundColor] as? NSColor) == AtomOneDark.defaultText {
                styled.addAttribute(.foregroundColor, value: color, range: range)
            }
            if isBold {
                let existingFont = attrs[.font] as? NSFont ?? font
                styled.addAttribute(.font, value: NSFont(descriptor: existingFont.fontDescriptor.withSymbolicTraits(.bold), size: existingFont.pointSize) ?? font, range: range)
            }
            if isItalic {
                let existingFont = attrs[.font] as? NSFont ?? font
                styled.addAttribute(.font, value: NSFont(descriptor: existingFont.fontDescriptor.withSymbolicTraits(.italic), size: existingFont.pointSize) ?? font, range: range)
            }
        }
        result.append(styled)

        // Advance past </span>
        if scanPos < remaining.endIndex, remaining[scanPos...].hasPrefix("</span>") {
            let afterSpan = remaining.index(scanPos, offsetBy: 7, limitedBy: remaining.endIndex) ?? remaining.endIndex
            remaining = remaining[afterSpan...]
        } else {
            remaining = remaining[scanPos...]
        }

        return remaining
    }

    private func styledString(_ text: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
        ])
    }

    private func decodeEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}

// MARK: - Atom One Dark Theme

enum AtomOneDark {
    static let background   = OSColor(hex: "#282c34")!
    static let gutterBackground = OSColor(hex: "#21252b")!
    static let defaultText  = OSColor(hex: "#abb2bf")!

    private static let palette: [String: OSColor] = [
        "keyword":          OSColor(hex: "#c678dd")!,
        "built_in":         OSColor(hex: "#e6c07b")!,
        "type":             OSColor(hex: "#e6c07b")!,
        "literal":          OSColor(hex: "#56b6c2")!,
        "number":           OSColor(hex: "#d19a66")!,
        "regexp":           OSColor(hex: "#98c379")!,
        "string":           OSColor(hex: "#98c379")!,
        "subst":            OSColor(hex: "#e06c75")!,
        "symbol":           OSColor(hex: "#61aeee")!,
        "class":            OSColor(hex: "#e6c07b")!,
        "function":         OSColor(hex: "#61aeee")!,
        "title":            OSColor(hex: "#61aeee")!,
        "title.function_":  OSColor(hex: "#61aeee")!,
        "title.class_":     OSColor(hex: "#e6c07b")!,
        "params":           OSColor(hex: "#abb2bf")!,
        "comment":          OSColor(hex: "#5c6370")!,
        "doctag":           OSColor(hex: "#c678dd")!,
        "meta":             OSColor(hex: "#e06c75")!,
        "attr":             OSColor(hex: "#e06c75")!,
        "attribute":        OSColor(hex: "#e06c75")!,
        "variable":         OSColor(hex: "#e06c75")!,
        "bullet":           OSColor(hex: "#61aeee")!,
        "section":          OSColor(hex: "#e06c75")!,
        "addition":         OSColor(hex: "#98c379")!,
        "deletion":         OSColor(hex: "#e06c75")!,
        "selector-tag":     OSColor(hex: "#e06c75")!,
        "selector-id":      OSColor(hex: "#61aeee")!,
        "selector-class":   OSColor(hex: "#e6c07b")!,
        "template-tag":     OSColor(hex: "#e06c75")!,
        "template-variable":OSColor(hex: "#c678dd")!,
        "link":             OSColor(hex: "#61aeee")!,
        "name":             OSColor(hex: "#e06c75")!,
        "tag":              OSColor(hex: "#e06c75")!,
        "punctuation":      OSColor(hex: "#abb2bf")!,
        "operator":         OSColor(hex: "#56b6c2")!,
        "property":         OSColor(hex: "#e06c75")!,
    ]

    static func color(for className: String) -> NSColor {
        // Handle compound classes like "title function_"
        for part in className.components(separatedBy: .whitespaces) {
            if let c = palette[part] { return c }
        }
        // Try the full compound key
        if let c = palette[className] { return c }
        return defaultText
    }

    static func isBold(_ className: String) -> Bool {
        ["section", "strong"].contains(className)
    }

    static func isItalic(_ className: String) -> Bool {
        ["comment", "emphasis"].contains(className)
    }
}

// MARK: - LineNumberGutterView

/// A plain NSView that draws line numbers synchronized with an NSTextView's scroll position.
/// Does NOT use NSRulerView — avoids SwiftUI/NSViewRepresentable tiling conflicts.
final class LineNumberGutterView: NSView {
    override var isFlipped: Bool { true }

    private weak var trackedTextView: NSTextView?
    private weak var trackedScrollView: NSScrollView?

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.trackedTextView = textView
        self.trackedScrollView = scrollView
        super.init(frame: .zero)

        NotificationCenter.default.addObserver(
            self, selector: #selector(viewNeedsRedraw),
            name: NSTextStorage.didProcessEditingNotification,
            object: textView.textStorage
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(viewNeedsRedraw),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func viewNeedsRedraw(_ n: Notification) { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        guard
            let textView = trackedTextView,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer,
            let scrollView = trackedScrollView
        else { return }

        // Background
        AtomOneDark.gutterBackground.setFill()
        dirtyRect.fill()

        // Separator line
        NSColor.separatorColor.withAlphaComponent(0.4).setStroke()
        let sep = NSBezierPath()
        sep.move(to: NSPoint(x: bounds.maxX - 0.5, y: dirtyRect.minY))
        sep.line(to: NSPoint(x: bounds.maxX - 0.5, y: dirtyRect.maxY))
        sep.lineWidth = 1
        sep.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: OSColor(hex: "#4b5263")!,
        ]

        let visibleRect = scrollView.contentView.bounds
        let insetY = textView.textContainerInset.height
        let nsString = textView.string as NSString
        let length = nsString.length
        guard length > 0 else { return }

        let visibleGlyphs = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleChars = layoutManager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)

        // Count lines before visible range
        var lineNum = 1
        var idx = 0
        while idx < visibleChars.location {
            let r = nsString.lineRange(for: NSRange(location: idx, length: 0))
            let next = NSMaxRange(r)
            guard next > idx else { break }
            idx = next
            lineNum += 1
        }

        // Draw visible line numbers
        let gutterWidth = bounds.width
        idx = visibleChars.location
        while idx < length {
            let lineRange = nsString.lineRange(for: NSRange(location: idx, length: 0))
            let glyphs = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            var lineRect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            lineRect.origin.y += insetY - visibleRect.origin.y

            if lineRect.minY > dirtyRect.maxY { break }

            let str = "\(lineNum)" as NSString
            let size = str.size(withAttributes: attrs)
            str.draw(
                at: NSPoint(
                    x: gutterWidth - size.width - 8,
                    y: lineRect.origin.y + (lineRect.height - size.height) / 2
                ),
                withAttributes: attrs
            )

            lineNum += 1
            let next = NSMaxRange(lineRange)
            guard next > idx else { break }
            idx = next
        }
    }
}
