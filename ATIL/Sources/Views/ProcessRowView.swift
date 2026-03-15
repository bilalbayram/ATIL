import SwiftUI
import AppKit

struct ProcessRowView: View {
    let process: ATILProcess
    @Environment(ProcessListViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: 10) {
            ProcessIconView(process: process)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(process.name)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)

                if let path = process.executablePath {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            // Status badges
            HStack(spacing: 4) {
                if process.classificationReasons.contains(.protectedProcess) {
                    StatusBadgeView(text: "protected", icon: "lock.fill", color: .blue)
                }
                if process.shouldDisplayOrphanBadge {
                    StatusBadgeView(text: "orphaned", color: .orange)
                }
                if let idle = process.idleSince {
                    let duration = Date().timeIntervalSince(idle)
                    if duration > 300 {
                        StatusBadgeView(
                            text: "idle \(formatDuration(duration))",
                            color: .yellow
                        )
                    }
                }
                if process.classificationReasons.contains(.blocklistMatch) {
                    StatusBadgeView(text: "blocklist", icon: "list.bullet", color: .red)
                }
                if let job = process.launchdJob, job.willRespawn {
                    StatusBadgeView(text: "respawns", icon: "arrow.counterclockwise", color: .purple)
                }
            }

            // Memory
            Text(formatBytes(process.residentMemory))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)

            // PID
            Text(formatPID(process.pid))
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                Task { await viewModel.killProcess(process) }
            } label: {
                Label("Kill Process", systemImage: "xmark.circle")
            }
            .disabled(process.classificationReasons.contains(.protectedProcess))

            if process.processState == .suspended {
                Button {
                    viewModel.resumeProcess(process)
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
            } else {
                Button {
                    viewModel.suspendProcess(process)
                } label: {
                    Label("Suspend", systemImage: "pause.circle")
                }
                .disabled(process.classificationReasons.contains(.protectedProcess))
            }

            Divider()

            Button {
                viewModel.ignoreProcess(process)
            } label: {
                Label("Ignore", systemImage: "eye.slash")
            }

            Button {
                viewModel.createRuleFrom(process)
            } label: {
                Label("Create Rule…", systemImage: "bolt.badge.plus")
            }

            Divider()

            Button {
                viewModel.inspectProcess(process)
            } label: {
                Label("Inspect", systemImage: "info.circle")
            }

            Divider()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(process.pid)", forType: .string)
            } label: {
                Label("Copy PID", systemImage: "doc.on.doc")
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(process.name, forType: .string)
            } label: {
                Label("Copy Process Name", systemImage: "doc.on.doc")
            }

            if let path = process.executablePath {
                Button {
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(process.name), \(process.category.displayName)")
        .accessibilityValue("PID \(process.pid), \(formatBytes(process.residentMemory))")
    }
}
