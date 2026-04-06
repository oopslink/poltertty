// macos/Sources/Features/Agent/CtrlServer/EventBus.swift
import Foundation

/// 统一事件分发中心，供 SSE 连接订阅。
/// 所有 emit/subscribe/unsubscribe 均通过 actor 隔离保证并发安全。
actor EventBus {
    static let shared = EventBus()

    enum Event: @unchecked Sendable {
        case hook(HookPayload)
        case paneCreated(paneId: UUID, tabId: UUID, workspaceId: UUID)
        case paneClosed(paneId: UUID)
        case paneFocused(paneId: UUID)
        case tabCreated(tabId: UUID, workspaceId: UUID)
        case tabClosed(tabId: UUID)
        case agentStatusChanged(
            sessionId: String,
            state: String,
            workspaceId: UUID,
            customLabel: String?
        )
        case workspaceSwitched(
            workspaceId: UUID,
            previousWorkspaceId: UUID?
        )
    }

    private var subscribers: [UUID: AsyncStream<Event>.Continuation] = [:]

    func subscribe() -> (subscriberId: UUID, AsyncStream<Event>) {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Event>.makeStream()
        // onTermination 作为双重保障：消费者 Task 取消时自动 unsubscribe
        // EventBus 是单例，self 不会提前释放，强捕获安全
        // unsubscribe 被重复调用是幂等的（removeValue + finish 均安全）
        continuation.onTermination = { [self, id] _ in
            Task { await self.unsubscribe(id) }
        }
        subscribers[id] = continuation
        return (id, stream)
    }

    func unsubscribe(_ id: UUID) {
        subscribers[id]?.finish()
        subscribers.removeValue(forKey: id)
    }

    func emit(_ event: Event) {
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }
}
