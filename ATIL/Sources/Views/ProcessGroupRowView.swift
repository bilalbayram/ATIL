import SwiftUI

/// A row representing a group of related processes (e.g., all Chrome helpers).
/// Can be expanded to show individual processes.
struct ProcessGroupRowView: View {
    let group: ProcessGroup
    @State private var isExpanded = false

    var body: some View {
        if group.isGrouped {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(group.processes) { process in
                    ProcessRowView(process: process)
                        .tag(process.identity)
                        .padding(.leading, 8)
                }
            } label: {
                groupLabel
            }
        } else if let process = group.processes.first {
            ProcessRowView(process: process)
                .tag(process.identity)
        }
    }

    private var groupLabel: some View {
        HStack(spacing: 10) {
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
        }
        .padding(.vertical, 2)
    }
}
