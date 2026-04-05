# Sidebar Workspace Metadata 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在侧边栏每个 Workspace 条目下展示监听端口徽标、PR 状态徽标、Agent 活跃指示器，折叠状态下以三色小点呈现。

**Architecture:** 新增 `WorkspaceMetadataStore`（@MainActor 单例），统一管理三条数据通道——端口（5s lsof 轮询）、PR（60s gh CLI 刷新）、Agent（订阅 ExternalSessionDiscovery）；`ExpandedWorkspaceItem` 在路径行下增加徽标行（方案 A），`CollapsedWorkspaceIcon` 在图标下增加三点行（方案 X）。

**Tech Stack:** Swift 6, Swift Testing (`import Testing`), Combine, lsof, gh CLI, ExternalSessionDiscovery

**设计稿参考:** `.superpowers/brainstorm/42210-1775360708/sidebar-metadata-design.png`

**UI/UX 测试要求:** 每个 UI Task 完成后用 screencapture 截图与设计稿比对，确认色调、间距、徽标格式与设计稿一致。

---

## 文件清单

| 操作 | 路径 | 职责 |
|------|------|------|
| 新建 | `macos/Sources/Features/Workspace/Metadata/WorkspaceMetadata.swift` | 数据类型定义（WorkspaceMetadata / PRStatus / AgentState） |
| 新建 | `macos/Sources/Features/Workspace/Metadata/PortScanner.swift` | lsof 解析 + 端口归属逻辑 |
| 新建 | `macos/Sources/Features/Workspace/Metadata/PRStatusFetcher.swift` | gh CLI 调用 + JSON 解析 |
| 新建 | `macos/Sources/Features/Workspace/Metadata/WorkspaceMetadataStore.swift` | 三通道协调 + 生命周期管理 |
| 新建 | `macos/Tests/Workspace/PortScannerTests.swift` | PortScanner 解析逻辑单元测试 |
| 新建 | `macos/Tests/Workspace/PRStatusFetcherTests.swift` | PRStatusFetcher JSON 解析单元测试 |
| 修改 | `macos/Sources/Features/Workspace/WorkspaceSidebar.swift` | 注入 metadataStore；更新 ExpandedWorkspaceItem + CollapsedWorkspaceIcon |
| 修改 | `macos/Sources/Features/Workspace/PolterttyRootView.swift` | 处理 openURLInBrowserPanel 通知；启动 WorkspaceMetadataStore |

---

## Task 1: WorkspaceMetadata 类型定义

**Files:**
- Create: `macos/Sources/Features/Workspace/Metadata/WorkspaceMetadata.swift`

- [ ] **Step 1: 创建类型文件**

```swift
// macos/Sources/Features/Workspace/Metadata/WorkspaceMetadata.swift
import Foundation

struct WorkspaceMetadata: Equatable {
    var listeningPorts: [Int] = []
    var prStatus: PRStatus? = nil
    var agentState: AgentState = .none
}

enum PRStatus: Equatable {
    case open(number: Int)
    case draft(number: Int)
    case merged(number: Int)

    var displayText: String {
        switch self {
        case .open(let n):   return "#\(n) Open"
        case .draft(let n):  return "#\(n) Draft"
        case .merged(let n): return "#\(n) Merged"
        }
    }
}

enum AgentState: Equatable {
    case none     // 无 session
    case idle     // session 存在但全部不再存活
    case working  // 至少一个 session isAlive
}
```

- [ ] **Step 2: 构建确认**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty
swift build --target Ghostty 2>&1 | grep -E "error:|Build complete"
```

期望：`Build complete!`（无 error）

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/Features/Workspace/Metadata/WorkspaceMetadata.swift
git commit -m "feat(metadata): add WorkspaceMetadata, PRStatus, AgentState types"
```

---

## Task 2: PortScanner — lsof 解析与端口归属

