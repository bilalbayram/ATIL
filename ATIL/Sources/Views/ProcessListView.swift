import SwiftUI

struct ProcessListView: View {
    @Environment(ProcessListViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        List(selection: $vm.selectedProcessID) {
            ForEach(viewModel.categorizedProcesses, id: \.category) { group in
                CategorySectionView(
                    category: group.category,
                    processes: group.processes,
                    groups: viewModel.showGrouped ? viewModel.groupedProcesses[group.category] : nil
                )
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if viewModel.monitor.isScanning && viewModel.monitor.snapshot.isEmpty {
                ProgressView("Scanning processes...")
            } else if viewModel.filteredProcesses.isEmpty && !viewModel.searchText.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
            }
        }
        .onKeyPress(.delete) {
            Task { await viewModel.killSelected() }
            return .handled
        }
        .onKeyPress("i") {
            viewModel.ignoreSelected()
            return .handled
        }
    }
}
