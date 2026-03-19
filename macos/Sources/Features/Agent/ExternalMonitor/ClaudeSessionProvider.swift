// macos/Sources/Features/Agent/ExternalMonitor/ClaudeSessionProvider.swift
import Foundation

// MARK: - 可测试的纯函数解析器

enum ClaudeSessionFileParser {
    struct Entry {
        let pid: Int
        let sessionId: String
        let cwd: String
        let startedAt: Date
    }

    static func parse(json: String) throws -> Entry {
        guard let data = json.data(using: .utf8),
              let obj  = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid  = obj["pid"] as? Int,
              let sid  = obj["sessionId"] as? String,
              let cwd  = obj["cwd"] as? String,
              let ts   = obj["startedAt"] as? Double
        else { throw CocoaError(.fileReadCorruptFile) }
        return Entry(pid: pid, sessionId: sid, cwd: cwd,
                     startedAt: Date(timeIntervalSince1970: ts / 1000))
    }
}

enum ClaudeJsonlParser {
    /// 从 .jsonl 文本中提取最后一条 user/assistant 消息
    static func parseLastMessage(from content: String) -> ExternalSessionRecord.LastMessage? {
        let lines = content.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for line in lines.reversed() {
            guard
                let data = line.data(using: .utf8),
                let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = obj["type"] as? String,
                (type == "user" || type == "assistant"),
                let msg  = obj["message"] as? [String: Any]
            else { continue }

            let role: ExternalSessionRecord.LastMessage.Role = type == "user" ? .user : .assistant
            let rawText = extractText(from: msg["content"])
            guard !rawText.isEmpty else { continue }
            let text = String(rawText.prefix(120))

            let timestamp: Date
            if let tsStr = obj["timestamp"] as? String {
                timestamp = ISO8601DateFormatter().date(from: tsStr) ?? Date()
            } else {
                timestamp = Date()
            }
            return ExternalSessionRecord.LastMessage(role: role, text: text, timestamp: timestamp)
        }
        return nil
    }

    private static func extractText(from content: Any?) -> String {
        if let str = content as? String { return str }
        if let arr = content as? [[String: Any]] {
            return arr.first(where: { $0["type"] as? String == "text" })?["text"] as? String ?? ""
        }
        return ""
    }
}

// MARK: - Provider

@MainActor
final class ClaudeSessionProvider: ExternalAgentProvider {
    let toolType: ExternalToolType = .claudeCode
    private let workspaceDir: String
    private let sessionsDir: String
    private var dirFd: Int32 = -1
    private var dirSource: DispatchSourceFileSystemObject?
    private var jsonlSources: [String: (source: DispatchSourceFileSystemObject, fd: Int32)] = [:]
    private var records: [String: ExternalSessionRecord] = [:]
    private var onChange: (@MainActor () -> Void)?

    init(workspaceDir: String) {
        self.workspaceDir = workspaceDir
        self.sessionsDir = "\(NSHomeDirectory())/.claude/sessions"
    }

    func startWatching(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        scan()
        watchDir()
    }

    func stopWatching() {
        dirSource?.cancel()
        dirSource = nil
        if dirFd >= 0 { close(dirFd); dirFd = -1 }
        jsonlSources.values.forEach { $0.source.cancel() }
        jsonlSources.removeAll()
        records.removeAll()
    }

    func currentSessions() -> [ExternalSessionRecord] {
        Array(records.values)
    }

    // MARK: - Private

    private func watchDir() {
        let fd = open(sessionsDir, O_EVTONLY)
        guard fd >= 0 else { return }
        dirFd = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: .write, queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            DispatchQueue.main.async { self?.scan() }
        }
        source.setCancelHandler { [fd] in close(fd) }
        source.resume()
        dirSource = source
    }

    private func scan() {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: sessionsDir) else { return }
        var found: Set<String> = []

        for file in files where file.hasSuffix(".json") {
            let path = "\(sessionsDir)/\(file)"
            guard let content = try? String(contentsOfFile: path, encoding: .utf8),
                  let entry   = try? ClaudeSessionFileParser.parse(json: content),
                  entry.cwd == workspaceDir
            else { continue }

            let alive = kill(Int32(entry.pid), 0) == 0
            found.insert(entry.sessionId)

            if records[entry.sessionId] == nil {
                var rec = ExternalSessionRecord(
                    id: entry.sessionId, toolType: .claudeCode,
                    pid: entry.pid, cwd: entry.cwd,
                    startedAt: entry.startedAt, isAlive: alive
                )
                rec.lastMessage = parseJsonl(for: entry.sessionId, cwd: entry.cwd)
                records[entry.sessionId] = rec
                if alive { watchJsonl(for: entry.sessionId, cwd: entry.cwd) }
            } else {
                records[entry.sessionId]?.isAlive = alive
                if !alive {
                    jsonlSources[entry.sessionId]?.source.cancel()
                    jsonlSources.removeValue(forKey: entry.sessionId)
                }
            }
        }

        // 移除已消失的 session
        for sid in records.keys where !found.contains(sid) {
            jsonlSources[sid]?.source.cancel()
            jsonlSources.removeValue(forKey: sid)
            records.removeValue(forKey: sid)
        }

        onChange?()
    }

    private func watchJsonl(for sessionId: String, cwd: String) {
        let path = jsonlPath(for: sessionId, cwd: cwd)
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend], queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.records[sessionId]?.lastMessage = self.parseJsonl(for: sessionId, cwd: cwd)
                self.onChange?()
            }
        }
        source.setCancelHandler { [fd] in close(fd) }
        source.resume()
        jsonlSources[sessionId] = (source: source, fd: fd)
    }

    private func parseJsonl(for sessionId: String, cwd: String) -> ExternalSessionRecord.LastMessage? {
        let path = jsonlPath(for: sessionId, cwd: cwd)
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return ClaudeJsonlParser.parseLastMessage(from: content)
    }

    private func jsonlPath(for sessionId: String, cwd: String) -> String {
        let projectDir = cwd.replacingOccurrences(of: "/", with: "-")
        return "\(NSHomeDirectory())/.claude/projects/\(projectDir)/\(sessionId).jsonl"
    }
}
