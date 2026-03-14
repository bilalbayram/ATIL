import SwiftUI

struct MainWindowView: View {
    @Environment(ProcessListViewModel.self) private var viewModel
    @State private var showingRules = false

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
                Toggle(isOn: $vm.showGrouped) {
                    Label("Group by App", systemImage: "rectangle.3.group")
                }
                .toggleStyle(.button)
                .help("Group processes by application bundle")

                Button {
                    showingRules.toggle()
                } label: {
                    Label("Rules", systemImage: "bolt")
                }
                .help("Manage auto-action rules")

                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(viewModel.monitor.isScanning)
            }
        }
        .sheet(isPresented: $showingRules) {
            NavigationStack {
                RulesListView()
            }
            .frame(minWidth: 500, minHeight: 400)
        }
        .sheet(isPresented: $vm.showingRuleBuilder) {
            if var rule = viewModel.ruleBuilderRule {
                RuleBuilderView(rule: Binding(
                    get: { rule },
                    set: { rule = $0 }
                )) { saved in
                    viewModel.saveRule(saved)
                } onCancel: {
                    viewModel.showingRuleBuilder = false
                }
            }
        }
    }
}
