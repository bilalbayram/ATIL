import SwiftUI

struct FooterStatsView: View {
    @Environment(ProcessListViewModel.self) private var viewModel

    var body: some View {
        HStack {
            let processCount = viewModel.monitor.snapshot.count
            let redundantCount = viewModel.monitor.snapshot.filter { $0.category == .redundant }.count

            Label("\(processCount) processes", systemImage: "cpu")
                .font(.caption)
                .foregroundStyle(.secondary)

            if redundantCount > 0 {
                Text("\(redundantCount) redundant")
                    .font(.caption)
                    .foregroundStyle(.orange)

                Text("(\(formatBytes(viewModel.totalRedundantMemory)) reclaimable)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.sessionKillCount > 0 {
                Text("Session: \(viewModel.sessionKillCount) killed \u{00B7} \(formatBytes(viewModel.sessionMemoryFreed)) freed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
