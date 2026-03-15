import SwiftUI

struct FilterBarView: View {
    @Environment(ProcessListViewModel.self) private var viewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        @Bindable var vm = viewModel

        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search processes...", text: $vm.searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(.bar)
        .onChange(of: viewModel.searchFocusNonce) {
            isSearchFocused = true
        }
    }
}
