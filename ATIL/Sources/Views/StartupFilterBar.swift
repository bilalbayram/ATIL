import SwiftUI

struct StartupFilterBar: View {
    @Environment(StartupItemsViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 10) {
            TextField("Search apps, labels, or paths", text: $vm.searchText)
                .textFieldStyle(.roundedBorder)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StartupFilter.allCases) { filter in
                        StartupFilterChip(
                            filter: filter,
                            isActive: viewModel.activeFilters.contains(filter)
                        ) {
                            viewModel.toggleFilter(filter)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }

            if !viewModel.activeFilters.isEmpty {
                Button("Clear Filters") {
                    viewModel.clearFilters()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
    }
}

struct StartupFilterChip: View {
    let filter: StartupFilter
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: filter.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(filter.displayName)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isActive ? filter.color : .secondary)
            .background(
                Capsule()
                    .fill(isActive ? filter.color.opacity(0.14) : .clear)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isActive ? filter.color.opacity(0.3) : .secondary.opacity(isHovered ? 0.3 : 0.15),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainPressableButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
