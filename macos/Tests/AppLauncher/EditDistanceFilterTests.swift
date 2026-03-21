// macos/Tests/AppLauncher/EditDistanceFilterTests.swift
import Testing
import SwiftUI
@testable import Ghostty

struct EditDistanceFilterTests {

    // CommandOption 工厂方法
    private func option(_ title: String) -> CommandOption {
        CommandOption(title: title, action: {})
    }

    // --- levenshteinDistance ---

    @Test func testIdenticalStrings() {
        #expect(EditDistanceFilter.levenshteinDistance("abc", "abc") == 0)
    }

    @Test func testEmptyQuery() {
        #expect(EditDistanceFilter.levenshteinDistance("", "abc") == 3)
    }

    @Test func testSingleInsertion() {
        #expect(EditDistanceFilter.levenshteinDistance("ab", "abc") == 1)
    }

    @Test func testSingleDeletion() {
        #expect(EditDistanceFilter.levenshteinDistance("abc", "ab") == 1)
    }

    @Test func testSingleSubstitution() {
        #expect(EditDistanceFilter.levenshteinDistance("abc", "axc") == 1)
    }

    // --- rank ---

    @Test func testEmptyQueryReturnsEmpty() {
        let opts = [option("New Tab"), option("New Window")]
        #expect(EditDistanceFilter.rank("", in: opts).isEmpty)
    }

    @Test func testContainsMatchRankedHigher() {
        let opts = [option("New Window"), option("New Tab")]
        let result = EditDistanceFilter.rank("tab", in: opts)
        #expect(result.first?.title == "New Tab")
    }

    @Test func testResultsLimitedToEight() {
        let opts = (0..<12).map { option("tab \($0)") }
        let result = EditDistanceFilter.rank("tab", in: opts)
        #expect(result.count <= 8)
    }

    @Test func testTooDistantResultsFiltered() {
        let opts = [option("zzzzzzzzz")]
        let result = EditDistanceFilter.rank("a", in: opts)
        #expect(result.isEmpty)
    }

    @Test func testCaseInsensitiveMatching() {
        let opts = [option("New Tab")]
        let result = EditDistanceFilter.rank("TAB", in: opts)
        #expect(!result.isEmpty)
    }
}