**Files:**
- Create: `macos/Sources/Features/Workspace/Metadata/PortScanner.swift`
- Create: `macos/Tests/Workspace/PortScannerTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
// macos/Tests/Workspace/PortScannerTests.swift
import Testing
import Foundation
@testable import Ghostty

struct PortScannerTests {

    // MARK: - parseListenOutput

    @Test func parsesListenOutputBasic() {
        let output = """
        p1234
        n*:3000
        p5678
        n127.0.0.1:8080
        """
        let entries = PortScanner.parseListenOutput(output)
        #expect(entries.count == 2)
        #expect(entries[0].port == 3000)
        #expect(entries[0].pid  == 1234)
        #expect(entries[1].port == 8080)
        #expect(entries[1].pid  == 5678)
    }

    @Test func ignoresNonPortLines() {
        let output = "pfoo\nnnotaport\n"
        let entries = PortScanner.parseListenOutput(output)
        #expect(entries.isEmpty)
    }

    // MARK: - parseCwdOutput

    @Test func parsesCwdOutput() {
        let output = """
        p1234
        n/Users/foo/myproject
        p5678
        n/Users/foo/other
        """
        let cwds = PortScanner.parseCwdOutput(output)
        #expect(cwds[1234] == "/Users/foo/myproject")
        #expect(cwds[5678] == "/Users/foo/other")
    }

    // MARK: - assignPorts

    @Test func assignsPortByRootDirPrefix() {
        let entries = [
            PortScanner.ListenEntry(port: 3000, pid: 1),
            PortScanner.ListenEntry(port: 8080, pid: 2),
        ]
        let cwds: [Int: String] = [
            1: "/Users/foo/project-a/server",
            2: "/Users/foo/project-b",
        ]
        let idA = UUID()
        let idB = UUID()
        let workspaces: [(id: UUID, rootDir: String)] = [
            (idA, "/Users/foo/project-a"),
            (idB, "/Users/foo/project-b"),
        ]
        let result = PortScanner.assignPorts(entries, cwds: cwds, workspaces: workspaces)
        #expect(result[idA] == [3000])
        #expect(result[idB] == [8080])
    }

    @Test func dropsPortWithNoCwdMatch() {
        let entries = [PortScanner.ListenEntry(port: 9999, pid: 99)]
        let cwds: [Int: String] = [99: "/tmp/unrelated"]
        let idA = UUID()
        let result = PortScanner.assignPorts(entries, cwds: cwds, workspaces: [(idA, "/Users/foo/project")])
        #expect(result.isEmpty)
    }

    @Test func expandsTildaInRootDir() {
        let entries = [PortScanner.ListenEntry(port: 3000, pid: 1)]
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let cwds: [Int: String] = [1: "\(home)/myproject/src"]
        let idA = UUID()
        let result = PortScanner.assignPorts(entries, cwds: cwds, workspaces: [(idA, "~/myproject")])
        #expect(result[idA] == [3000])
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /Users/oopslink/works/codes/oopslink/poltertty
swift test --filter PortScannerTests 2>&1 | tail -20
```

期望：编译错误（PortScanner 尚不存在）

- [ ] **Step 3: 实现 PortScanner**

