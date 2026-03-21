// macos/Sources/Features/Agent/HookServer/HookSessionStore.swift
import Foundation
import OSLog
import Security

struct WrapperSession: Codable {
    let polterttySessionId: String
    let agentSessionId: String
    let agentType: String
    let workspaceId: String
    let surfaceId: String
    let pid: Int32
    let cwd: String
    let token: String
    let port: UInt16              // HookServer 端口，供 poltertty-cli hook 读取
    let startedAt: Date
    var updatedAt: Date
    var endedAt: Date?
}

@MainActor
final class HookSessionStore {
    static let shared = HookSessionStore()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "HookSessionStore"
    )

    private var sessions: [String: WrapperSession] = [:]  // polterttySessionId → session

    private static var sessionsDir: String {
        "\(NSHomeDirectory())/.poltertty/sessions"
    }

    private init() {}

    // MARK: - Token 生成

    static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    // MARK: - Session CRUD

    func create(
        sessionId: String,
        agentSessionId: String,
        agentType: String,
        workspaceId: String,
        surfaceId: String,
        pid: Int32,
        cwd: String,
        port: UInt16
    ) -> WrapperSession {
        let token = Self.generateToken()
        let session = WrapperSession(
            polterttySessionId: sessionId,
            agentSessionId: agentSessionId,
            agentType: agentType,
            workspaceId: workspaceId,
            surfaceId: surfaceId,
            pid: pid,
            cwd: cwd,
            token: token,
            port: port,
            startedAt: Date(),
            updatedAt: Date()
        )
        sessions[sessionId] = session
        persistSession(session)
        return session
    }

    func get(_ sessionId: String) -> WrapperSession? {
        sessions[sessionId]
    }

    func validateToken(sessionId: String, token: String) -> Bool {
        guard let session = sessions[sessionId] else { return false }
        return session.token == token
    }

    func markEnded(_ sessionId: String) {
        sessions[sessionId]?.endedAt = Date()
        sessions[sessionId]?.updatedAt = Date()
        if let session = sessions[sessionId] {
            persistSession(session)
        }
    }

    // MARK: - 持久化

    private func sessionDir(_ sessionId: String) -> String {
        (Self.sessionsDir as NSString).appendingPathComponent(sessionId)
    }

    private func persistSession(_ session: WrapperSession) {
        let dir = sessionDir(session.polterttySessionId)
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let metaURL = URL(fileURLWithPath: (dir as NSString).appendingPathComponent("meta.json"))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(session) {
            try? data.write(to: metaURL, options: .atomic)
            // chmod 600
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metaURL.path)
        }
    }

    // MARK: - Stale 清理

    func cleanupStale() {
        // PID 检测：遍历活跃 session，检查进程是否存活
        for (id, session) in sessions where session.endedAt == nil {
            if kill(session.pid, 0) != 0 {
                logger.info("Stale session detected (pid \(session.pid) dead): \(id)")
                markEnded(id)
            }
        }

        // 过期清理：endedAt 超过 7 天的目录删除
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        let fm = FileManager.default
        for (id, session) in sessions {
            if let ended = session.endedAt, ended < cutoff {
                let dir = sessionDir(id)
                try? fm.removeItem(atPath: dir)
                sessions.removeValue(forKey: id)
                logger.info("Removed expired session dir: \(id)")
            }
        }
    }

    func loadFromDisk() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: Self.sessionsDir) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        for entry in entries {
            let metaPath = (Self.sessionsDir as NSString)
                .appendingPathComponent(entry)
                .appending("/meta.json")
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
                  let session = try? decoder.decode(WrapperSession.self, from: data) else { continue }
            sessions[session.polterttySessionId] = session
        }
        logger.info("Loaded \(sessions.count) wrapper sessions from disk")
    }
}
