// macos/Sources/Features/Agent/ExternalMonitor/OpenCodeSessionProvider.swift
import Foundation
import SQLite3

@MainActor
final class OpenCodeSessionProvider: ExternalAgentProvider {
    let toolType: ExternalToolType = .openCode
    private let workspaceDir: String
    private let dbPath: String
    private var dbFileSource: DispatchSourceFileSystemObject?
    private var cachedRecords: [ExternalSessionRecord] = []
    private var onChange: (@MainActor () -> Void)?

    init(workspaceDir: String) {
        self.workspaceDir = workspaceDir
        self.dbPath = "\(NSHomeDirectory())/.local/share/opencode/opencode.db"
    }

    func startWatching(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        queryDB()
        watchDBFile()
    }

    func stopWatching() {
        dbFileSource?.cancel()   // cancelHandler closes fd
        dbFileSource = nil
        cachedRecords.removeAll()
    }

    func currentSessions() -> [ExternalSessionRecord] { cachedRecords }

    // MARK: - isAlive (static for testability)

    nonisolated static func isAliveByTime(lastUpdated: Date, window: TimeInterval = 300) -> Bool {
        Date().timeIntervalSince(lastUpdated) < window
    }

    // MARK: - Private

    private func watchDBFile() {
        guard FileManager.default.fileExists(atPath: dbPath) else { return }
        let fd = open(dbPath, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend], queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            DispatchQueue.main.async { self?.queryDB() }
        }
        source.setCancelHandler { [fd] in close(fd) }
        source.resume()
        dbFileSource = source
    }

    private func queryDB() {
        guard FileManager.default.fileExists(atPath: dbPath) else { return }
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 500)

        let sql = """
        SELECT s.id, s.directory, s.time_created, s.time_updated,
               m.data AS last_msg
        FROM session s
        LEFT JOIN (
            SELECT session_id, data
            FROM message
            WHERE rowid IN (SELECT MAX(rowid) FROM message GROUP BY session_id)
        ) m ON m.session_id = s.id
        WHERE s.directory = ? AND s.time_archived IS NULL
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, workspaceDir, -1, unsafeBitCast(-1 as Int, to: sqlite3_destructor_type.self))

        var results: [ExternalSessionRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idPtr  = sqlite3_column_text(stmt, 0),
                  let dirPtr = sqlite3_column_text(stmt, 1)
            else { continue }

            let id          = String(cString: idPtr)
            let directory   = String(cString: dirPtr)
            let created     = sqlite3_column_int64(stmt, 2)   // ms
            let updated     = sqlite3_column_int64(stmt, 3)   // ms
            let lastUpdated = Date(timeIntervalSince1970: Double(updated) / 1000)
            let alive       = OpenCodeSessionProvider.isAliveByTime(lastUpdated: lastUpdated)

            var lastMsg: ExternalSessionRecord.LastMessage?
            if let msgPtr = sqlite3_column_text(stmt, 4) {
                lastMsg = parseMessage(String(cString: msgPtr))
            }

            results.append(ExternalSessionRecord(
                id: id, toolType: .openCode, pid: nil,
                cwd: directory,
                startedAt: Date(timeIntervalSince1970: Double(created) / 1000),
                isAlive: alive,
                lastMessage: lastMsg
            ))
        }
        cachedRecords = results
        onChange?()
    }

    private func parseMessage(_ json: String) -> ExternalSessionRecord.LastMessage? {
        guard let data = json.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let role = obj["role"] as? String
        else { return nil }

        let mappedRole: ExternalSessionRecord.LastMessage.Role =
            role == "assistant" ? .assistant : .user

        let rawText: String
        if let str = obj["content"] as? String {
            rawText = str
        } else if let arr = obj["content"] as? [[String: Any]] {
            rawText = arr.first(where: { $0["type"] as? String == "text" })?["text"] as? String ?? ""
        } else {
            return nil
        }
        guard !rawText.isEmpty else { return nil }
        return ExternalSessionRecord.LastMessage(
            role: mappedRole, text: String(rawText.prefix(120)), timestamp: Date()
        )
    }
}
