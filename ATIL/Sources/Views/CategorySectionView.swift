import SwiftUI

struct CategorySectionView: View {
    let category: ProcessCategory
    let processes: [ATILProcess]

    @Environment(ProcessListViewModel.self) private var viewModel

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
            ForEach(processes) { process in
                ProcessRowView(process: process)
                    .tag(process.identity)
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
