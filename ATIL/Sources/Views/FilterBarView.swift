import SwiftUI

struct FilterBarView: View {
    @Environment(ProcessListViewModel.self) private var viewModel
    @FocusState private var isSearchFocused: Bool
    @State private var isClearHovered = false

    var body: some View {
        @Bindable var vm = viewModel

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
        .background(.bar)
        .onChange(of: viewModel.searchFocusNonce) {
            isSearchFocused = true
        }
    }
}
