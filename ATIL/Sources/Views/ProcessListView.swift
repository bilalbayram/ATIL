import SwiftUI

struct ProcessListView: View {
    @Environment(ProcessListViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var vm = viewModel

        ZStack(alignment: .bottom) {
            List(selection: $vm.selectedProcessIDs) {
                ForEach(viewModel.categorizedProcesses, id: \.category) { group in
                    CategorySectionView(
                        category: group.category,
                        processes: group.processes,
                        groups: viewModel.showGrouped ? viewModel.groupedProcesses[group.category] : nil
                    )
                }
            }
            .listStyle(.sidebar)
            .animation(ATILAnimation.subtle(reduceMotion: reduceMotion), value: viewModel.searchText)
            .animation(ATILAnimation.snappy(reduceMotion: reduceMotion), value: viewModel.showGrouped)
            .overlay {
                if viewModel.monitor.isScanning && viewModel.monitor.snapshot.isEmpty {
                    ProgressView("Scanning processes...")
                        .transition(.opacity)
                } else if viewModel.filteredProcesses.isEmpty && !viewModel.searchText.isEmpty {
                    ContentUnavailableView.search(text: viewModel.searchText)
                        .transition(.opacity)
                }
            }
            .onKeyPress(.delete) {
                Task { await viewModel.killAllSelected() }
                return .handled
            }
            .onKeyPress(.space) {
                viewModel.toggleSuspendResumeForSelection()
                return .handled
            }
            .onKeyPress(.return) {
                viewModel.selectedProcessID = viewModel.selectedProcessIDs.count == 1 ? viewModel.selectedProcessIDs.first : nil
                return .handled
            }
            .onKeyPress("i") {
                viewModel.ignoreAllSelected()
                return .handled
            }
            .onKeyPress("r") {
                viewModel.createRuleFromSelected()
                return .handled
            }
            .onKeyPress(.escape) {
                viewModel.clearSelection()
                return .handled
            }
            .onChange(of: vm.selectedProcessIDs) {
                // Expand group sentinel tags to their child process IDs
                vm.resolveGroupSentinels()
                // Sync single selection for inspect panel
                vm.selectedProcessID = vm.selectedProcessIDs.count == 1 ? vm.selectedProcessIDs.first : nil
            }

            // Batch action bar
            if viewModel.hasMultipleSelection {
                BatchActionBarView(selectedCount: viewModel.selectedProcessIDs.count)
                    .padding(.bottom, 8)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .bottom).combined(with: .opacity)
                    )
            }
        }
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.15)
                : ATILAnimation.smooth,
            value: viewModel.hasMultipleSelection
        )
    }
}
