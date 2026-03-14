import SwiftUI

struct MainWindowView: View {
    @Environment(ProcessListViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        NavigationSplitView {
            VStack(spacing: 0) {
                FilterBarView()
                ProcessListView()
                Divider()
                FooterStatsView()
            }
            .navigationSplitViewColumnWidth(min: 350, ideal: 500)
        } detail: {
            if viewModel.selectedProcess != nil {
                InspectPanelView()
            } else {
                ContentUnavailableView(
                    "No Process Selected",
                    systemImage: "cpu",
                    description: Text("Select a process to inspect its details")
                )
            }
        }
        .navigationTitle("ATIL")
        .task {
            viewModel.startMonitoring()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(viewModel.monitor.isScanning)
            }
        }
    }
}
