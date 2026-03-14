import SwiftUI

struct ProcessRowView: View {
    let process: ATILProcess

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
                if process.isOrphaned {
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
    }
}
