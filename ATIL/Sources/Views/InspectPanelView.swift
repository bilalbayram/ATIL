import SwiftUI

struct InspectPanelView: View {
    @Environment(ProcessListViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inspector = ProcessInspectorViewModel()

    var body: some View {
        Group {
            if let process = viewModel.selectedProcess {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            ProcessIconView(process: process)
                                .frame(width: 48, height: 48)

                            VStack(alignment: .leading) {
                                Text(process.name)
                                    .font(.title2.bold())

                                if let bundleID = process.bundleIdentifier {
                                    Text(bundleID)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            CategoryBadge(category: process.category)
                        }

                        if !process.classificationReasons.contains(.protectedProcess) {
                            ProcessActionButtons(process: process)
                        }

                        Divider()

                        SectionHeader("Process Info")
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            alignment: .leading,
                            spacing: 12
                        ) {
                            InfoRow(label: "PID", value: "\(process.pid)")
                            InfoRow(label: "Parent PID", value: "\(process.ppid)")
                            InfoRow(label: "User ID", value: "\(process.uid)")
                            InfoRow(label: "Group ID", value: "\(process.gid)")
                            InfoRow(label: "Nice", value: "\(process.niceValue)")
                            InfoRow(label: "State", value: process.processState.rawValue.capitalized)
                            InfoRow(label: "Threads", value: "\(process.threadCount)")
                            InfoRow(label: "Started", value: inspector.formattedStartTime)
                            InfoRow(label: "Uptime", value: inspector.formattedUptime)
                            InfoRow(label: "CPU Time", value: inspector.formattedCPUTime)
                            InfoRow(label: "CPU %", value: inspector.formattedCPUPercent)
                            InfoRow(label: "Resident Memory", value: inspector.formattedResidentMemory)
                            InfoRow(label: "Virtual Memory", value: inspector.formattedVirtualMemory)
                            InfoRow(label: "Bundle Version", value: inspector.bundleVersion)
                        }

                        if let path = process.executablePath {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Executable Path")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(path)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)

                                Button {
                                    viewModel.openStartupItems(for: process)
                                } label: {
                                    Label("Open in Startup Items", systemImage: "power.circle")
                                }
                                .buttonStyle(.link)
                                .padding(.top, 4)
                            }
                        }

                        LazyInspectionSection(
                            title: "Launchd Info",
                            section: .launchd,
                            inspector: inspector
                        ) {
                            Task {
                                await inspector.load(section: .launchd, launchdMap: viewModel.monitor.launchdMap)
                            }
                        } content: {
                            if let job = inspector.inspectionData.launchdJob {
                                LazyVGrid(
                                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                                    alignment: .leading,
                                    spacing: 12
                                ) {
                                    InfoRow(label: "Label", value: job.label)
                                    InfoRow(label: "Domain", value: job.domain)
                                    InfoRow(label: "KeepAlive", value: job.keepAlive ? "Yes" : "No")
                                    InfoRow(label: "RunAtLoad", value: job.runAtLoad ? "Yes" : "No")
                                    InfoRow(label: "Will Respawn", value: job.willRespawn ? "Yes" : "No")
                                }

                                LabeledMonospaceValue(label: "Plist Path", value: job.plistPath)

                                Button {
                                    viewModel.openStartupItems(for: process)
                                } label: {
                                    Label("Manage in Startup Items", systemImage: "power.circle")
                                }
                                .buttonStyle(.link)
                            } else {
                                EmptyDetailState(message: "No launchd association found.")
                            }
                        }

                        LazyInspectionSection(
                            title: "Code Signature",
                            section: .codeSignature,
                            inspector: inspector
                        ) {
                            Task {
                                await inspector.load(section: .codeSignature, launchdMap: viewModel.monitor.launchdMap)
                            }
                        } content: {
                            if let signature = inspector.inspectionData.codeSignature {
                                LazyVGrid(
                                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                                    alignment: .leading,
                                    spacing: 12
                                ) {
                                    InfoRow(label: "Signed", value: signature.isSigned ? "Yes" : "No")
                                    InfoRow(label: "Identity", value: signature.signingIdentity ?? "—")
                                    InfoRow(label: "Team ID", value: signature.teamIdentifier ?? "—")
                                    InfoRow(label: "Code Identifier", value: signature.codeIdentifier ?? "—")
                                    InfoRow(label: "Apple Signed", value: signature.isAppleSigned ? "Yes" : "No")
                                    InfoRow(label: "Notarized", value: signature.isNotarized ? "Yes" : "No")
                                }
                            } else {
                                EmptyDetailState(message: "Signature details are unavailable for this process.")
                            }
                        }

                        LazyInspectionSection(
                            title: "Network",
                            section: .network,
                            inspector: inspector
                        ) {
                            Task {
                                await inspector.load(section: .network, launchdMap: viewModel.monitor.launchdMap)
                            }
                        } content: {
                            NetworkSectionContent(data: inspector.inspectionData)
                        }

                        LazyInspectionSection(
                            title: "Open Files",
                            section: .openFiles,
                            inspector: inspector
                        ) {
                            Task {
                                await inspector.load(section: .openFiles, launchdMap: viewModel.monitor.launchdMap)
                            }
                        } content: {
                            if let files = inspector.inspectionData.openFiles, !files.isEmpty {
                                ForEach(files.prefix(50)) { file in
                                    HStack(spacing: 6) {
                                        Text("fd \(file.fd)")
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.tertiary)
                                            .frame(width: 40, alignment: .trailing)
                                        Text(file.path)
                                            .font(.caption.monospaced())
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .textSelection(.enabled)
                                    }
                                }
                                if files.count > 50 {
                                    Text("... and \(files.count - 50) more")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                EmptyDetailState(message: "No open files were reported.")
                            }
                        }

                        LazyInspectionSection(
                            title: "Energy",
                            section: .energy,
                            inspector: inspector
                        ) {
                            Task {
                                await inspector.load(section: .energy, launchdMap: viewModel.monitor.launchdMap)
                            }
                        } content: {
                            if let usage = inspector.inspectionData.resourceUsage {
                                LazyVGrid(
                                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                                    alignment: .leading,
                                    spacing: 12
                                ) {
                                    InfoRow(label: "Idle Wakeups", value: "\(usage.idleWakeUps)")
                                    InfoRow(label: "Interrupt Wakeups", value: "\(usage.interruptWakeUps)")
                                    InfoRow(label: "Bytes Read", value: formatBytes(usage.bytesRead))
                                    InfoRow(label: "Bytes Written", value: formatBytes(usage.bytesWritten))
                                }
                            } else {
                                EmptyDetailState(message: "Resource usage is unavailable for this process.")
                            }
                        }

                        if !process.classificationReasons.isEmpty {
                            Divider()
                            SectionHeader("Classification Signals")
                            FlowLayout(spacing: 6) {
                                ForEach(
                                    Array(process.classificationReasons).sorted(by: { $0.rawValue < $1.rawValue }),
                                    id: \.self
                                ) { reason in
                                    Text(reason.rawValue)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(reason.isRedundantSignal ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                        }

                        Spacer()
                    }
                    .padding()
                }
                .id(viewModel.selectedProcess?.identity)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .offset(y: 6))
                )
                .onChange(of: viewModel.selectedProcess?.identity) {
                    inspector.selectedProcess = viewModel.selectedProcess
                    inspector.clearInspection()
                }
                .onAppear {
                    inspector.selectedProcess = viewModel.selectedProcess
                    inspector.clearInspection()
                }
            }
        }
        .animation(ATILAnimation.smooth(reduceMotion: reduceMotion), value: viewModel.selectedProcess?.identity)
        .frame(minWidth: 300)
    }
}

