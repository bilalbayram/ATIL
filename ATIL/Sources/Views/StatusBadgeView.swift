import SwiftUI

struct StatusBadgeView: View {
    let text: String
    var icon: String? = nil
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8))
            }
            Text(text)
                .font(.system(size: 9, weight: .medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(color)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
        .transition(.opacity)
        .accessibilityLabel(text)
    }
}
