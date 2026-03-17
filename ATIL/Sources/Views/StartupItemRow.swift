import SwiftUI

struct StartupItemRow: View {
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
