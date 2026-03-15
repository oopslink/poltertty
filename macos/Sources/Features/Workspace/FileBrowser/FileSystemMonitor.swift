// macos/Sources/Features/Workspace/FileBrowser/FileSystemMonitor.swift
import Foundation
import CoreServices

/// FSEventStream wrapper that watches rootDir for file system changes.
/// Fires onChange on the main thread with 300ms debounce.
final class FileSystemMonitor {
    private var stream: FSEventStreamRef?
    private let rootDir: String
    private let queue = DispatchQueue(label: "poltertty.fsevents", qos: .utility)
    private var debounceWorkItem: DispatchWorkItem?

    /// Called on the main thread when file system changes are detected
    var onChange: (() -> Void)?

    init(rootDir: String) {
        self.rootDir = rootDir
    }

    deinit {
        stop()
    }

    func start() {
        guard !rootDir.isEmpty,
              FileManager.default.fileExists(atPath: rootDir),
              stream == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let paths = [rootDir] as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let monitor = Unmanaged<FileSystemMonitor>.fromOpaque(info).takeUnretainedValue()
            monitor.scheduleReload()
        }

        guard let newStream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            flags
        ) else { return }

        stream = newStream
        FSEventStreamSetDispatchQueue(newStream, queue)
        FSEventStreamStart(newStream)
    }

    func stop() {
        debounceWorkItem?.cancel()
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    private func scheduleReload() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                self?.onChange?()
            }
        }
        debounceWorkItem = item
        queue.asyncAfter(deadline: .now() + 0.3, execute: item)
    }
}
