import SwiftUI

struct FilterBarView: View {
    @Environment(ProcessListViewModel.self) private var viewModel
    @FocusState private var isSearchFocused: Bool
    @State private var isClearHovered = false
    @State private var isClearTagsHovered = false

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            // Search row
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search processes...", text: $vm.searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .accessibilityLabel("Search processes")

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(isClearHovered ? .primary : .secondary)
                            .animation(ATILAnimation.quick, value: isClearHovered)
                    }
                    .buttonStyle(PlainPressableButtonStyle())
                    .onHover { hovering in
                        isClearHovered = hovering
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(8)

            // Tag filter row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ProcessStatusTag.allCases, id: \.self) { tag in
                        FilterTagView(
                            tag: tag,
                            count: viewModel.tagCounts[tag] ?? 0,
                            isActive: viewModel.activeFilterTags.contains(tag),
                            action: { viewModel.toggleFilterTag(tag) }
                        )
                    }

                    if !viewModel.activeFilterTags.isEmpty {
                        Button {
                            viewModel.clearFilterTags()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(isClearTagsHovered ? .primary : .secondary)
                                .frame(width: 20, height: 20)
                                .background(
                                    Circle()
                                        .fill(.secondary.opacity(isClearTagsHovered ? 0.15 : 0.08))
                                )
                                .animation(ATILAnimation.quick, value: isClearTagsHovered)
                        }
                        .buttonStyle(PlainPressableButtonStyle())
                        .onHover { hovering in
                            isClearTagsHovered = hovering
                        }
                        .accessibilityLabel("Clear all filters")
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }

            Divider()
        }
        .background(.bar)
        .onChange(of: viewModel.searchFocusNonce) {
            isSearchFocused = true
        }
    }
}
