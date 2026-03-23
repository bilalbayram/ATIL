import AppKit
import SwiftUI

struct DefaultAppsSettingsView: View {
    @State private var viewModel = DefaultAppsViewModel()

    var body: some View {
        @Bindable var vm = viewModel

        NavigationStack {
            Form {
                Section {
                    Text("Choose which app opens each type of link or file. Changes apply immediately and macOS may ask for confirmation.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Default Apps") {
                    ForEach(vm.rows) { row in
                        DefaultAppsSettingsRow(row: row) { option in
                            Task { await viewModel.select(option, for: row.category) }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Default Apps")
        }
        .frame(minWidth: 680, minHeight: 520)
        .task {
            await viewModel.loadIfNeeded()
        }
        .alert("Error", isPresented: Binding(
            get: { vm.lastError != nil },
            set: { if !$0 { vm.lastError = nil } }
        )) {
            Button("OK") { vm.lastError = nil }
        } message: {
            Text(vm.lastError ?? "")
        }
    }
}

private struct DefaultAppsSettingsRow: View {
    let row: DefaultAppRowState
    let onSelect: (DefaultAppOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.category.title)
                        .font(.headline)
                    Text(row.category.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                currentAppView
                    .frame(minWidth: 180, alignment: .leading)

                controlView
                    .frame(width: 180, alignment: .trailing)
            }

            if let errorMessage = row.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    private var currentAppView: some View {
        HStack(spacing: 8) {
            if let iconPath = row.currentIconPath {
                Image(nsImage: appIcon(for: iconPath))
                    .resizable()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: row.currentSelection == .multiple ? "square.stack.3d.down.right" : "app")
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
            }

            Text(row.currentDisplayName)
                .foregroundStyle(row.isUnavailable ? .secondary : .primary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var controlView: some View {
        if row.isLoading || row.isApplying {
            ProgressView()
                .controlSize(.small)
        } else if row.isUnavailable {
            Text("Unavailable")
                .foregroundStyle(.secondary)
        } else {
            Menu {
                ForEach(row.candidates) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        HStack {
                            Image(nsImage: appIcon(for: option.appURL.path))
                                .resizable()
                                .frame(width: 16, height: 16)
                            Text(option.displayName)
                            Spacer()
                            if row.selectedAppID == option.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text("Choose App")
                    .frame(maxWidth: .infinity)
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func appIcon(for path: String) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}
