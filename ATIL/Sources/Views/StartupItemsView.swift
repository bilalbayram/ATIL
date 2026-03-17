import SwiftUI

struct StartupItemsView: View {
    @Environment(StartupItemsViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var vm = viewModel

        NavigationSplitView {
            VStack(spacing: 0) {
                StartupFilterBar()
                List(selection: $vm.selectedGroupID) {
                    ForEach(viewModel.groups) { group in
                        StartupGroupRow(group: group)
                            .tag(group.id)
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 320)
        } detail: {
            Group {
                if viewModel.isLoadingInitialSnapshot {
                    ContentUnavailableView {
                        ProgressView()
                    } description: {
                        Text("Scanning startup and background items...")
                    }
                } else if let group = viewModel.selectedGroup {
                    VStack(alignment: .leading, spacing: 0) {
                        StartupGroupHeader(group: group)
                        Divider()
                        StartupActionPanel(group: group)
                        Divider()
                        List(selection: $vm.selectedItemID) {
                            ForEach(group.items) { item in
                                StartupItemRow(item: item, isBlocked: viewModel.isBlocked(item))
                                    .tag(item.id)
                            }
                        }
                        .frame(minHeight: 220)
                        Divider()
                        StartupItemDetail()
                    }
                } else {
                    ContentUnavailableView(
                        "No Startup Items",
                        systemImage: "power.circle",
                        description: Text("ATIL has not discovered any startup or background items yet.")
                    )
                }
            }
            .animation(ATILAnimation.subtle(reduceMotion: reduceMotion), value: viewModel.selectedGroupID)
        }
        .navigationTitle("Startup Items")
        .task {
            await viewModel.refresh()
        }
        .alert("Startup Items Error", isPresented: Binding(
            get: { viewModel.lastError != nil },
            set: { if !$0 { viewModel.lastError = nil } }
        )) {
            Button("OK") { viewModel.lastError = nil }
        } message: {
            Text(viewModel.lastError ?? "")
        }
    }
}
