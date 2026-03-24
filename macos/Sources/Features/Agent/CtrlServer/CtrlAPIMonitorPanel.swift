// macos/Sources/Features/Agent/CtrlServer/CtrlAPIMonitorPanel.swift
import SwiftUI

struct CtrlAPIMonitorPanel: View {
    @StateObject private var viewModel = CtrlAPIMonitorViewModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if viewModel.filteredRecords.isEmpty {
                emptyState
            } else {
                VSplitView {
                    recordList
                        .frame(minHeight: 60)
                    if viewModel.selectedRecord != nil {
                        detailView
                            .frame(minHeight: 60, idealHeight: 150)
                    }
                }
            }
        }
        .frame(minHeight: 100)
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

    // MARK: - Detail View

    private var detailView: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Request")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                Divider()
                ScrollView([.horizontal, .vertical]) {
                    Text(prettyJSON(viewModel.selectedRecord?.requestBody))
                        .font(.system(size: 11, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text("Response")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                Divider()
                ScrollView([.horizontal, .vertical]) {
                    Text(prettyJSON(viewModel.selectedRecord?.responseBody))
                        .font(.system(size: 11, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.4))
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

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: record.timestamp)
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
