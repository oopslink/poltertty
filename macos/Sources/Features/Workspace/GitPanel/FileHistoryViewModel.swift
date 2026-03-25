// macos/Sources/Features/Workspace/GitPanel/FileHistoryViewModel.swift
import Foundation

@MainActor
class FileHistoryViewModel: ObservableObject {
    let filePath: String
    private let repo: GitRepository

    @Published var commits: [GitCommit] = []
    @Published var selectedCommit: GitCommit?
    @Published var selectedDiff: GitFileDiff?
    @Published var isLoading = false
    @Published var error: String?

    init(path: String, repo: GitRepository) {
        self.filePath = path
        self.repo = repo
    }

    func load() async {
        isLoading = true
        do {
            commits = try await repo.fileLog(path: filePath)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func selectCommit(_ commit: GitCommit) async {
        selectedCommit = commit
        do {
            selectedDiff = try await repo.fileDiff(oid: commit.id, path: filePath)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func restoreToSelected() async throws {
        guard let commit = selectedCommit else { return }
        try await repo.restoreToCommit(path: filePath, oid: commit.id)
    }
}
