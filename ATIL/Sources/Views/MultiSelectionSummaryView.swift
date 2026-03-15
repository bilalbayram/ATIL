import SwiftUI

/// Detail pane shown when multiple processes are selected.
struct MultiSelectionSummaryView: View {
    @Environment(ProcessListViewModel.self) private var viewModel

    private var processes: [ATILProcess] {
        viewModel.selectedProcesses
    }

    private var totalMemory: UInt64 {
        processes.reduce(0) { $0 + $1.residentMemory }
    }

    private var categoryCounts: [(ProcessCategory, Int)] {
        let grouped = Dictionary(grouping: processes, by: \.category)
        return ProcessCategory.allCases.compactMap { cat in
            guard let count = grouped[cat]?.count, count > 0 else { return nil }
            return (cat, count)
        }
    }

    private var commonBundleName: String? {
        let names = Set(processes.compactMap(\.bundleIdentifier))
        return names.count == 1 ? names.first : nil
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("\(processes.count) Processes Selected")
                .font(.title2.bold())

            if let bundleName = commonBundleName {
                Text(bundleName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Stats grid
            HStack(spacing: 32) {
                StatBox(label: "Total Memory", value: formatBytes(totalMemory))

                if !categoryCounts.isEmpty {
                    StatBox(
                        label: "Categories",
                        value: categoryCounts.map { "\($0.1) \($0.0.displayName.lowercased())" }.joined(separator: ", ")
                    )
                }
            }
            .padding()
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Actions
            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.killAllSelected() }
                } label: {
                    Label("Kill All", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                Button {
                    viewModel.suspendAllSelected()
                } label: {
                    Label("Suspend All", systemImage: "pause.circle")
                }
                .buttonStyle(.bordered)

                Button {
                    viewModel.ignoreAllSelected()
                } label: {
                    Label("Ignore All", systemImage: "eye.slash")
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

private struct StatBox: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospaced())
        }
    }
}
