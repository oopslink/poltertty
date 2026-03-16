// macos/Sources/Features/Workspace/FileBrowser/FilePreviewView.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FilePreviewView: View {
    let url: URL
    let isFullscreen: Bool
    let onToggleFullscreen: () -> Void

    @State private var content: PreviewContent = .loading
    @State private var fileInfo: FileInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with file name
            headerView
            Divider()

            // File info section
            if let info = fileInfo {
                fileInfoView(info)
                Divider()
            }

            // Preview content
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .task(id: url) {
            // Reset state when URL changes
            content = .loading
            fileInfo = nil
            // Load preview (automatically cancelled when URL changes or view disappears)
            await loadPreview()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // Enable keyboard shortcuts when window is active
        }
        .overlay(
            // Hidden button to handle Esc key when fullscreen
            Group {
                if isFullscreen {
                    Button("") {
                        onToggleFullscreen()
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    .opacity(0)
                    .frame(width: 0, height: 0)
                }
            }
        )
    }

    private var headerView: some View {
        HStack(spacing: 8) {
            FileIconView(url: url)
                .frame(width: 16, height: 16)

            Text(url.lastPathComponent)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            // Fullscreen toggle button
            Button(action: onToggleFullscreen) {
                Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isFullscreen ? "Show Terminal (Esc)" : "Hide Terminal and Maximize Preview")
        }
        .padding()
    }

    private func fileInfoView(_ info: FileInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            infoRow("Size:", info.formattedSize)
            infoRow("Modified:", info.formattedModified)
            if let type = info.fileType {
                infoRow("Type:", type)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .fontWeight(.medium)
            Text(value)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch content {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .text(let text, let language):
            SyntaxHighlightView(text: text, language: language)

        case .image(let nsImage):
            imagePreview(nsImage)

        case .notSupported(let message):
            notSupportedView(message)

        case .error(let message):
            errorView(message)
        }
    }

    private func imagePreview(_ nsImage: NSImage) -> some View {
        Image(nsImage: nsImage)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func notSupportedView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !url.hasDirectoryPath {
                Button("Open in Default App") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Loading Logic

    private func loadPreview() async {
        // Load file info
        await loadFileInfo()

        // Check if task was cancelled
        guard !Task.isCancelled else { return }

        // Check if it's a directory
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                content = .error("File not found")
            }
            return
        }

        guard !Task.isCancelled else { return }

        if isDirectory.boolValue {
            await MainActor.run {
                content = .notSupported("Directory preview not available")
            }
            return
        }

        // Check if task was cancelled before type detection
        guard !Task.isCancelled else { return }

        // Try to preview based on content type
        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            guard !Task.isCancelled else { return }

            if contentType.conforms(to: .image) {
                await loadImage()
            } else if contentType.conforms(to: .text) || isKnownTextType(contentType) {
                await loadText()
            } else if contentType.conforms(to: .sourceCode) {
                await loadText()
            } else if isKnownTextExtension() {
                // Fallback: Check file extension when UTType doesn't help
                await loadText()
            } else {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    content = .notSupported("Preview not available for this file type")
                }
            }
        } else if isKnownTextExtension() {
            // No content type, but has known text extension
            await loadText()
        } else {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                content = .notSupported("Unknown file type")
            }
        }
    }

    private func loadFileInfo() async {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = attributes[.size] as? Int64 ?? 0
            let modified = attributes[.modificationDate] as? Date ?? Date()

            let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
            let typeDescription = contentType?.localizedDescription

            await MainActor.run {
                fileInfo = FileInfo(
                    size: size,
                    modified: modified,
                    fileType: typeDescription
                )
            }
        } catch {
            // Ignore errors, fileInfo will remain nil
        }
    }

    private func loadText() async {
        do {
            guard !Task.isCancelled else { return }

            // Read file with size limit (1MB)
            let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
            if fileSize > 1_000_000 {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    content = .notSupported("File too large for text preview (max 1MB)")
                }
                return
            }

            guard !Task.isCancelled else { return }
            let data = try Data(contentsOf: url)

            guard !Task.isCancelled else { return }
            guard let text = String(data: data, encoding: .utf8) else {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    content = .notSupported("File is not valid UTF-8 text")
                }
                return
            }

            guard !Task.isCancelled else { return }
            let language = detectLanguage()
            await MainActor.run {
                content = .text(text, language)
            }
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                content = .error("Failed to read file: \(error.localizedDescription)")
            }
        }
    }

    private func loadImage() async {
        do {
            guard !Task.isCancelled else { return }
            let data = try Data(contentsOf: url)

            guard !Task.isCancelled else { return }
            guard let nsImage = NSImage(data: data) else {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    content = .error("Failed to load image")
                }
                return
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                content = .image(nsImage)
            }
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                content = .error("Failed to load image: \(error.localizedDescription)")
            }
        }
    }

    private func isKnownTextType(_ contentType: UTType) -> Bool {
        // Common text file types
        let textTypes: [UTType] = [
            .json,
            .xml,
            .yaml,
            .propertyList,
            .log,
            .makefile,
            .shellScript,
        ]

        return textTypes.contains { contentType.conforms(to: $0) } || isKnownTextExtension()
    }

    private func isKnownTextExtension() -> Bool {
        // Common programming language and text file extensions
        let extensions = [
            // Markup
            "md", "markdown", "rst", "adoc", "asciidoc", "textile",
            // Programming
            "swift", "py", "js", "ts", "tsx", "jsx", "c", "cpp", "h", "hpp",
            "go", "rs", "java", "kt", "rb", "php", "cs", "m", "mm",
            "zig",  // Zig language
            // Web
            "html", "htm", "css", "scss", "sass", "less", "vue",
            // Config
            "json", "yml", "yaml", "toml", "ini", "conf", "config",
            "xml", "plist", "env", "properties",
            // Shell
            "sh", "bash", "zsh", "fish",
            // Text
            "txt", "text", "log", "csv", "tsv",
            // Build
            "makefile", "mk", "cmake", "gradle",
            // Other
            "sql", "graphql", "proto", "lock", "gitignore", "dockerfile"
        ]

        return extensions.contains(url.pathExtension.lowercased())
    }

    private func detectLanguage() -> String? {
        // Check filename first (for extensionless files like Makefile, Dockerfile)
        let filenameMap: [String: String] = [
            "makefile": "makefile",
            "dockerfile": "dockerfile",
            "gemfile": "ruby",
            "rakefile": "ruby",
            "podfile": "ruby",
            "vagrantfile": "ruby",
            "cmakelists.txt": "cmake",
        ]
        if let lang = filenameMap[url.lastPathComponent.lowercased()] { return lang }

        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }

        let extMap: [String: String] = [
            // Swift / Apple
            "swift": "swift", "m": "objectivec", "mm": "objectivec",
            // C / C++
            "c": "c", "h": "c", "cpp": "cpp", "cc": "cpp", "cxx": "cpp", "hpp": "cpp",
            // JVM
            "java": "java", "kt": "kotlin", "groovy": "groovy", "gradle": "groovy",
            "scala": "scala",
            // .NET
            "cs": "csharp", "fs": "fsharp", "vb": "vbnet",
            // Scripting
            "py": "python", "rb": "ruby", "php": "php", "lua": "lua", "pl": "perl",
            // Web
            "js": "javascript", "jsx": "javascript", "ts": "typescript", "tsx": "typescript",
            "html": "xml", "htm": "xml", "vue": "xml", "svelte": "xml",
            "css": "css", "scss": "scss", "sass": "scss", "less": "less",
            // Systems
            "go": "go", "rs": "rust", "zig": "zig",
            // Shell
            "sh": "bash", "bash": "bash", "zsh": "bash", "fish": "bash",
            // Data / Config
            "json": "json", "yml": "yaml", "yaml": "yaml",
            "toml": "ini", "ini": "ini", "conf": "ini", "properties": "properties",
            "xml": "xml", "plist": "xml",
            "env": "bash", "gitignore": "bash",
            // Docs
            "md": "markdown", "markdown": "markdown", "rst": "markdown",
            // Query
            "sql": "sql", "graphql": "graphql",
            // Build
            "cmake": "cmake", "mk": "makefile",
            // Serialization
            "proto": "protobuf",
        ]
        return extMap[ext]
    }
}

// MARK: - Supporting Types

private enum PreviewContent {
    case loading
    case text(String, String?)   // (content, highlightLanguage)
    case image(NSImage)
    case notSupported(String)
    case error(String)
}

private struct FileInfo {
    let size: Int64
    let modified: Date
    let fileType: String?

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedModified: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modified)
    }
}

// MARK: - File Icon View

private struct FileIconView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyDown
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        nsView.image = icon
    }
}
