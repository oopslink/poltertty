// macos/Sources/Features/Agent/CtrlServer/CtrlAPIMonitorPanel.swift
import SwiftUI
import AppKit

struct CtrlAPIMonitorPanel: View {
    @StateObject private var viewModel = CtrlAPIMonitorViewModel()
    @State private var panelHeight: CGFloat = 220
    @GestureState private var dragOffset: CGFloat = 0

    private var effectiveHeight: CGFloat {
        max(120, min(600, panelHeight - dragOffset))
    }

    var body: some View {
        VStack(spacing: 0) {
            dragHandle
            toolbar
            Divider()
            content
        }
        .frame(height: effectiveHeight)
        .onChange(of: viewModel.selectedWorkspaceId) { _ in resetSelectionIfNeeded() }
        .onChange(of: viewModel.selectedSurfaceId) { _ in resetSelectionIfNeeded() }
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        HStack {
            Spacer()
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.primary.opacity(0.18))
                .frame(width: 28, height: 2)
            Spacer()
        }
        .frame(height: 4)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.01))
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation.height
                }
                .onEnded { value in
                    panelHeight = max(120, min(600, panelHeight - value.translation.height))
                }
        )
        .onHover { hovering in
            if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "network")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Ctrl API")
                    .font(.system(size: 11, weight: .semibold))
            }
            Spacer()
            if !viewModel.availableWorkspaceIds.isEmpty {
                Picker("WS", selection: $viewModel.selectedWorkspaceId) {
                    Text("All WS").tag(Optional<UUID>.none)
                    ForEach(viewModel.availableWorkspaceIds, id: \.self) { id in
                        Text(id.uuidString.prefix(8) + "…").tag(Optional(id))
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.mini)
                .frame(maxWidth: 90)
            }
            if !viewModel.availableSurfaceIds.isEmpty {
                Picker("SF", selection: $viewModel.selectedSurfaceId) {
                    Text("All SF").tag(Optional<UUID>.none)
                    ForEach(viewModel.availableSurfaceIds, id: \.self) { id in
                        Text(id.uuidString.prefix(8) + "…").tag(Optional(id))
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.mini)
                .frame(maxWidth: 90)
            }
            Button("Clear") { viewModel.clearRecords() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.filteredRecords.isEmpty {
            emptyState
        } else {
            HSplitView {
                recordList
                    .frame(minWidth: 200)
                if viewModel.selectedRecord != nil {
                    detailPane
                        .frame(minWidth: 240)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 4) {
            Spacer()
            Image(systemName: "network.slash")
                .font(.system(size: 20, weight: .thin))
                .foregroundStyle(.quaternary)
            Text("No API calls recorded")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Record List

    private var recordList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.filteredRecords) { record in
                    CtrlAPIRecordRow(
                        record: record,
                        isSelected: viewModel.selectedRecord?.id == record.id
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if viewModel.selectedRecord?.id == record.id {
                            viewModel.selectedRecord = nil
                        } else {
                            viewModel.selectedRecord = record
                        }
                    }
                    Divider().padding(.leading, 8)
                }
            }
        }
    }

    // MARK: - Detail Pane

    private var detailPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Detail")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    viewModel.selectedRecord = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            Divider()

            if let record = viewModel.selectedRecord {
                if let error = record.error {
                    VSplitView {
                        detailSection(title: "Request", body: record.requestBody, isError: false)
                            .frame(minHeight: 40)
                        detailSection(title: "Response", body: record.responseBody, isError: false)
                            .frame(minHeight: 40)
                        detailSection(title: "Error", body: error, isError: true)
                            .frame(minHeight: 40, idealHeight: 80)
                    }
                } else {
                    VSplitView {
                        detailSection(title: "Request", body: record.requestBody, isError: false)
                            .frame(minHeight: 40)
                        detailSection(title: "Response", body: record.responseBody, isError: false)
                            .frame(minHeight: 40)
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.4))
    }

    private func detailSection(title: String, body: String?, isError: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isError ? Color.red : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            Divider()
            JSONHighlightView(content: prettyJSON(body), isError: isError)
        }
    }

    // MARK: - Helpers

    private func resetSelectionIfNeeded() {
        guard let selected = viewModel.selectedRecord else { return }
        if !viewModel.filteredRecords.contains(where: { $0.id == selected.id }) {
            viewModel.selectedRecord = nil
        }
    }

    private func prettyJSON(_ str: String?) -> String {
        guard let str,
              let data = str.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
              let result = String(data: pretty, encoding: .utf8) else {
            return str ?? "(empty)"
        }
        return result
    }
}

// MARK: - RecordRow

struct CtrlAPIRecordRow: View {
    let record: CtrlAPIRecord
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(timeString)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Text(record.method)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(methodColor)
                .frame(width: 40, alignment: .leading)
            Text(displayPath)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(durationString)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(durationColor)
                .frame(width: 46, alignment: .trailing)
            Text("\(record.statusCode)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(statusColor)
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var timeString: String {
        CtrlAPIRecordRow.timeFormatter.string(from: record.timestamp)
    }

    private var displayPath: String {
        if let tool = record.toolName { return "tools/call · \(tool)" }
        return record.path
    }

    private var durationString: String {
        let ms = record.durationMs
        if ms < 10 { return String(format: "%.1fms", ms) }
        return String(format: "%.0fms", ms)
    }

    private var methodColor: Color {
        switch record.method {
        case "POST":   return .blue
        case "GET":    return Color(nsColor: .systemGreen)
        case "DELETE": return .red
        default:       return .secondary
        }
    }

    private var statusColor: Color {
        if record.error != nil || record.statusCode >= 400 { return .red }
        return .primary
    }

    private var durationColor: Color {
        if record.durationMs < 10 { return Color(nsColor: .systemGreen) }
        if record.durationMs < 100 { return .primary }
        return .orange
    }
}
