// macos/Tests/Workspace/PRStatusFetcherTests.swift
import Testing
import Foundation
@testable import Ghostty

struct PRStatusFetcherTests {

    @Test func parsesOpenPR() throws {
        let json = #"{"number":152,"state":"OPEN","isDraft":false}"#
        let status = PRStatusFetcher.parseJSON(json.data(using: .utf8)!)
        #expect(status == .open(number: 152))
    }

    @Test func parsesDraftPR() throws {
        let json = #"{"number":89,"state":"OPEN","isDraft":true}"#
        let status = PRStatusFetcher.parseJSON(json.data(using: .utf8)!)
        #expect(status == .draft(number: 89))
    }

    @Test func parsesMergedPR() throws {
        let json = #"{"number":77,"state":"MERGED","isDraft":false}"#
        let status = PRStatusFetcher.parseJSON(json.data(using: .utf8)!)
        #expect(status == .merged(number: 77))
    }

    @Test func returnsNilForClosedPR() throws {
        let json = #"{"number":10,"state":"CLOSED","isDraft":false}"#
        let status = PRStatusFetcher.parseJSON(json.data(using: .utf8)!)
        #expect(status == nil)
    }

    @Test func returnsNilForInvalidJSON() {
        let status = PRStatusFetcher.parseJSON(Data())
        #expect(status == nil)
    }
}
