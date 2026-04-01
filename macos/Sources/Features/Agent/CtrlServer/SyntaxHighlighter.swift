// macos/Sources/Features/Agent/CtrlServer/SyntaxHighlighter.swift
// SyntaxHighlighter（JSContext + highlight.js）和 AtomOneDark 主题
// 供 JSONHighlightView 使用的语法高亮工具类
import AppKit
import JavaScriptCore

// MARK: - SyntaxHighlighter (JSContext + highlight.js)

final class SyntaxHighlighter {
    /// 所有 JSContext 操作必须在此 queue 上执行（JSContext 非线程安全）
    static let highlightQueue = DispatchQueue(label: "com.poltertty.syntax-highlight", qos: .userInitiated)
    /// 高亮结果缓存，key 为 "语言:代码"，避免重复执行 JS
    private static let cache: NSCache<NSString, NSAttributedString> = {
        let c = NSCache<NSString, NSAttributedString>()
        c.countLimit = 50
        return c
    }()

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

    /// 返回高亮后的 NSAttributedString，失败时返回 nil
    func highlight(_ code: String, language: String?) -> NSAttributedString? {
        guard let ctx = context else { return nil }

        let cacheKey = "\(language ?? "auto"):\(code)" as NSString
        if let cached = SyntaxHighlighter.cache.object(forKey: cacheKey) {
            return cached
        }

        let escaped = code
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")

        var html: String?
        if let lang = language {
            let result = ctx.evaluateScript("hljs.highlight(`\(escaped)`, {language: `\(lang)`, ignoreIllegals: true}).value")
            let str = result?.toString()
            if let str, !str.isEmpty, str != "undefined" {
                html = str
            }
        }
        if html == nil {
            let result = ctx.evaluateScript("hljs.highlightAuto(`\(escaped)`).value")
            let str = result?.toString()
            if let str, !str.isEmpty, str != "undefined" {
                html = str
            }
        }

        guard let html else { return nil }

        let highlighted = parseHighlightHTML(html)
        SyntaxHighlighter.cache.setObject(highlighted, forKey: cacheKey)
        return highlighted
    }

    // MARK: - HTML span 解析

    private func parseHighlightHTML(_ html: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var remaining = html[html.startIndex...]

        while !remaining.isEmpty {
            if remaining.hasPrefix("<span") {
                remaining = consumeSpan(remaining, into: result)
            } else if remaining.hasPrefix("<") {
                if let end = remaining.range(of: ">") {
                    remaining = remaining[end.upperBound...]
                } else {
                    break
                }
            } else {
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

        let className: String
        if let classRange = remaining.range(of: "class=\""),
           let classEnd = remaining[classRange.upperBound...].range(of: "\"") {
            let raw = String(remaining[classRange.upperBound..<classEnd.lowerBound])
            className = raw.hasPrefix("hljs-") ? String(raw.dropFirst(5)) : raw
        } else {
            className = ""
        }

        guard let tagEnd = remaining.range(of: ">") else { return remaining.dropFirst() }
        remaining = remaining[tagEnd.upperBound...]

        let color = AtomOneDark.color(for: className)
        let isBold = AtomOneDark.isBold(className)
        let isItalic = AtomOneDark.isItalic(className)

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

// MARK: - Atom One Dark 主题

enum AtomOneDark {
    static let background       = NSColor(hex: "#282c34")!
    static let gutterBackground = NSColor(hex: "#21252b")!
    static let defaultText      = NSColor(hex: "#abb2bf")!

    private static let palette: [String: NSColor] = [
        "keyword":           NSColor(hex: "#c678dd")!,
        "built_in":          NSColor(hex: "#e6c07b")!,
        "type":              NSColor(hex: "#e6c07b")!,
        "literal":           NSColor(hex: "#56b6c2")!,
        "number":            NSColor(hex: "#d19a66")!,
        "regexp":            NSColor(hex: "#98c379")!,
        "string":            NSColor(hex: "#98c379")!,
        "subst":             NSColor(hex: "#e06c75")!,
        "symbol":            NSColor(hex: "#61aeee")!,
        "class":             NSColor(hex: "#e6c07b")!,
        "function":          NSColor(hex: "#61aeee")!,
        "title":             NSColor(hex: "#61aeee")!,
        "title.function_":   NSColor(hex: "#61aeee")!,
        "title.class_":      NSColor(hex: "#e6c07b")!,
        "params":            NSColor(hex: "#abb2bf")!,
        "comment":           NSColor(hex: "#5c6370")!,
        "doctag":            NSColor(hex: "#c678dd")!,
        "meta":              NSColor(hex: "#e06c75")!,
        "attr":              NSColor(hex: "#e06c75")!,
        "attribute":         NSColor(hex: "#e06c75")!,
        "variable":          NSColor(hex: "#e06c75")!,
        "bullet":            NSColor(hex: "#61aeee")!,
        "section":           NSColor(hex: "#e06c75")!,
        "addition":          NSColor(hex: "#98c379")!,
        "deletion":          NSColor(hex: "#e06c75")!,
        "selector-tag":      NSColor(hex: "#e06c75")!,
        "selector-id":       NSColor(hex: "#61aeee")!,
        "selector-class":    NSColor(hex: "#e6c07b")!,
        "template-tag":      NSColor(hex: "#e06c75")!,
        "template-variable": NSColor(hex: "#c678dd")!,
        "link":              NSColor(hex: "#61aeee")!,
        "name":              NSColor(hex: "#e06c75")!,
        "tag":               NSColor(hex: "#e06c75")!,
        "punctuation":       NSColor(hex: "#abb2bf")!,
        "operator":          NSColor(hex: "#56b6c2")!,
        "property":          NSColor(hex: "#e06c75")!,
    ]

    static func color(for className: String) -> NSColor {
        for part in className.components(separatedBy: .whitespaces) {
            if let c = palette[part] { return c }
        }
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
