import SwiftUI

/// Non-selectable group header row. Only the chevron toggles expansion.
/// Processes are rendered as siblings by CategorySectionView.
struct ProcessGroupHeaderView: View {
    let group: ProcessGroup
    @Environment(ProcessListViewModel.self) private var viewModel

    private var isExpanded: Bool {
        viewModel.expandedGroupIDs.contains(group.id)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Only the chevron is tappable for expand/collapse
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded {
                        viewModel.expandedGroupIDs.remove(group.id)
                    } else {
                        viewModel.expandedGroupIDs.insert(group.id)
                    }
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let icon = group.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "gearshape.2.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(group.displayName)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)

                Text("\(group.processCount) processes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(formatBytes(group.totalMemory))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)

            // Empty spacer matching PID column width in ProcessRowView
            Spacer()
                .frame(width: 70)
        }
        .padding(.vertical, 2)
    }
}
