import SwiftUI

/// Group header row — tagged with a synthetic identity so it gets native
/// List selection highlighting identical to process rows.
struct ProcessGroupHeaderView: View {
    let group: ProcessGroup
    @Environment(ProcessListViewModel.self) private var viewModel

    private var isExpanded: Bool {
        viewModel.expandedGroupIDs.contains(group.id)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Group indicator SF Symbol
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

            // Name + count
            VStack(alignment: .leading, spacing: 2) {
                Text(group.displayName)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)

                Text("\(group.processCount) processes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Memory — same column as ProcessRowView
            Text(formatBytes(group.totalMemory))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)

            // Expand/collapse button in PID column position
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .tag(group.groupIdentity)
    }
}
