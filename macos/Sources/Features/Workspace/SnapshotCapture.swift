import AppKit

/// 捕获 NSWindow 内容区域的 JPEG 截图
enum SnapshotCapture {
    /// 返回 JPEG Data，失败返回 nil（不抛出）
    /// 不需要 Screen Recording 权限（仅捕获自身 App 的 View 层级）
    static func capture(window: NSWindow) -> Data? {
        guard let contentView = window.contentView else { return nil }
        let bounds = contentView.bounds
        // bitmapImageRepForCachingDisplay 在 macOS 14 被标记废弃，但 macOS 上暂无官方等效替代。
        // 此方案仅捕获 App 自身 View 层级，无需 Screen Recording 权限，保留使用。
        guard let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        contentView.cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.6])
    }
}
