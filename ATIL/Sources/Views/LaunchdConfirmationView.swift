import SwiftUI

/// Confirmation dialog shown before killing a process that will respawn via launchd.
struct LaunchdConfirmationView: View {
    let process: ATILProcess
    let onKillOnly: () -> Void
    let onKillAndDisable: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("This process will restart automatically")
                .font(.headline)

            if let job = process.launchdJob {
                VStack(alignment: .leading, spacing: 4) {
                    Text("**\(process.name)** is managed by launchd:")
                        .font(.body)

                    Text("Label: \(job.label)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    if job.keepAlive {
                        Text("KeepAlive: enabled — launchd will restart it immediately")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if job.runAtLoad {
                        Text("RunAtLoad: enabled — will start at next login")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Kill Only") {
                    onKillOnly()
                }

                Button("Kill + Disable Respawn") {
                    onKillAndDisable()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(24)
        .frame(width: 450)
    }
}