private struct LazyInspectionSection<Content: View>: View {
    let title: String
    let section: InspectionSection
    let inspector: ProcessInspectorViewModel
    let onLoad: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var isExpanded = false

    var body: some View {
        Divider()
        DisclosureGroup(isExpanded: $isExpanded) {
            if inspector.hasLoaded(section) {
                content()
                    .transition(.opacity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                    .transition(.opacity)
            }
        } label: {
            SectionHeader(title)
        }
        .animation(ATILAnimation.snappy, value: isExpanded)
        .animation(ATILAnimation.subtle, value: inspector.hasLoaded(section))
        .onChange(of: isExpanded) {
            if isExpanded && !inspector.hasLoaded(section) && !inspector.isLoading(section) {
                onLoad()
            }
        }
        .onChange(of: inspector.loadedSections) {
            if isExpanded && !inspector.hasLoaded(section) && !inspector.isLoading(section) {
                onLoad()
            }
        }
    }
}

private struct NetworkSectionContent: View {
    let data: ProcessInspectionData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            networkContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var networkContent: some View {
        if let listeningPorts = data.listeningPorts, !listeningPorts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Listening Ports")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(listeningPorts) { port in
                    HStack {
                        Text(":\(port.port)")
                            .font(.body.monospaced())
                        Spacer()
                        Text(port.family)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        if let connections = data.establishedConnections, !connections.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Connections")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(connections) { connection in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(connection.localAddress):\(connection.localPort) → \(connection.remoteAddress):\(connection.remotePort)")
                            .font(.caption.monospaced())
                        Text("\(connection.family) • \(connection.state)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        if let unixSockets = data.unixDomainSockets, !unixSockets.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Unix Domain Sockets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(unixSockets) { socket in
                    HStack(spacing: 6) {
                        Text("fd \(socket.fd)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .frame(width: 40, alignment: .trailing)
                        Text(socket.path)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }

        if (data.listeningPorts ?? []).isEmpty
            && (data.establishedConnections ?? []).isEmpty
            && (data.unixDomainSockets ?? []).isEmpty {
            EmptyDetailState(message: "No network activity was reported.")
        }
    }
}

private struct EmptyDetailState: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct LabeledMonospaceValue: View {
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

private struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospaced())
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CategoryBadge: View {
    let category: ProcessCategory

    var body: some View {
        Text(category.displayName)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
            .accessibilityLabel(category.displayName)
    }

    private var color: Color {
        switch category {
        case .quarantined: .purple
        case .redundant: .red
        case .suspicious: .orange
        case .healthy: .green
        }
    }
}

private struct ProcessActionButtons: View {
    let process: ATILProcess
    @Environment(ProcessListViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: 10) {
            if process.processState == .suspended {
                Button {
                    viewModel.resumeSelected()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    Task { await viewModel.killSelected() }
                } label: {
                    Label("Kill", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .accessibilityHint("Terminates this process")

                Button {
                    viewModel.suspendSelected()
                } label: {
                    Label("Suspend", systemImage: "pause.circle")
                }
                .buttonStyle(.bordered)
            }

            Button {
                viewModel.ignoreSelected()
            } label: {
                Label("Ignore", systemImage: "eye.slash")
            }
            .buttonStyle(.bordered)

            Button {
                viewModel.createRuleFromSelected()
            } label: {
                Label("Create Rule", systemImage: "bolt.badge.plus")
            }
            .buttonStyle(.bordered)

            Spacer()
        }
    }
}

/// Simple flow layout for wrapping tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            usedWidth = max(usedWidth, currentX)
        }

        return (
            CGSize(width: min(usedWidth, maxWidth), height: currentY + lineHeight),
            positions
        )
    }
}
