import SwiftUI

private struct NumericRoll: ViewModifier {
    let value: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .contentTransition(.numericText())
            .animation(ATILAnimation.subtle(reduceMotion: reduceMotion), value: value)
    }
}

struct FooterStatsView: View {
    @Environment(ProcessListViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack {
            let processCount = viewModel.monitor.snapshot.count
            let redundantCount = viewModel.monitor.snapshot.filter { $0.category == .redundant }.count
            let quarantinedCount = viewModel.monitor.snapshot.filter { $0.category == .quarantined || $0.processState == .suspended }.count

            Label("\(processCount) processes", systemImage: "cpu")
                .font(.caption)
                .foregroundStyle(.secondary)
                .modifier(NumericRoll(value: processCount, reduceMotion: reduceMotion))

            if redundantCount > 0 {
                Text("\(redundantCount) redundant")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .modifier(NumericRoll(value: redundantCount, reduceMotion: reduceMotion))

                Text("(\(formatBytes(viewModel.totalRedundantMemory)) reclaimable)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if quarantinedCount > 0 {
                Text("\(quarantinedCount) quarantined")
                    .font(.caption)
                    .foregroundStyle(.purple)
                    .modifier(NumericRoll(value: quarantinedCount, reduceMotion: reduceMotion))
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
        .background(.bar)
        .accessibilityElement(children: .combine)
    }
}
