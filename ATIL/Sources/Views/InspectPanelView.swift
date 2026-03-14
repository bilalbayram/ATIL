import SwiftUI

struct InspectPanelView: View {
    @Environment(ProcessListViewModel.self) private var viewModel
    @State private var inspector = ProcessInspectorViewModel()

    var body: some View {
        Group {
            if let process = viewModel.selectedProcess {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header
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

                        Divider()

                        // Core info grid
                        SectionHeader("Process Info")
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                        ], alignment: .leading, spacing: 12) {
                            InfoRow(label: "PID", value: "\(process.pid)")
                            InfoRow(label: "Parent PID", value: "\(process.ppid)")
                            InfoRow(label: "User ID", value: "\(process.uid)")
                            InfoRow(label: "State", value: process.processState.rawValue.capitalized)
                            InfoRow(label: "Threads", value: "\(process.threadCount)")
                            InfoRow(label: "Started", value: inspector.formattedStartTime)
                            InfoRow(label: "Uptime", value: inspector.formattedUptime)
                            InfoRow(label: "CPU Time", value: inspector.formattedCPUTime)
                            InfoRow(label: "Resident Memory", value: inspector.formattedResidentMemory)
                            InfoRow(label: "Virtual Memory", value: inspector.formattedVirtualMemory)
                        }

                        if let path = process.executablePath {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Executable Path")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(path)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                        }

                        // Launchd Info
                        if let job = process.launchdJob {
                            Divider()
                            SectionHeader("Launchd Job")
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                            ], alignment: .leading, spacing: 12) {
                                InfoRow(label: "Label", value: job.label)
                                InfoRow(label: "KeepAlive", value: job.keepAlive ? "Yes" : "No")
                                InfoRow(label: "RunAtLoad", value: job.runAtLoad ? "Yes" : "No")
                                InfoRow(label: "Will Respawn", value: job.willRespawn ? "Yes" : "No")
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Plist Path")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(job.plistPath)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                        }

                        // Code Signature (loaded lazily)
                        if let sig = inspector.inspectionData?.codeSignature {
                            Divider()
                            SectionHeader("Code Signature")
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                            ], alignment: .leading, spacing: 12) {
                                InfoRow(label: "Signed", value: sig.isSigned ? "Yes" : "No")
                                InfoRow(label: "Identity", value: sig.signingIdentity ?? "—")
                                InfoRow(label: "Team ID", value: sig.teamIdentifier ?? "—")
                                InfoRow(label: "Apple Signed", value: sig.isAppleSigned ? "Yes" : "No")
                                InfoRow(label: "Notarized", value: sig.isNotarized ? "Yes" : "No")
                            }
                        }

                        // Listening Ports
                        if let ports = inspector.inspectionData?.listeningPorts, !ports.isEmpty {
                            Divider()
                            SectionHeader("Listening Ports")
                            ForEach(ports) { port in
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

                        // Open Files (loaded lazily, show first 50)
                        if let files = inspector.inspectionData?.openFiles, !files.isEmpty {
                            Divider()
                            SectionHeader("Open Files (\(files.count))")
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
                        }

                        // Classification reasons
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

                        // Loading indicator
                        if inspector.isLoadingInspection {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading inspection data...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .padding()
                }
                .onChange(of: viewModel.selectedProcess?.identity) {
                    inspector.selectedProcess = viewModel.selectedProcess
                    inspector.clearInspection()
                    Task {
                        await inspector.loadInspection(launchdMap: viewModel.monitor.launchdMap)
                    }
                }
                .onAppear {
                    inspector.selectedProcess = viewModel.selectedProcess
                    Task {
                        await inspector.loadInspection(launchdMap: viewModel.monitor.launchdMap)
                    }
                }
            }
        }
        .frame(minWidth: 300)
    }
}

// MARK: - Helper Views

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
    }
}

private struct CategoryBadge: View {
    let category: ProcessCategory

    var body: some View {
        Text(category.displayName)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(.white)
            .background(color)
            .clipShape(Capsule())
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
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
