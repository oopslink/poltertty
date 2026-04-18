// macos/Sources/Features/Agent/Skills/SkillManager.swift
import Foundation

enum SkillError: LocalizedError {
    case invalidId(String)
    case pathTraversal(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidId(let id): return "Invalid skill ID: \(id)"
        case .pathTraversal(let p): return "Path traversal blocked: \(p)"
        case .notFound(let id): return "Bundled skill not found: \(id)"
        }
    }
}

struct SkillDefinition: Identifiable {
    let id: String
    let displayName: String
    let description: String
    let bundledVersion: String
}

@MainActor
final class SkillManager: ObservableObject {
    static let shared = SkillManager()

    private static let validIdRegex = try! NSRegularExpression(pattern: "^[a-zA-Z0-9_-]{1,64}$")

    private let skillsBaseDir: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/skills/poltertty")

    let availableSkills: [SkillDefinition] = [
        .init(
            id: "agent-browser",
            displayName: "Agent Browser",
            description: "Let AI agents control the built-in browser panel via Ctrl API",
            bundledVersion: "1.1.0"
        ),
    ]

    // MARK: - State queries (no caching, always check filesystem)

    func isInstalled(_ skill: SkillDefinition) -> Bool {
        FileManager.default.fileExists(
            atPath: skillsBaseDir.appendingPathComponent(skill.id).path
        )
    }

    func installedVersion(_ skill: SkillDefinition) -> String? {
        let vFile = skillsBaseDir
            .appendingPathComponent(skill.id)
            .appendingPathComponent(".installed_version")
        return try? String(contentsOf: vFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func hasUpdate(_ skill: SkillDefinition) -> Bool {
        guard let installed = installedVersion(skill) else { return false }
        return installed != skill.bundledVersion
    }

    // MARK: - Install / Uninstall

    func install(_ skill: SkillDefinition) async throws {
        try validateId(skill.id)
        guard let source = bundledSkillURL(for: skill.id) else {
            throw SkillError.notFound(skill.id)
        }
        let dest = try resolvedDestination(for: skill.id)
        let version = skill.bundledVersion

        try await Task.detached(priority: .utility) {
            let fm = FileManager.default
            try fm.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: source, to: dest)
            let vFile = dest.appendingPathComponent(".installed_version")
            try version.write(to: vFile, atomically: true, encoding: .utf8)
        }.value

        objectWillChange.send()
    }

    func uninstall(_ skill: SkillDefinition) async throws {
        try validateId(skill.id)
        let dest = try resolvedDestination(for: skill.id)

        try await Task.detached(priority: .utility) {
            try FileManager.default.removeItem(at: dest)
        }.value

        objectWillChange.send()
    }

    // MARK: - Security

    private func validateId(_ id: String) throws {
        let range = NSRange(id.startIndex..<id.endIndex, in: id)
        guard Self.validIdRegex.firstMatch(in: id, range: range) != nil else {
            throw SkillError.invalidId(id)
        }
    }

    private func resolvedDestination(for id: String) throws -> URL {
        let dest = skillsBaseDir.appendingPathComponent(id).standardizedFileURL
        guard dest.path.hasPrefix(skillsBaseDir.standardizedFileURL.path) else {
            throw SkillError.pathTraversal(dest.path)
        }
        return dest
    }

    private func bundledSkillURL(for id: String) -> URL? {
        Bundle.main.url(forResource: id, withExtension: nil, subdirectory: "Skills/poltertty")
    }
}