```swift
// macos/Sources/Features/Workspace/Metadata/PortScanner.swift
import Foundation

enum PortScanner {
    struct ListenEntry {
        let port: Int
        let pid: Int
    }

    /// 解析 `lsof -iTCP -sTCP:LISTEN -Pn -F pn` 输出
    static func parseListenOutput(_ output: String) -> [ListenEntry] {
        var results: [ListenEntry] = []
        var currentPid: Int? = nil
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("p"), let pid = Int(line.dropFirst()) {
                currentPid = pid
            } else if line.hasPrefix("n"), let pid = currentPid {
                let name = String(line.dropFirst())  // e.g. "*:3000" or "127.0.0.1:8080"
                if let colonIdx = name.lastIndex(of: ":"),
                   let port = Int(name[name.index(after: colonIdx)...]) {
                    results.append(ListenEntry(port: port, pid: pid))
                }
            }
        }
        return results
    }

    /// 解析 `lsof -p <pids> -d cwd -F pn` 输出，返回 pid → cwd
    static func parseCwdOutput(_ output: String) -> [Int: String] {
        var result: [Int: String] = [:]
        var currentPid: Int? = nil
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("p"), let pid = Int(line.dropFirst()) {
                currentPid = pid
            } else if line.hasPrefix("n"), let pid = currentPid {
                result[pid] = String(line.dropFirst())
            }
        }
        return result
    }

    /// 将 ListenEntry 列表按 rootDir 前缀归属到各 workspace
    static func assignPorts(
        _ entries: [ListenEntry],
        cwds: [Int: String],
        workspaces: [(id: UUID, rootDir: String)]
    ) -> [UUID: [Int]] {
        var portsByWorkspace: [UUID: [Int]] = [:]
        let expandedWorkspaces = workspaces.map { (id: $0.id, rootDir: ($0.rootDir as NSString).expandingTildeInPath) }
        for entry in entries {
            guard let cwd = cwds[entry.pid] else { continue }
            for ws in expandedWorkspaces {
                if cwd == ws.rootDir || cwd.hasPrefix(ws.rootDir + "/") {
                    portsByWorkspace[ws.id, default: []].append(entry.port)
                    break
                }
            }
        }
        return portsByWorkspace
    }

    /// 实际扫描：运行 lsof 并归属端口到各 workspace（在后台线程执行）
    static func scan(workspaces: [(id: UUID, rootDir: String)]) async -> [UUID: [Int]] {
        guard !workspaces.isEmpty else { return [:] }

        // 1. 获取所有监听端口 + PID
        let listenOutput = await runCommand("/usr/sbin/lsof", args: ["-iTCP", "-sTCP:LISTEN", "-Pn", "-F", "pn"])
        let entries = parseListenOutput(listenOutput)
        guard !entries.isEmpty else { return [:] }

        // 2. 批量查询这些 PID 的工作目录
        let pids = Array(Set(entries.map { $0.pid })).map { String($0) }.joined(separator: ",")
        let cwdOutput = await runCommand("/usr/sbin/lsof", args: ["-p", pids, "-d", "cwd", "-F", "pn"])
        let cwds = parseCwdOutput(cwdOutput)

        // 3. 归属
        return assignPorts(entries, cwds: cwds, workspaces: workspaces)
    }

    private static func runCommand(_ path: String, args: [String]) async -> String {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            } catch {
                continuation.resume(returning: "")
            }
        }
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
swift test --filter PortScannerTests 2>&1 | tail -20
```

期望：所有测试 PASS

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Workspace/Metadata/PortScanner.swift \
        macos/Tests/Workspace/PortScannerTests.swift
git commit -m "feat(metadata): add PortScanner with lsof parsing and workspace assignment"
```

---

## Task 3: PRStatusFetcher — gh CLI 集成

**Files:**
- Create: `macos/Sources/Features/Workspace/Metadata/PRStatusFetcher.swift`
- Create: `macos/Tests/Workspace/PRStatusFetcherTests.swift`

- [ ] **Step 1: 写失败测试（仅测试 JSON 解析，不调用真实 gh）**

```swift
// macos/Tests/Workspace/PRStatusFetcherTests.swift
import Testing
import Foundation
@testable import Ghostty

struct PRStatusFetcherTests {

    @Test func parsesOpenPR() throws {
        let json = #"{"number":152,"state":"OPEN","isDraft":false}"#
        let status = PRStatusFetcher.parseJSON(json.data(using: .utf8)!)
        #expect(status == .open(number: 152))
    }

    @Test func parsesDraftPR() throws {
        let json = #"{"number":89,"state":"OPEN","isDraft":true}"#
        let status = PRStatusFetcher.parseJSON(json.data(using: .utf8)!)
        #expect(status == .draft(number: 89))
    }

    @Test func parsesMergedPR() throws {
        let json = #"{"number":77,"state":"MERGED","isDraft":false}"#
        let status = PRStatusFetcher.parseJSON(json.data(using: .utf8)!)
        #expect(status == .merged(number: 77))
    }

    @Test func returnsNilForClosedPR() throws {
        let json = #"{"number":10,"state":"CLOSED","isDraft":false}"#
        let status = PRStatusFetcher.parseJSON(json.data(using: .utf8)!)
        #expect(status == nil)
    }

