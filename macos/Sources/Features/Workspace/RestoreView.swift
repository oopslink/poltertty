// macos/Sources/Features/Workspace/RestoreView.swift
import SwiftUI

private struct SnapshotImageItem: Identifiable {
    let id = UUID()
    let image: NSImage
}

struct RestoreView: View {
    let workspaces: [WorkspaceModel]
    let onRestore: ([UUID]) -> Void
    let onCreateNew: () -> Void

    @State private var selected: Set<UUID> = []
    @State private var enlargedSnapshotItem: SnapshotImageItem? = nil
    /// 异步预加载的截图缓存，Key 为 Workspace ID，避免在渲染路径中做磁盘 I/O
    @State private var screenshots: [UUID: NSImage] = [:]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Text("Restore Workspaces")
                    .font(.system(size: 20, weight: .bold))
            }

            Spacer().frame(height: 24)

            // Workspace list
            VStack(spacing: 0) {
                ForEach(workspaces) { workspace in
                    Button(action: { toggleSelection(workspace.id) }) {
                        HStack(spacing: 12) {
                            thumbnailView(for: workspace)

                            Image(systemName: selected.contains(workspace.id) ? "checkmark.square.fill" : "square")
                                .font(.system(size: 16))
                                .foregroundColor(selected.contains(workspace.id) ? .accentColor : .secondary)

                            Text(workspace.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)

                            Spacer()

                            Text(relativeTime(workspace.lastActiveAt))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            selected.contains(workspace.id)
                                ? Color.accentColor.opacity(0.06)
                                : Color.clear
                        )
                    }
                    .buttonStyle(.plain)

                    if workspace.id != workspaces.last?.id {
                        Divider().padding(.horizontal, 16)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(10)
            .frame(width: 480)

            Spacer().frame(height: 24)

            // Main restore button
            Button(action: {
                onRestore(Array(selected))
            }) {
                Text("Restore selected (\(selected.count))")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(selected.isEmpty ? Color.gray : Color.accentColor)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(selected.isEmpty)

            Spacer().frame(height: 12)

            // Quick actions
            HStack(spacing: 16) {
                Button("Restore latest only") {
                    if let first = workspaces.first {
                        onRestore([first.id])
                    }
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .buttonStyle(.plain)

                Text("|").foregroundColor(.secondary.opacity(0.3))

                Button("Restore all") {
                    onRestore(workspaces.map { $0.id })
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
            }

            Spacer().frame(height: 20)

            // New workspace option
            Button(action: onCreateNew) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                    Text("New Workspace")
                        .font(.system(size: 12))
                }
                .foregroundColor(selected.isEmpty ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { preselectRecent() }
        .task { await loadScreenshots() }
        .sheet(item: $enlargedSnapshotItem) { item in
            EnlargedSnapshotView(item: item)
        }
    }

    // MARK: - 子视图

    /// 缩略图 View（从预加载缓存读取，不做磁盘 I/O）
    @ViewBuilder
    private func thumbnailView(for workspace: WorkspaceModel) -> some View {
        if let img = screenshots[workspace.id] {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 80, height: 50)
                .clipped()
                .cornerRadius(4)
                // onTapGesture 优先于外层 Button，点击缩略图只放大，不切换选中
                .onTapGesture { enlargedSnapshotItem = SnapshotImageItem(image: img) }
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: .tertiaryLabelColor).opacity(0.15))
                .frame(width: 80, height: 50)
        }
    }

    // MARK: - 数据加载

    /// 异步预加载所有 workspace 的最新快照截图，结果写入 screenshots 缓存
    @MainActor
    private func loadScreenshots() async {
        let rootURL = URL(fileURLWithPath: PolterttyConfig.shared.workspaceDir)
        await withTaskGroup(of: (UUID, NSImage?).self) { group in
            for workspace in workspaces {
                group.addTask {
                    let store = SnapshotStore(workspaceId: workspace.id, storageRootURL: rootURL)
                    guard let latest = store.loadLatest() else { return (workspace.id, nil) }
                    return (workspace.id, store.screenshot(for: latest.id))
                }
            }
            for await (id, image) in group {
                if let image {
                    screenshots[id] = image
                }
            }
        }
    }

    // MARK: - 辅助

    private func toggleSelection(_ id: UUID) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    private func preselectRecent() {
        let recent = workspaces.prefix(2)
        selected = Set(recent.map { $0.id })
    }

    private static let timeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private func relativeTime(_ date: Date) -> String {
        Self.timeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - 放大预览 View

private struct EnlargedSnapshotView: View {
    let item: SnapshotImageItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: item.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 900, maxHeight: 600)
            Button("关闭") { dismiss() }
        }
        .padding(24)
    }
}
