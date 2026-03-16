import SwiftUI

struct StartupItemsView: View {
    @Environment(StartupItemsViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var vm = viewModel

        NavigationSplitView {
            VStack(spacing: 0) {
                StartupFilterBar()
                List(selection: $vm.selectedGroupID) {
                    ForEach(viewModel.groups) { group in
                        StartupGroupRow(group: group)
                            .tag(group.id)
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 320)
        } detail: {
            Group {
                if let group = viewModel.selectedGroup {
                    VStack(alignment: .leading, spacing: 0) {
                        StartupGroupHeader(group: group)
                        Divider()
                        List(selection: $vm.selectedItemID) {
                            ForEach(group.items) { item in
                                StartupItemRow(item: item, isBlocked: viewModel.isBlocked(item))
                                    .tag(item.id)
                            }
                        }
                        .frame(minHeight: 220)
                        Divider()
                        StartupItemDetail()
                    }
                } else {
                    ContentUnavailableView(
                        "No Startup Items",
                        systemImage: "power.circle",
                        description: Text("ATIL has not discovered any startup or background items yet.")
                    )
                }
            }
            .animation(ATILAnimation.subtle(reduceMotion: reduceMotion), value: viewModel.selectedGroupID)
        }
        .navigationTitle("Startup Items")
        .task {
            await viewModel.refresh()
        }
        .alert("Startup Items Error", isPresented: Binding(
            get: { viewModel.lastError != nil },
            set: { if !$0 { viewModel.lastError = nil } }
        )) {
            Button("OK") { viewModel.lastError = nil }
        } message: {
            Text(viewModel.lastError ?? "")
        }
    }
}

private struct StartupFilterBar: View {
    @Environment(StartupItemsViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 10) {
            TextField("Search apps, labels, or paths", text: $vm.searchText)
                .textFieldStyle(.roundedBorder)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StartupFilter.allCases) { filter in
                        StartupFilterChip(
                            filter: filter,
                            isActive: viewModel.activeFilters.contains(filter)
                        ) {
                            viewModel.toggleFilter(filter)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }

            if !viewModel.activeFilters.isEmpty {
                Button("Clear Filters") {
                    viewModel.clearFilters()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
    }
}

private struct StartupFilterChip: View {
    let filter: StartupFilter
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: filter.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(filter.displayName)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isActive ? filter.color : .secondary)
            .background(
                Capsule()
                    .fill(isActive ? filter.color.opacity(0.14) : .clear)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isActive ? filter.color.opacity(0.3) : .secondary.opacity(isHovered ? 0.3 : 0.15),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainPressableButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct StartupGroupRow: View {
    let group: StartupAppGroup
    @Environment(StartupItemsViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: 10) {
            if let icon = viewModel.icon(for: group) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 26, height: 26)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(group.app.displayName)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("\(group.items.count) item\(group.items.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if group.runningItemCount > 0 {
                        StatusBadgeView(text: "\(group.runningItemCount) running", icon: "waveform.path.ecg", color: .mint)
                    }
                    if group.isBlocked {
                        StatusBadgeView(text: "blocked", icon: "shield.slash", color: .red)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct StartupGroupHeader: View {
    let group: StartupAppGroup
    @Environment(StartupItemsViewModel.self) private var viewModel

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let icon = viewModel.icon(for: group) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: "app.badge")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(group.app.displayName)
                    .font(.title3.bold())

                if let bundleIdentifier = group.app.bundleIdentifier {
                    Text(bundleIdentifier)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    if group.isBlocked {
                        StatusBadgeView(text: "blocked", icon: "shield.slash", color: .red)
                    }
                    if group.enabledItemCount > 0 {
                        StatusBadgeView(text: "\(group.enabledItemCount) enabled", icon: "power", color: .green)
                    }
                    if group.runningItemCount > 0 {
                        StatusBadgeView(text: "\(group.runningItemCount) running", icon: "waveform.path.ecg", color: .mint)
                    }
                }
            }

            Spacer()

            HStack(spacing: 10) {
                if group.isBlocked {
                    Button("Unblock App") {
                        viewModel.unblockSelectedApp()
                    }
                } else {
                    Button("Block App") {
                        viewModel.blockSelectedApp()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }

                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .padding(16)
    }
}

private struct StartupItemRow: View {
    let item: StartupItem
    let isBlocked: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.displayLabel)
                        .font(.system(.body, weight: .medium))
                        .lineLimit(1)

                    if item.isRunning {
                        StatusBadgeView(text: "running", icon: "waveform.path.ecg", color: .mint)
                    }
                    if isBlocked {
                        StatusBadgeView(text: "blocked", icon: "shield.slash", color: .red)
                    }
                }

                HStack(spacing: 8) {
                    Text(item.kind.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(item.scope.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(item.state.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct StartupItemDetail: View {
    @Environment(StartupItemsViewModel.self) private var viewModel

    var body: some View {
        Group {
            if let item = viewModel.selectedItem {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.displayLabel)
                                    .font(.headline)

                                Text(item.kind.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            HStack(spacing: 10) {
                                Button("Disable") {
                                    Task { await viewModel.disableSelectedItem() }
                                }
                                .disabled(!item.canDisable || item.state == .unknown)

                                Button("Kill Current Process") {
                                    Task { await viewModel.killSelectedProcess() }
                                }
                                .disabled(viewModel.selectedRunningProcess == nil)

                                Button("Reveal File") {
                                    viewModel.revealSelectedItem()
                                }
                                .disabled(item.plistPath == nil && item.executablePath == nil)
                            }
                        }

                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            alignment: .leading,
                            spacing: 12
                        ) {
                            StartupInfoRow(label: "State", value: item.state.displayName)
                            StartupInfoRow(label: "Scope", value: item.scope.displayName)
                            StartupInfoRow(label: "Kind", value: item.kind.displayName)
                            StartupInfoRow(label: "Confidence", value: item.attributionConfidence.displayName)
                            StartupInfoRow(label: "Needs Helper", value: item.requiresHelper ? "Yes" : "No")
                            StartupInfoRow(label: "Blocked", value: viewModel.isBlocked(item) ? "Yes" : "No")
                        }

                        if let label = item.label {
                            StartupMonospaceValue(label: "Launchd Label", value: label)
                        }
                        if let plistPath = item.plistPath {
                            StartupMonospaceValue(label: "Plist Path", value: plistPath)
                        }
                        if let executablePath = item.executablePath {
                            StartupMonospaceValue(label: "Executable Path", value: executablePath)
                        }
                        if !item.programArguments.isEmpty {
                            StartupMonospaceValue(label: "Arguments", value: item.programArguments.joined(separator: " "))
                        }

                        if let process = viewModel.selectedRunningProcess {
                            Divider()
                            StartupSectionHeader("Running Process")
                            LazyVGrid(
                                columns: [GridItem(.flexible()), GridItem(.flexible())],
                                alignment: .leading,
                                spacing: 12
                            ) {
                                StartupInfoRow(label: "PID", value: "\(process.pid)")
                                StartupInfoRow(label: "Memory", value: formatBytes(process.residentMemory))
                                StartupInfoRow(label: "CPU %", value: String(format: "%.1f", process.cpuPercent))
                                StartupInfoRow(label: "Started", value: formatDateTime(process.startTime))
                            }
                        }

                        if item.state == .unknown {
                            Text("This item was attributed heuristically. ATIL avoids destructive control until it has a confident target.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
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

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct StartupMonospaceValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }
}

private struct StartupSectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}

private struct StartupInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