    @Test func returnsNilForInvalidJSON() {
        let status = PRStatusFetcher.parseJSON(Data())
        #expect(status == nil)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
swift test --filter PRStatusFetcherTests 2>&1 | tail -10
```

期望：编译错误（PRStatusFetcher 尚不存在）

- [ ] **Step 3: 实现 PRStatusFetcher**

```swift
// macos/Sources/Features/Workspace/Metadata/PRStatusFetcher.swift
import Foundation

enum PRStatusFetcher {
    private struct Response: Decodable {
        let number: Int
        let state: String
        let isDraft: Bool
    }

    /// 解析 `gh pr view --json number,state,isDraft` 的输出
    static func parseJSON(_ data: Data) -> PRStatus? {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        if response.isDraft { return .draft(number: response.number) }
        switch response.state.uppercased() {
        case "OPEN":   return .open(number: response.number)
        case "MERGED": return .merged(number: response.number)
        default:       return nil
        }
    }

    /// 实际调用 gh CLI，在后台线程执行
    static func fetch(rootDir: String) async -> PRStatus? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["gh", "pr", "view", "--json", "number,state,isDraft"]
            process.currentDirectoryURL = URL(fileURLWithPath: (rootDir as NSString).expandingTildeInPath)
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: parseJSON(data))
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
swift test --filter PRStatusFetcherTests 2>&1 | tail -10
```

期望：所有测试 PASS

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Workspace/Metadata/PRStatusFetcher.swift \
        macos/Tests/Workspace/PRStatusFetcherTests.swift
git commit -m "feat(metadata): add PRStatusFetcher with gh CLI integration"
```

---

## Task 4: WorkspaceMetadataStore — 三通道协调

**Files:**
- Create: `macos/Sources/Features/Workspace/Metadata/WorkspaceMetadataStore.swift`

- [ ] **Step 1: 实现 WorkspaceMetadataStore**

```swift
// macos/Sources/Features/Workspace/Metadata/WorkspaceMetadataStore.swift
import Foundation
import Combine

@MainActor
final class WorkspaceMetadataStore: ObservableObject {
    static let shared = WorkspaceMetadataStore()

    @Published private(set) var metadata: [UUID: WorkspaceMetadata] = [:]

    private var portScanTask: Task<Void, Never>?
    private var prTasks: [UUID: Task<Void, Never>] = [:]
    private var discoveries: [UUID: ExternalSessionDiscovery] = [:]
    private var discoveryCancellables: [UUID: AnyCancellable] = [:]
    private var workspacesCancellable: AnyCancellable?

    private init() {}

    // MARK: - 启动

    func start() {
        // 订阅 WorkspaceManager 的 workspaces 变化
        workspacesCancellable = WorkspaceManager.shared.$workspaces
            .receive(on: RunLoop.main)
            .sink { [weak self] workspaces in
                self?.syncWorkspaces(workspaces)
            }
        startPortScanLoop()
    }

    // MARK: - 端口扫描（5s 轮询）

    private func startPortScanLoop() {
        portScanTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let workspaces = WorkspaceManager.shared.workspaces.map { (id: $0.id, rootDir: $0.rootDir) }
                let portMap = await PortScanner.scan(workspaces: workspaces)
                guard !Task.isCancelled else { return }
                for (id, ports) in portMap {
                    let sorted = Array(Set(ports)).sorted()
                    self.metadata[id, default: WorkspaceMetadata()].listeningPorts = sorted
                }
                // 清空无端口的 workspace
                for id in self.metadata.keys where portMap[id] == nil {
                    self.metadata[id]?.listeningPorts = []
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    // MARK: - PR 状态（60s TTL，workspace 粒度）

    private func startPRRefresh(for workspace: WorkspaceModel) {
        let id = workspace.id
        let rootDir = workspace.rootDir
        prTasks[id] = Task { [weak self] in
            while !Task.isCancelled {
                let status = await PRStatusFetcher.fetch(rootDir: rootDir)
                guard let self, !Task.isCancelled else { return }
                self.metadata[id, default: WorkspaceMetadata()].prStatus = status
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    // MARK: - Agent 状态（订阅 ExternalSessionDiscovery）

    private func startAgentTracking(for workspace: WorkspaceModel) {
        let id = workspace.id
        let rootDir = workspace.rootDirExpanded
        guard !rootDir.isEmpty else { return }
        let discovery = ExternalSessionDiscovery(workspaceRootDir: rootDir)
        discoveries[id] = discovery
        discoveryCancellables[id] = discovery.$sessions
            .receive(on: RunLoop.main)
            .sink { [weak self] sessions in
                guard let self else { return }
                let state: AgentState
                if sessions.isEmpty {
                    state = .none
                } else if sessions.contains(where: { $0.isAlive }) {
                    state = .working
                } else {
                    state = .idle
                }
                self.metadata[id, default: WorkspaceMetadata()].agentState = state
            }
        discovery.start()
    }

    // MARK: - 生命周期同步

    private func syncWorkspaces(_ workspaces: [WorkspaceModel]) {
        let currentIds = Set(workspaces.map { $0.id })
        let trackedIds = Set(prTasks.keys)

        // 新增 workspace → 开始追踪
        for ws in workspaces where !trackedIds.contains(ws.id) {
            startPRRefresh(for: ws)
            startAgentTracking(for: ws)
        }

        // 移除的 workspace → 停止追踪 + 清空数据
        for id in trackedIds where !currentIds.contains(id) {
            prTasks[id]?.cancel()
            prTasks.removeValue(forKey: id)
            discoveries[id]?.stop()
            discoveries.removeValue(forKey: id)
            discoveryCancellables.removeValue(forKey: id)
            metadata.removeValue(forKey: id)
        }
    }
}
```

- [ ] **Step 2: 给 WorkspaceModel 添加 rootDirExpanded（如果还没有）**

检查 WorkspaceModel 是否有 `rootDirExpanded`：

```bash
grep -n "rootDirExpanded" macos/Sources/Features/Workspace/WorkspaceModel.swift
```

若没有，在 `WorkspaceModel.swift` 中添加：

```swift
var rootDirExpanded: String {
    (rootDir as NSString).expandingTildeInPath
}
```

- [ ] **Step 3: 构建确认**

```bash
swift build --target Ghostty 2>&1 | grep -E "error:|Build complete"
```

期望：`Build complete!`

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Workspace/Metadata/WorkspaceMetadataStore.swift
git commit -m "feat(metadata): add WorkspaceMetadataStore with port/PR/agent tracking"
```

---

## Task 5: ExpandedWorkspaceItem — 徽标行（方案 A）

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceSidebar.swift`（`ExpandedWorkspaceItem` 部分）

**设计稿对照：** 参考 `.superpowers/brainstorm/42210-1775360708/sidebar-metadata-design.png` 方案 A 区域：蓝色端口徽标、绿色 Open PR、灰色 Draft、黄色脉冲 Working

- [ ] **Step 1: 给 ExpandedWorkspaceItem 添加 metadata 参数和徽标行**

在 `WorkspaceSidebar.swift` 找到 `struct ExpandedWorkspaceItem: View`（第 778 行），做以下修改：

① 在现有属性列表末尾添加参数：

```swift
var metadata: WorkspaceMetadata = WorkspaceMetadata()
var onOpenPort: ((Int) -> Void)? = nil
```

② 在 `VStack(alignment: .leading, spacing: 2)` 内，`Text(workspace.rootDir)` 行的**下方**追加徽标行：

```swift
if !metadata.listeningPorts.isEmpty || metadata.prStatus != nil || metadata.agentState != .none {
    WorkspaceMetadataBadgeRow(metadata: metadata, onOpenPort: onOpenPort)
}
```

- [ ] **Step 2: 新增 WorkspaceMetadataBadgeRow 视图**

在 `WorkspaceSidebar.swift` 末尾（`GroupHeaderRow` 之前）添加：

```swift
// MARK: - Metadata Badge Row

private struct WorkspaceMetadataBadgeRow: View {
    let metadata: WorkspaceMetadata
    var onOpenPort: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 3) {
            // 端口徽标（最多 3 个 + "+N"）
            let ports = metadata.listeningPorts
            let displayPorts = Array(ports.prefix(3))
            let overflow = ports.count - displayPorts.count
            ForEach(displayPorts, id: \.self) { port in
                Button(action: { onOpenPort?(port) }) {
                    Text(":\(port)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.58, green: 0.77, blue: 0.99))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(red: 0.23, green: 0.51, blue: 0.95).opacity(0.18))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(Color(red: 0.23, green: 0.51, blue: 0.95).opacity(0.25), lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(.plain)
                .help("在 Browser Panel 打开 http://localhost:\(port)")
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // PR 状态徽标
            if let pr = metadata.prStatus {
                PRBadgeView(status: pr)
            }

            // Agent 状态徽标
            if metadata.agentState != .none {
                AgentStateBadgeView(state: metadata.agentState)
            }
        }
    }
}

private struct PRBadgeView: View {
    let status: PRStatus

    private var textColor: Color {
        switch status {
        case .open:   return Color(red: 0.53, green: 0.94, blue: 0.67)
        case .draft:  return Color(nsColor: .tertiaryLabelColor)
        case .merged: return Color(red: 0.77, green: 0.71, blue: 0.99)
        }
    }
    private var bgColor: Color {
        switch status {
        case .open:   return Color(red: 0.13, green: 0.77, blue: 0.37).opacity(0.14)
        case .draft:  return Color.primary.opacity(0.07)
        case .merged: return Color(red: 0.55, green: 0.36, blue: 0.97).opacity(0.14)
        }
    }
    private var borderColor: Color {
        switch status {
        case .open:   return Color(red: 0.13, green: 0.77, blue: 0.37).opacity(0.22)
        case .draft:  return Color.primary.opacity(0.12)
        case .merged: return Color(red: 0.55, green: 0.36, blue: 0.97).opacity(0.22)
        }
    }

    var body: some View {
        Text(status.displayText)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(bgColor)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(borderColor, lineWidth: 0.5))
            )
    }
}

private struct AgentStateBadgeView: View {
    let state: AgentState
    @State private var pulseOpacity: Double = 1.0

    private var dotColor: Color {
        state == .working ? Color(red: 0.99, green: 0.82, blue: 0.30) : Color(nsColor: .tertiaryLabelColor)
    }
    private var textColor: Color {
        state == .working ? Color(red: 0.99, green: 0.85, blue: 0.42) : Color(nsColor: .secondaryLabelColor)
    }
    private var bgColor: Color {
        state == .working
            ? Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.14)
            : Color.primary.opacity(0.07)
    }
    private var borderColor: Color {
        state == .working
            ? Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.22)
            : Color.primary.opacity(0.12)
    }
    private var label: String { state == .working ? "Working" : "Idle" }

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(dotColor)
                .frame(width: 5, height: 5)
                .opacity(state == .working ? pulseOpacity : 1.0)
                .animation(
                    state == .working
                        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                        : .default,
                    value: pulseOpacity
                )
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(textColor)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(bgColor)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(borderColor, lineWidth: 0.5))
        )
        .onAppear {
            if state == .working { pulseOpacity = 0.25 }
        }
    }
}
```

- [ ] **Step 3: 构建确认**

```bash
swift build --target Ghostty 2>&1 | grep -E "error:|Build complete"
```

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceSidebar.swift
git commit -m "feat(metadata): add badge row to ExpandedWorkspaceItem (expanded sidebar A)"
```

---

## Task 6: CollapsedWorkspaceIcon — 三点行（方案 X）

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceSidebar.swift`（`CollapsedWorkspaceIcon` 部分）

**设计稿对照：** 参考设计稿方案 X 区域：图标下方三点（蓝=端口、黄闪=agent、绿/灰=PR）

- [ ] **Step 1: 给 CollapsedWorkspaceIcon 添加 metadata 参数**

在 `struct CollapsedWorkspaceIcon: View` 的属性列表中添加：

```swift
var metadata: WorkspaceMetadata = WorkspaceMetadata()
```

- [ ] **Step 2: 修改 CollapsedWorkspaceIcon 的 body**

将现有 `Button(action: onTap)` 外层结构改为 `VStack(spacing: 3)`，图标下方追加三点行。

找到 CollapsedWorkspaceIcon 的 `var body: some View` 返回值，将 `Button(action: onTap) { ... }` 包裹在 VStack 中：

```swift
var body: some View {
    VStack(spacing: 3) {
        Button(action: onTap) {
            // （现有图标代码保持不变）
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isActive ? .white.opacity(0.9) : .clear, lineWidth: 2)
                    )
                    .shadow(color: isActive ? workspace.color.opacity(0.5) : .clear, radius: 4)
                Text(workspace.icon)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(iconTextColor)
            }
            .frame(width: 32, height: 32)
            .overlay(alignment: .topTrailing) {
                if unreadCount > 0 {
                    Text("\(min(unreadCount, 99))")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.red))
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(tooltipText)
        .contextMenu { /* 保持现有 contextMenu 不变，略 */ }
        .onTapGesture(count: 2) {}

        // 三点行
        CollapsedMetadataDots(metadata: metadata)
    }
}
```

- [ ] **Step 3: 新增 CollapsedMetadataDots 视图**

紧接在 `WorkspaceMetadataBadgeRow` 上方添加：

```swift
// MARK: - Collapsed Metadata Dots

private struct CollapsedMetadataDots: View {
    let metadata: WorkspaceMetadata
    @State private var pulseOpacity: Double = 1.0

    private var hasPort: Bool { !metadata.listeningPorts.isEmpty }
    private var portTooltip: String {
        metadata.listeningPorts.prefix(3).map { ":\($0)" }.joined(separator: " ")
    }

    var body: some View {
        HStack(spacing: 4) {
            // 左点：端口（蓝）
            Circle()
                .fill(hasPort ? Color(red: 0.58, green: 0.77, blue: 0.99) : Color.clear)
                .frame(width: 5, height: 5)
                .help(hasPort ? portTooltip : "")

            // 中点：Agent（黄闪=working，灰=idle，透明=none）
            agentDot

            // 右点：PR（绿=open，灰=draft，透明=none）
            prDot
        }
        .frame(height: 8)
        .onAppear {
            if metadata.agentState == .working { pulseOpacity = 0.2 }
        }
    }

    private var agentDot: some View {
        let color: Color
        switch metadata.agentState {
        case .working: color = Color(red: 0.99, green: 0.82, blue: 0.30)
        case .idle:    color = Color(nsColor: .tertiaryLabelColor)
        case .none:    color = .clear
        }
        return Circle()
            .fill(color)
            .frame(width: 5, height: 5)
            .opacity(metadata.agentState == .working ? pulseOpacity : 1.0)
            .animation(
                metadata.agentState == .working
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: pulseOpacity
            )
            .help(metadata.agentState == .none ? "" : (metadata.agentState == .working ? "Agent Working" : "Agent Idle"))
    }

    private var prDot: some View {
        let color: Color
        let tooltip: String
        switch metadata.prStatus {
        case .open:    color = Color(red: 0.53, green: 0.94, blue: 0.67); tooltip = "PR Open"
        case .draft:   color = Color(nsColor: .tertiaryLabelColor); tooltip = "PR Draft"
        case .merged:  color = Color(red: 0.77, green: 0.71, blue: 0.99); tooltip = "PR Merged"
        case .none:    color = .clear; tooltip = ""
        }
        return Circle()
            .fill(color)
            .frame(width: 5, height: 5)
            .help(tooltip)
    }
}
```

- [ ] **Step 4: 构建确认**

```bash
swift build --target Ghostty 2>&1 | grep -E "error:|Build complete"
```

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceSidebar.swift
git commit -m "feat(metadata): add three-dot row to CollapsedWorkspaceIcon (collapsed sidebar X)"
```

---

## Task 7: 接线 — WorkspaceSidebar + PolterttyRootView

**Files:**
- Modify: `macos/Sources/Features/Workspace/WorkspaceSidebar.swift`
- Modify: `macos/Sources/Features/Workspace/PolterttyRootView.swift`

- [ ] **Step 1: WorkspaceSidebar 注入 metadataStore**

在 `struct WorkspaceSidebar: View` 的属性列表中追加：

```swift
@ObservedObject private var metadataStore = WorkspaceMetadataStore.shared
```

- [ ] **Step 2: 向 ExpandedWorkspaceItem 传入 metadata 和 onOpenPort**

找到 `ungroupedSection` 和 group/temporary 区域中所有 `ExpandedWorkspaceItem(...)` 调用，追加两个参数：

```swift
metadata: metadataStore.metadata[workspace.id] ?? WorkspaceMetadata(),
onOpenPort: { port in
    NotificationCenter.default.post(
        name: .openURLInBrowserPanel,
        object: nil,
        userInfo: [
            "url": URL(string: "http://localhost:\(port)")!,
            "workspaceId": workspace.id
        ]
    )
}
```

（共有 3 处：ungroupedSection、group 展开区、temporary 区——每处都要加）

- [ ] **Step 3: 向 CollapsedWorkspaceIcon 传入 metadata**

找到所有 `CollapsedWorkspaceIcon(...)` 调用（共 3 处），追加：

```swift
metadata: metadataStore.metadata[workspace.id] ?? WorkspaceMetadata(),
```

- [ ] **Step 4: 注册新通知名**

在 `PolterttyRootView.swift` 的 `extension Notification.Name` 块中追加：

```swift
static let openURLInBrowserPanel = Notification.Name("poltertty.openURLInBrowserPanel")
```

- [ ] **Step 5: PolterttyRootView 处理通知并启动 Store**

在 `PolterttyRootView` 的 `body` 中，找到 `.onReceive(NotificationCenter.default.publisher(for: .toggleBrowserPanel))` 一块，**紧随其后**追加：

```swift
.onReceive(NotificationCenter.default.publisher(for: .openURLInBrowserPanel)) { notification in
    guard let url = notification.userInfo?["url"] as? URL,
          let wsId = notification.userInfo?["workspaceId"] as? UUID,
          wsId == workspaceId else { return }
    browserPanelVisible = true
    let mgr = browserStore.manager(for: wsId)
    mgr.newTab(url: url)
}
```

在 `.onAppear` 中追加（或新增 `.onAppear` 如果不存在）：

```swift
.onAppear {
    WorkspaceMetadataStore.shared.start()
}
```

注意：`start()` 内部已处理重复调用（`workspacesCancellable` 非 nil 时 Combine 会替换订阅）。

- [ ] **Step 6: 构建确认**

```bash
swift build --target Ghostty 2>&1 | grep -E "error:|Build complete"
```

- [ ] **Step 7: 运行全部测试**

```bash
swift test 2>&1 | tail -20
```

期望：所有测试 PASS

- [ ] **Step 8: Commit**

```bash
git add macos/Sources/Features/Workspace/WorkspaceSidebar.swift \
        macos/Sources/Features/Workspace/PolterttyRootView.swift
git commit -m "feat(metadata): wire WorkspaceMetadataStore into sidebar and root view"
```

---

## Task 8: UI/UX 测试与设计稿对比

**设计稿：** `.superpowers/brainstorm/42210-1775360708/sidebar-metadata-design.png`

- [ ] **Step 1: 构建 Release 并启动应用**

```bash
swift build -c release --target Ghostty 2>&1 | grep -E "error:|Build complete"
open .build/release/Ghostty.app  # 或通过 Xcode 运行
```

- [ ] **Step 2: 截图当前侧边栏展开状态**

```bash
screencapture -i /tmp/sidebar-expanded-actual.png
```

对照设计稿确认：
- [ ] 端口徽标：蓝色系，monospaced 字体，格式 `:3000`
- [ ] PR 徽标：Open=绿色背景 `#N Open`，Draft=灰色 `#N Draft`
- [ ] Agent 徽标：黄色脉冲点 + `Working`；灰色点 + `Idle`
- [ ] 无数据时徽标行完全不显示（item 行高不变）
- [ ] 最多 3 个端口徽标，超出显示 `+N`

- [ ] **Step 3: 截图折叠状态**

```bash
screencapture -i /tmp/sidebar-collapsed-actual.png
```

对照设计稿确认：
- [ ] 图标下方三点行高度 8px，间距 4px
- [ ] 左=蓝色（有端口时），中=黄色脉冲（working）/灰（idle），右=绿（open）/灰（draft）
- [ ] 无数据的点透明（占位不显示）
- [ ] 已有红色未读角标在右上角不受影响

- [ ] **Step 4: 记录测试结果**

将两张截图保存到：

```bash
mkdir -p docs/tests/2026-04-05
cp /tmp/sidebar-expanded-actual.png docs/tests/2026-04-05/sidebar-expanded.png
cp /tmp/sidebar-collapsed-actual.png docs/tests/2026-04-05/sidebar-collapsed.png
```

- [ ] **Step 5: 最终 Commit**

```bash
git add docs/tests/2026-04-05/
git commit -m "test(metadata): add UI/UX screenshots for sidebar metadata"
```

---

## 自查

**Spec 覆盖：**
- ✅ 端口扫描 5s 轮询（Task 2 + Task 4）
- ✅ PR 状态 60s TTL（Task 3 + Task 4）
- ✅ Agent 指示（Task 4，订阅 ExternalSessionDiscovery）
- ✅ 展开状态徽标行（Task 5）
- ✅ 折叠状态三点行（Task 6）
- ✅ 端口点击 → Browser Panel（Task 7）
- ✅ 无数据时不渲染（Task 5 的 if 条件）
- ✅ 最多 3 端口 + "+N"（Task 5）
- ✅ 无 PR 留空（Task 3 返回 nil，Task 5 通过 if 过滤）
- ✅ Workspace 删除时清理（Task 4 syncWorkspaces）
