import SwiftUI

struct StartupGroupRow: View {
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
