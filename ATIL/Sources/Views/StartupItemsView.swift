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
                if viewModel.isLoadingInitialSnapshot {
                    ContentUnavailableView {
                        ProgressView()
                    } description: {
                        Text("Scanning startup and background items...")
                    }
                } else if let group = viewModel.selectedGroup {
                    VStack(alignment: .leading, spacing: 0) {
                        StartupGroupHeader(group: group)
                        Divider()
                        StartupActionPanel(group: group)
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

    var body: some View {
        HStack(spacing: 10) {
            StartupAppIconView(
                group: group,
                size: 26,
                cornerRadius: 6,
                placeholderSystemName: "app.dashed"
            )

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

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            StartupAppIconView(
                group: group,
                size: 44,
                cornerRadius: 10,
                placeholderSystemName: "app.badge"
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(group.app.displayName)
                    .font(.title3.bold())

                if let bundleIdentifier = group.app.bundleIdentifier {
                    Text(bundleIdentifier)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        badges
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        badges
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    @ViewBuilder
    private var badges: some View {
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

private struct StartupActionPanel: View {
    @Environment(StartupItemsViewModel.self) private var viewModel

    let group: StartupAppGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    refreshButton
                    blockButton
                    disableButton
                    moreButton
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        refreshButton
                        blockButton
                    }

                    HStack(spacing: 8) {
                        disableButton
                        moreButton
                    }
                }
            }

            StartupActionStatusLine(
                feedback: viewModel.actionFeedback,
                selectedItemLabel: viewModel.selectedItem?.displayLabel
            )
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 820, alignment: .leading)
    }

    private var refreshButton: some View {
        Button {
            Task { await viewModel.refreshManually() }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .disabled(viewModel.isPerformingUserAction)
    }

    private var blockButton: some View {
        Button {
            Task {
                if group.isBlocked {
                    await viewModel.unblockSelectedApp()
                } else {
                    await viewModel.blockSelectedApp()
                }
            }
        } label: {
            Label(group.isBlocked ? "Unblock App" : "Block App", systemImage: group.isBlocked ? "shield" : "shield.slash")
        }
        .disabled(viewModel.isPerformingUserAction)
    }

    private var disableButton: some View {
        Button {
            Task { await viewModel.disableSelectedItem() }
        } label: {
            Label("Disable", systemImage: "power.slash")
        }
        .disabled(!canDisableSelectedItem)
    }

    private var moreButton: some View {
        Menu {
            Button("Kill Current Process") {
                Task { await viewModel.killSelectedProcess() }
            }
            .disabled(viewModel.selectedRunningProcess == nil || viewModel.isPerformingUserAction)

            Button("Reveal File") {
                viewModel.revealSelectedItem()
            }
            .disabled(!canRevealSelectedItem || viewModel.isPerformingUserAction)
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .disabled(viewModel.selectedItem == nil || viewModel.isPerformingUserAction)
    }

    private var canDisableSelectedItem: Bool {
        guard let item = viewModel.selectedItem else { return false }
        return item.canDisable && item.state != .unknown && !viewModel.isPerformingUserAction
    }

    private var canRevealSelectedItem: Bool {
        guard let item = viewModel.selectedItem else { return false }
        return item.plistPath != nil || item.executablePath != nil
    }
}

private struct StartupActionStatusLine: View {
    let feedback: StartupActionFeedback?
    let selectedItemLabel: String?

    var body: some View {
        HStack(spacing: 8) {
            if let feedback {
                switch feedback.style {
                case .progress:
                    ProgressView()
                        .controlSize(.small)
                    Text(feedback.message)
                        .foregroundStyle(.secondary)
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(feedback.message)
                        .foregroundStyle(.green)
                }
            } else if let selectedItemLabel {
                Image(systemName: "cursorarrow.click.2")
                    .foregroundStyle(.secondary)
                Text("Selected item: \(selectedItemLabel)")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "sidebar.left")
                    .foregroundStyle(.secondary)
                Text("Select a startup item to disable, reveal, or stop it.")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .font(.caption)
        .frame(minHeight: 18, alignment: .leading)
    }
}

private struct StartupAppIconView: View {
    let group: StartupAppGroup
    let size: CGFloat
    let cornerRadius: CGFloat
    let placeholderSystemName: String

    @Environment(StartupItemsViewModel.self) private var viewModel

    var body: some View {
        Group {
            if let icon = viewModel.icon(for: group) {
                Image(nsImage: icon)
                    .resizable()
            } else {
                Image(systemName: placeholderSystemName)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.secondary.opacity(0.08))
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: group.id) {
            viewModel.loadIconIfNeeded(for: group)
        }
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
                        StartupDetailHeadline(item: item)

                        StartupDetailFacts(rows: [
                            ("State", item.state.displayName),
                            ("Scope", item.scope.displayName),
                            ("Kind", item.kind.displayName),
                            ("Confidence", item.attributionConfidence.displayName),
                            ("Needs Helper", item.requiresHelper ? "Yes" : "No"),
                            ("Blocked", viewModel.isBlocked(item) ? "Yes" : "No")
                        ])

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
                            StartupDetailFacts(rows: [
                                ("PID", "\(process.pid)"),
                                ("Memory", formatBytes(process.residentMemory)),
                                ("CPU %", String(format: "%.1f", process.cpuPercent)),
                                ("Started", formatDateTime(process.startTime))
                            ])
                        }

                        if item.state == .unknown {
                            Text("This item was attributed heuristically. ATIL avoids destructive control until it has a confident target.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

private struct StartupDetailHeadline: View {
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

private struct StartupDetailFacts: View {
    let rows: [(label: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                StartupInfoRow(label: row.label, value: row.value)
            }
        }
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
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
