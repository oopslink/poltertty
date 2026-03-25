// macos/Sources/Features/Workspace/BottomStatusBarView.swift

import SwiftUI
import AppKit

// MARK: - Per-pane Git Status

/// 轻量级 per-pane git 状态 VM：跟踪当前 pane 的 pwd，不依赖 workspace rootDir。
/// 用于在状态栏展示当前目录所在 git 分支和变更数量。
@MainActor
private class PaneGitStatusViewModel: ObservableObject {
    @Published var branch: String?
    @Published var isGitRepo = false
    @Published var changedCount = 0

    private var repo: GitRepository?
    nonisolated(unsafe) private var headSource: DispatchSourceFileSystemObject?
    nonisolated(unsafe) private var indexSource: DispatchSourceFileSystemObject?
    nonisolated(unsafe) private var pendingTask: Task<Void, Never>?
    private let queue = DispatchQueue(label: "poltertty.pane-git-status")
    private var currentGitDir: String?

    func updatePwd(_ pwd: String) async {
        guard !pwd.isEmpty else { resetState(); return }
        do {
            let newRepo = try GitRepository(path: pwd)
            repo = newRepo
            isGitRepo = true
            await fetchStatus()
            if let gitDir = await newRepo.gitDir, gitDir != currentGitDir {
                currentGitDir = gitDir
                setupWatching(gitDir: gitDir)
            }
        } catch {
            resetState()
        }
    }

    private func fetchStatus() async {
        guard let repo else { return }
        do {
            async let branchTask = repo.currentBranch()
            async let statusTask = repo.status()
            let (b, changes) = try await (branchTask, statusTask)
            branch = b
            changedCount = changes.count
        } catch {}
    }

    private func resetState() {
        isGitRepo = false
        repo = nil
        branch = nil
        changedCount = 0
        stopWatching()
    }

    private func setupWatching(gitDir: String) {
        stopWatching()
        startSource(path: "\(gitDir)HEAD", store: &headSource)
        startSource(path: "\(gitDir)index", store: &indexSource)
    }

    private func startSource(path: String, store: inout DispatchSourceFileSystemObject?) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.pendingTask?.cancel()
            self?.pendingTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                await self?.fetchStatus()
            }
        }
        source.setCancelHandler { close(fd) }
        store = source
        source.resume()
    }

    private func stopWatching() {
        headSource?.cancel(); headSource = nil
        indexSource?.cancel(); indexSource = nil
        pendingTask?.cancel()
    }

    deinit {
        headSource?.cancel()
        indexSource?.cancel()
    }
}

// MARK: - View

struct BottomStatusBarView: View {
    @StateObject private var paneGitVM = PaneGitStatusViewModel()
    @EnvironmentObject var tabBarVM: TabBarViewModel
    @EnvironmentObject private var paneSelectorVM: PaneSelectorViewModel
    @State private var showAnnotationPopover: Bool = false
    let pwd: String
    let isFocused: Bool
    let surfaceId: UUID

    private var hasTmuxAttached: Bool {
        tabBarVM.tmuxStates[surfaceId] != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 6) {
                // 左：当前目录路径
                Label(abbreviatedPwd, systemImage: "folder")
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundColor(.secondary)
                Spacer()
                // 右：tmux 按钮 | agent 按钮 | 注释按钮 | git 状态
                if !hasTmuxAttached {
                    Button(action: {
                        NotificationCenter.default.post(
                            name: .showTmuxSessionPicker,
                            object: nil,
                            userInfo: ["attachInCurrentPane": true]
                        )
                    }) {
                        Image("TmuxIcon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                    .help("Attach tmux session")
                }
                AgentButtonView(surfaceId: surfaceId)
                Button(action: { showAnnotationPopover = true }) {
                    Image(systemName: "tag")
                        .font(.system(size: 11))
                        .foregroundStyle(
                            paneSelectorVM.annotations[surfaceId] != nil ? Color.accentColor : Color.secondary
                        )
                }
                .buttonStyle(.plain)
                .help("设置 pane 注释")
                .popover(isPresented: $showAnnotationPopover) {
                    AnnotationPopoverView(surfaceId: surfaceId)
                        .environmentObject(paneSelectorVM)
                }
                if paneGitVM.isGitRepo {
                    Text("|")
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundColor(.secondary)
                        Text(paneGitVM.branch ?? "detached")
                            .foregroundColor(.primary)
                        if paneGitVM.changedCount > 0 {
                            Text("~\(paneGitVM.changedCount)")
                                .foregroundColor(.yellow)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        }
        .font(.system(size: 11))
        .opacity(isFocused ? 1.0 : 0.45)
        .task(id: pwd) {
            await paneGitVM.updatePwd(pwd)
        }
    }

    private var abbreviatedPwd: String {
        pwd.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
