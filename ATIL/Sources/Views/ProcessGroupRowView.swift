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
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
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
        .contextMenu {
            Button {
                Task { await viewModel.killAllInGroup(group) }
            } label: {
                Label("Kill All in Group", systemImage: "xmark.circle")
            }

            Button {
                viewModel.suspendAllInGroup(group)
            } label: {
                Label("Suspend All in Group", systemImage: "pause.circle")
            }

            Button {
                viewModel.ignoreAllInGroup(group)
            } label: {
                Label("Ignore All in Group", systemImage: "eye.slash")
            }

            Divider()

            Button {
                viewModel.selectGroup(group)
            } label: {
                Label("Select All in Group", systemImage: "checkmark.circle")
            }

            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    if isExpanded {
                        viewModel.expandedGroupIDs.remove(group.id)
                    } else {
                        viewModel.expandedGroupIDs.insert(group.id)
                    }
                }
            } label: {
                Label(isExpanded ? "Collapse" : "Expand", systemImage: isExpanded ? "chevron.up" : "chevron.down")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.displayName), \(group.processCount) processes")
        .accessibilityHint(isExpanded ? "Double-click to collapse" : "Double-click to expand")
    }
}
