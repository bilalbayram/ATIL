import SwiftUI

struct StartupGroupHeader: View {
    let group: StartupAppGroup

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
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
        .padding()
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
