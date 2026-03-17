import SwiftUI

struct StartupItemDetail: View {
    @Environment(StartupItemsViewModel.self) private var viewModel

    var body: some View {
        Group {
            if let item = viewModel.selectedItem {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        StartupDetailHeadline(item: item)

                        StartupDetailFacts(rows: [
                            ("State", item.state.displayName),
                            ("Scope", item.scope.displayName),
                            ("Kind", item.kind.displayName),
                            ("Confidence", item.attributionConfidence.displayName),
                            ("Needs Helper", item.requiresHelper ? "Yes" : "No"),
                            ("Blocked", viewModel.isBlocked(item) ? "Yes" : "No"),
                        ])

                        if let label = item.label {
                            LabeledMonospaceValue(label: "Launchd Label", value: label)
                        }
                        if let plistPath = item.plistPath {
                            LabeledMonospaceValue(label: "Plist Path", value: plistPath)
                        }
                        if let executablePath = item.executablePath {
                            LabeledMonospaceValue(label: "Executable Path", value: executablePath)
                        }
                        if !item.programArguments.isEmpty {
                            LabeledMonospaceValue(label: "Arguments", value: item.programArguments.joined(separator: " "))
                        }

                        if let process = viewModel.selectedRunningProcess {
                            Divider()
                            SectionHeader("Running Process")
                            StartupDetailFacts(rows: [
                                ("PID", "\(process.pid)"),
                                ("Memory", formatBytes(process.residentMemory)),
                                ("CPU %", String(format: "%.1f", process.cpuPercent)),
                                ("Started", formatDateTime(process.startTime)),
                            ])
                        }

                        if item.state == .unknown {
                            Text("This item was attributed heuristically. ATIL avoids destructive control until it has a confident target.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Select a Startup Item",
                    systemImage: "sidebar.left",
                    description: Text("Pick an app and item to inspect or disable.")
                )
            }
        }
    }
}

struct StartupDetailHeadline: View {
    let item: StartupItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.displayLabel)
                .font(.headline)

            Text(item.kind.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct StartupDetailFacts: View {
    let rows: [(label: String, value: String)]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                InfoRow(label: row.label, value: row.value)
            }
        }
    }
}
