import Testing
import Foundation
@testable import Ghostty

@Suite
struct TokenTrackerThrottleTests {

    @Test func throttle_allowsFirstPoll() {
        var lastPollDates: [UUID: Date] = [:]
        let id = UUID()
        let now = Date()
        let shouldPoll = Self.checkThrottle(id: id, lastPollDates: &lastPollDates,
                                            now: now, interval: 5)
        #expect(shouldPoll == true)
        #expect(lastPollDates[id] != nil)
    }

    @Test func throttle_blocksWithinInterval() {
        var lastPollDates: [UUID: Date] = [:]
        let id = UUID()
        let t0 = Date(timeIntervalSince1970: 1000)
        let t1 = Date(timeIntervalSince1970: 1003)  // 3s 后，< 5s
        _ = Self.checkThrottle(id: id, lastPollDates: &lastPollDates, now: t0, interval: 5)
        let shouldPoll = Self.checkThrottle(id: id, lastPollDates: &lastPollDates,
                                            now: t1, interval: 5)
        #expect(shouldPoll == false)
    }

    @Test func throttle_allowsAfterInterval() {
        var lastPollDates: [UUID: Date] = [:]
        let id = UUID()
        let t0 = Date(timeIntervalSince1970: 1000)
        let t1 = Date(timeIntervalSince1970: 1006)  // 6s 后，> 5s
        _ = Self.checkThrottle(id: id, lastPollDates: &lastPollDates, now: t0, interval: 5)
        let shouldPoll = Self.checkThrottle(id: id, lastPollDates: &lastPollDates,
                                            now: t1, interval: 5)
        #expect(shouldPoll == true)
    }

    // 镜像 TokenTracker 内部节流逻辑，供纯函数测试
    static func checkThrottle(id: UUID, lastPollDates: inout [UUID: Date],
                               now: Date, interval: TimeInterval) -> Bool {
        if let last = lastPollDates[id], now.timeIntervalSince(last) < interval {
            return false
        }
        lastPollDates[id] = now
        return true
    }
}
