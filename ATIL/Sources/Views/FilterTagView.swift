import SwiftUI

struct FilterTagView: View {
    let tag: ProcessStatusTag
    let count: Int
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = tag.icon {
                    Image(systemName: icon)
                        .font(.system(size: 9))
                }

                Text(tag.displayName)
                    .font(.system(size: 11, weight: .medium))

                Text("\(count)")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(isActive ? tag.color.opacity(0.25) : .secondary.opacity(0.12))
                    )
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isActive ? tag.color : .secondary)
            .background(
                Capsule()
                    .fill(isActive ? tag.color.opacity(0.15) : .clear)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isActive ? tag.color.opacity(0.3) : .secondary.opacity(isHovered ? 0.3 : 0.15),
                        lineWidth: 1
                    )
            )
            .animation(ATILAnimation.quick, value: isActive)
            .animation(ATILAnimation.quick, value: isHovered)
        }
        .buttonStyle(PlainPressableButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel("\(tag.displayName) filter, \(count) processes")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityHint(isActive ? "Double-tap to remove filter" : "Double-tap to filter by \(tag.displayName)")
    }
}
