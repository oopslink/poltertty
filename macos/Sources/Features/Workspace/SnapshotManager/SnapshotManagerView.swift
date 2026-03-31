// macos/Sources/Features/Workspace/SnapshotManager/SnapshotManagerView.swift
import SwiftUI

/// 快照缩略图的可点击放大项
private struct SnapshotImageItem: Identifiable {
    let id = UUID()
    let image: NSImage
}

/// 全局快照管理面板：展示所有非临时 Workspace 的历史快照，支持缩略图预览、从快照创建新 Workspace、删除快照
struct SnapshotManagerView: View {
    @StateObject private var vm = SnapshotManagerViewModel()
    @Environment(\.dismiss) private var dismiss

    /// Key: entryId，异步预加载的截图缓存
    @State private var screenshots: [UUID: NSImage] = [:]
    @State private var enlargedItem: SnapshotImageItem? = nil

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("快照管理")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // 内容区
            if vm.groups.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(vm.groups) { group in
                            groupSection(group)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 660, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await vm.load() }
        .task(id: vm.groups.map { $0.id }) {
            await loadScreenshots()
        }
        .sheet(item: $enlargedItem) { item in
            EnlargedSnapshotView(item: item)
        }
        .sheet(item: $vm.selectedEntry) { selected in
            WorkspaceCreateForm(
                onSubmit: { name, rootDir, colorHex, description in
                    WorkspaceManager.shared.create(
                        name: name,
                        rootDir: rootDir,
                        colorHex: colorHex,
                        description: description
                    )
                    vm.dismissCreate()
                },
                onCancel: {
                    vm.dismissCreate()
                },
                preselectedSourceWorkspaceId: selected.workspace.id
            )
        }
    }

    // MARK: - 空状态

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.5))
            Text("暂无快照记录")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Text("Workspace 活动时会自动保存快照")
                .font(.system(size: 12))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Workspace 分组

    @ViewBuilder
    private func groupSection(_ group: WorkspaceSnapshotGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 分组标题
            HStack(spacing: 6) {
                Circle()
                    .fill(group.workspace.color)
                    .frame(width: 8, height: 8)
                Text(group.workspace.name)
                    .font(.system(size: 13, weight: .semibold))
                Text("(\(group.entries.count) 条快照)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // 快照条目列表
            VStack(spacing: 0) {
                ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                    entryRow(entry: entry, workspace: group.workspace)

                    if index < group.entries.count - 1 {
                        Divider().padding(.horizontal, 8)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - 快照条目行

    @ViewBuilder
    private func entryRow(entry: SnapshotEntry, workspace: WorkspaceModel) -> some View {
        HStack(spacing: 12) {
            // 缩略图
            thumbnailView(entryId: entry.id)

            // 元信息
            VStack(alignment: .leading, spacing: 3) {
                Text(relativeTime(entry.savedAt))
                    .font(.system(size: 13, weight: .medium))
                if let tabs = entry.tabs, !tabs.isEmpty {
                    Text("\(tabs.count) 个标签页")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text("无标签信息")
                        .font(.system(size: 11))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                }
            }

            Spacer()

            // 操作按钮
            HStack(spacing: 8) {
                Button("从此创建") {
                    vm.requestCreate(from: entry, workspace: workspace)
                }
                .font(.system(size: 12))
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(role: .destructive) {
                    vm.delete(entryId: entry.id, workspaceId: workspace.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("删除此快照")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - 缩略图

    @ViewBuilder
    private func thumbnailView(entryId: UUID) -> some View {
        if let img = screenshots[entryId] {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 60)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .onTapGesture {
                    enlargedItem = SnapshotImageItem(image: img)
                }
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: .tertiaryLabelColor).opacity(0.15))
                .frame(width: 96, height: 60)
        }
    }

    // MARK: - 异步加载截图

    @MainActor
    private func loadScreenshots() async {
        let rootURL = URL(fileURLWithPath: PolterttyConfig.shared.workspaceDir)
        await withTaskGroup(of: (UUID, NSImage?).self) { group in
            for snapshotGroup in vm.groups {
                let workspaceId = snapshotGroup.workspace.id
                for entry in snapshotGroup.entries {
                    let entryId = entry.id
                    group.addTask {
                        let img = vm.screenshot(for: entryId, workspaceId: workspaceId, storageRootURL: rootURL)
                        return (entryId, img)
                    }
                }
            }
            for await (entryId, img) in group {
                if let img {
                    screenshots[entryId] = img
                }
            }
        }
    }

    // MARK: - 辅助

    private static let timeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    private func relativeTime(_ date: Date) -> String {
        Self.timeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - 放大预览

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
