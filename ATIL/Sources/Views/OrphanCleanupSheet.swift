import SwiftUI

struct OrphanCleanupSheet: View {
    @Environment(StartupItemsViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedOrphanIDs: Set<String> = []
    @State private var hasInitializedSelection = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if viewModel.orphanedItems.isEmpty {
                emptyState
            } else {
                orphanList
            }

            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 400)
        .onChange(of: viewModel.orphanedItems) {
            if !hasInitializedSelection {
                selectedOrphanIDs = Set(viewModel.orphanedItems.map(\.id))
                hasInitializedSelection = true
            }
        }
        .onAppear {
            if !hasInitializedSelection {
                selectedOrphanIDs = Set(viewModel.orphanedItems.map(\.id))
                hasInitializedSelection = true
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("Orphan Cleanup")
                .font(.headline)

            Text("Startup items whose parent application has been uninstalled. These can be safely removed.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Orphans Found", systemImage: "checkmark.circle")
        } description: {
            Text("All startup items have a valid parent application.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var orphanList: some View {
        List {
            ForEach(viewModel.orphanedItems) { orphan in
                OrphanRow(
                    orphan: orphan,
                    isSelected: selectedOrphanIDs.contains(orphan.id),
                    onToggle: {
                        if selectedOrphanIDs.contains(orphan.id) {
                            selectedOrphanIDs.remove(orphan.id)
                        } else {
                            selectedOrphanIDs.insert(orphan.id)
                        }
                    }
                )
            }
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        HStack {
            if !viewModel.orphanedItems.isEmpty {
                Text("\(selectedOrphanIDs.count) of \(viewModel.orphanedItems.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            if !viewModel.orphanedItems.isEmpty {
                Button("Delete Selected", role: .destructive) {
                    Task {
                        await viewModel.deleteOrphanedItems(selected: selectedOrphanIDs)
                        dismiss()
                    }
                }
                .disabled(selectedOrphanIDs.isEmpty || viewModel.isPerformingUserAction)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }
}

private struct OrphanRow: View {
    let orphan: OrphanedStartupItem
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(
                get: { isSelected },
                set: { _ in onToggle() }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 4) {
                Text(orphan.item.displayLabel)
                    .font(.body.weight(.medium))

                Text(orphan.item.app.displayName)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let executablePath = orphan.item.executablePath, orphan.executableMissing {
                    Label("Missing executable: \(executablePath)", systemImage: "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let plistPath = orphan.item.plistPath {
                    Label(plistPath, systemImage: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
