// macos/Tests/Agent/EventBusTests.swift
import Testing
import Foundation
@testable import Ghostty

struct EventBusTests {

    @Test func subscribeReceivesEmittedEvent() async {
        let bus = EventBus()
        let (_, stream) = await bus.subscribe()

        let tabId = UUID()
        let wsId = UUID()
        await bus.emit(.tabCreated(tabId: tabId, workspaceId: wsId))

        var iterator = stream.makeAsyncIterator()
        let event = await iterator.next()

        guard case .tabCreated(let receivedTabId, let receivedWsId) = event else {
            Issue.record("Expected tabCreated event")
            return
        }
        #expect(receivedTabId == tabId)
        #expect(receivedWsId == wsId)
    }

    @Test func unsubscribeFinishesStream() async {
        let bus = EventBus()
        let (subscriberId, stream) = await bus.subscribe()

        await bus.unsubscribe(subscriberId)

        var iterator = stream.makeAsyncIterator()
        let event = await iterator.next()
        // Optional 的 == nil 使用 _OptionalNilComparisonType，无 Equatable 要求
        #expect(event == nil)
    }

    @Test func multipleSubscribersEachReceiveEvent() async {
        let bus = EventBus()
        let (_, stream1) = await bus.subscribe()
        let (_, stream2) = await bus.subscribe()

        let paneId = UUID()
        await bus.emit(.paneClosed(paneId: paneId))

        var it1 = stream1.makeAsyncIterator()
        var it2 = stream2.makeAsyncIterator()
        let e1 = await it1.next()
        let e2 = await it2.next()

        guard case .paneClosed(let id1) = e1, case .paneClosed(let id2) = e2 else {
            Issue.record("Expected paneClosed from both subscribers")
            return
        }
        #expect(id1 == paneId)
        #expect(id2 == paneId)
    }
}
