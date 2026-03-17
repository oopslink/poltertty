// macos/Sources/Features/Agent/Monitoring/ProcessMonitor.swift
import Foundation

/// 使用 DispatchSource 监听进程退出，作为状态感知的兜底方案
@MainActor
final class ProcessMonitor {
    private var sources: [UUID: DispatchSourceProcess] = [:]

    func watch(pid: Int32, surfaceId: UUID, onExit: @escaping @MainActor (UUID, Int32) -> Void) {
        let source = DispatchSource.makeProcessSource(
            identifier: pid_t(pid), eventMask: .exit, queue: .main
        )
        source.setEventHandler {
            let status = Int32(source.data)
            Task { @MainActor in onExit(surfaceId, status) }
        }
        source.setCancelHandler { [weak self] in
            Task { @MainActor in self?.sources.removeValue(forKey: surfaceId) }
        }
        source.resume()
        sources[surfaceId] = source
    }

    func unwatch(surfaceId: UUID) {
        sources[surfaceId]?.cancel()
        sources.removeValue(forKey: surfaceId)
    }

    func unwatchAll() {
        sources.values.forEach { $0.cancel() }
        sources.removeAll()
    }
}
