// macos/Sources/Features/Agent/CtrlServer/CtrlAPIStore.swift
import Foundation

/// 全局 API 调用记录 Store，纯内存，重启清空，上限 500 条
@MainActor
final class CtrlAPIStore: ObservableObject {
    static let shared = CtrlAPIStore()
    private init() {}

    @Published private(set) var records: [CtrlAPIRecord] = []
    @Published var isMonitorVisible: Bool = false
    private let maxRecords = 500

    func append(_ record: CtrlAPIRecord) {
        records.append(record)
        if records.count > maxRecords {
            records.removeFirst(records.count - maxRecords)
        }
    }

    func clear() {
        records.removeAll()
    }
}
