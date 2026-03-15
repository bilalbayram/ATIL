import SwiftUI

struct HistoryListView: View {
    @Environment(ProcessListViewModel.self) private var viewModel
    @State private var records: [KillHistoryRecord] = []
    @State private var selectedRecordID: Int64?

    private var selectedRecord: KillHistoryRecord? {
        guard let selectedRecordID else { return nil }
        return records.first(where: { $0.id == selectedRecordID })
    }

    var body: some View {
        List(selection: $selectedRecordID) {
            ForEach(records) { record in
                HistoryRowView(record: record)
                    .tag(record.id)
            }
        }
        .overlay {
            if records.isEmpty {
                ContentUnavailableView(
                    "No History Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Kill and suspend actions will appear here.")
                )
            }
        }
        .onAppear(perform: load)
        .onKeyPress("l") {
            guard let selectedRecord, viewModel.canRelaunch(selectedRecord) else {
                return .ignored
            }
            viewModel.relaunch(selectedRecord)
            return .handled
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    load()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                if let selectedRecord, viewModel.canRelaunch(selectedRecord) {
                    Button {
                        viewModel.relaunch(selectedRecord)
                    } label: {
                        Label("Relaunch", systemImage: "arrow.counterclockwise")
                    }
                    .keyboardShortcut("l")
                }
            }
        }
        .navigationTitle("Kill History")
    }

    private func load() {
        records = viewModel.recentHistory()
    }
}

private struct HistoryRowView: View {
    let record: KillHistoryRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.processName)
                    .font(.body.weight(.medium))

                HStack(spacing: 8) {
                    Text(record.action.capitalized)
                    Text(record.result.capitalized)
                    if record.memoryFreed > 0 {
                        Text(formatBytes(UInt64(record.memoryFreed)))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let path = record.executablePath {
                    Text(path)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(record.timestamp, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch record.action {
        case "kill":
            return "xmark.circle"
        case "suspend":
            return "pause.circle"
        default:
            return "clock"
        }
    }

    private var iconColor: Color {
        switch record.result {
        case "success":
            return record.action == "kill" ? .red : .orange
        default:
            return .secondary
        }
    }
}
