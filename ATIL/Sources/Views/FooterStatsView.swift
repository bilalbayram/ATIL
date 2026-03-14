import SwiftUI

struct FooterStatsView: View {
    @Environment(ProcessListViewModel.self) private var viewModel

    var body: some View {
        HStack {
            let processCount = viewModel.monitor.snapshot.count
            let redundantCount = viewModel.monitor.snapshot.filter { $0.category == .redundant }.count
            let quarantinedCount = viewModel.monitor.snapshot.filter { $0.category == .quarantined || $0.processState == .suspended }.count

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

            if quarantinedCount > 0 {
                Text("\(quarantinedCount) quarantined")
                    .font(.caption)
                    .foregroundStyle(.purple)
            }

            Spacer()

            // Lifetime stats from SQLite
            if viewModel.lifetimeKills > 0 {
                Text("Lifetime: \(formatBytes(UInt64(viewModel.lifetimeMemoryFreed))) reclaimed \u{00B7} \(viewModel.lifetimeKills) killed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
