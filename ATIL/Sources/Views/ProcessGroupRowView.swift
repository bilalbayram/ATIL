import SwiftUI

/// Group header row — selectable (selects all children), with a trailing
/// expand/collapse button.  Layout matches ProcessRowView columns so
/// grouped and ungrouped rows are aligned.
struct ProcessGroupHeaderView: View {
    let group: ProcessGroup
    @Environment(ProcessListViewModel.self) private var viewModel

    private var isExpanded: Bool {
        viewModel.expandedGroupIDs.contains(group.id)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Icon — same position as ProcessRowView icon
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

            // Name + count — same position as ProcessRowView name
            VStack(alignment: .leading, spacing: 2) {
                Text(group.displayName)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)

                Text("\(group.processCount) processes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Memory — same position as ProcessRowView memory column
            Text(formatBytes(group.totalMemory))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)

            // Expand/collapse button in place of PID column
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
        .contentShape(Rectangle())
        .onTapGesture {
            // Select all child processes in this group
            viewModel.selectGroup(group)
        }
    }
}
