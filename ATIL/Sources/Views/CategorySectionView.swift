import SwiftUI

struct CategorySectionView: View {
    let category: ProcessCategory
    let processes: [ATILProcess]
    let groups: [ProcessGroup]?

    @Environment(ProcessListViewModel.self) private var viewModel

    init(category: ProcessCategory, processes: [ATILProcess], groups: [ProcessGroup]? = nil) {
        self.category = category
        self.processes = processes
        self.groups = groups
    }

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { viewModel.expandedCategories.contains(category) },
            set: { expanded in
                if expanded {
                    viewModel.expandedCategories.insert(category)
                } else {
                    viewModel.expandedCategories.remove(category)
                }
            }
        )
    }

    private var aggregateMemory: UInt64 {
        processes.reduce(0) { $0 + $1.residentMemory }
    }

    var body: some View {
        DisclosureGroup(isExpanded: isExpanded) {
            if let groups, viewModel.showGrouped {
                // Flatten groups: render group headers and their processes
                // at the same level so List selection works on all rows.
                ForEach(groups) { group in
                    if group.isGrouped {
                        // Group header (non-selectable toggle)
                        ProcessGroupHeaderView(group: group)

                        // Expanded processes — direct children of this DisclosureGroup
                        if viewModel.expandedGroupIDs.contains(group.id) {
                            ForEach(group.processes) { process in
                                ProcessRowView(process: process)
                                    .tag(process.identity)
                                    .padding(.leading, 20)
                            }
                        }
                    } else if let process = group.processes.first {
                        ProcessRowView(process: process)
                            .tag(process.identity)
                    }
                }
            } else {
                ForEach(processes) { process in
                    ProcessRowView(process: process)
                        .tag(process.identity)
                }
            }
        } label: {
            HStack {
                Image(systemName: category.systemImage)
                    .foregroundStyle(categoryColor)

                Text(category.displayName)
                    .font(.headline)

                Text("\(processes.count)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())

                Spacer()

                Text(formatBytes(aggregateMemory))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var categoryColor: Color {
        switch category {
        case .quarantined: .purple
        case .redundant: .red
        case .suspicious: .orange
        case .healthy: .green
        }
    }
}
