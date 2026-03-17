import SwiftUI

struct StartupAppIconView: View {
    let group: StartupAppGroup
    let size: CGFloat
    let cornerRadius: CGFloat
    let placeholderSystemName: String

    @Environment(StartupItemsViewModel.self) private var viewModel

    var body: some View {
        Group {
            if let icon = viewModel.icon(for: group) {
                Image(nsImage: icon)
                    .resizable()
            } else {
                Image(systemName: placeholderSystemName)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.secondary.opacity(0.08))
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: group.id) {
            viewModel.loadIconIfNeeded(for: group)
        }
    }
}
