import SwiftUI

struct MainWindowView: View {
    @Environment(ProcessListViewModel.self) private var viewModel
    @State private var showingHistory = false
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
        .onDisappear {
            viewModel.stopMonitoring()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    viewModel.requestSearchFocus()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: .command)
                .help("Focus search")

                Button {
                    viewModel.selectAllVisible()
                } label: {
                    Label("Select Visible", systemImage: "checklist")
                }
                .keyboardShortcut("a", modifiers: .command)
                .help("Select all visible process rows")

                Toggle(isOn: $vm.showGrouped) {
                    Label("Group by App", systemImage: "rectangle.3.group")
                }
                .toggleStyle(.button)
                .help("Group processes by application bundle")

                Button {
                    showingHistory.toggle()
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .help("Show kill history")

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
        .sheet(isPresented: $showingHistory) {
            NavigationStack {
                HistoryListView()
            }
            .frame(minWidth: 560, minHeight: 420)
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
        .sheet(isPresented: $vm.showingLaunchdConfirmation) {
            if let process = viewModel.launchdConfirmProcess {
                LaunchdConfirmationView(process: process) {
                    // Kill only
                    Task { await viewModel.performKill(process: process) }
                    viewModel.showingLaunchdConfirmation = false
                    viewModel.launchdConfirmProcess = nil
                } onKillAndDisable: {
                    Task { await viewModel.killAndDisableRespawn(process: process) }
                } onCancel: {
                    viewModel.showingLaunchdConfirmation = false
                    viewModel.launchdConfirmProcess = nil
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.lastError != nil },
            set: { if !$0 { viewModel.lastError = nil } }
        )) {
            Button("OK") { viewModel.lastError = nil }
        } message: {
            Text(viewModel.lastError ?? "")
        }
    }
}
