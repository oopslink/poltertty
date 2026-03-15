import Foundation
import SwiftUI

struct WorkspaceNameValidator {
    /// Characters that are silently blocked during input
    static let blockedCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")

    /// Maximum name length
    static let maxLength = 32

    /// Filter blocked characters from input string (for real-time input filtering)
    static func filterInput(_ input: String) -> String {
        let filtered = input.unicodeScalars.filter { !blockedCharacters.contains($0) }
        let result = String(String.UnicodeScalarView(filtered))
        return String(result.prefix(maxLength))
    }

    /// Validate on submit — returns error message or nil if valid
    static func validate(_ name: String, existingNames: [String]) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return "请输入名称"
        }
        if existingNames.contains(where: { $0.lowercased() == trimmed.lowercased() }) {
            return "该名称已存在"
        }
        return nil
    }
}

struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = sin(shakes * .pi * 2) * 5
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}
