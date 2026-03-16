import SwiftUI

struct MainWindowView: View {
    @Environment(ProcessListViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingHistory = false
    @State private var showingRules = false

    private var refreshIcon: some View {
        Image(systemName: "arrow.clockwise")
            .rotationEffect(.degrees(viewModel.monitor.isScanning && !reduceMotion ? 360 : 0))
            .animation(
                viewModel.monitor.isScanning && !reduceMotion
                    ? .linear(duration: 1).repeatForever(autoreverses: false)
                    : .default,
                value: viewModel.monitor.isScanning
            )
    }

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
            Group {
                if viewModel.selectedProcess != nil {
                    InspectPanelView()
                } else if viewModel.selectedProcessIDs.count > 1 {
                    MultiSelectionSummaryView()
                } else {
                    ContentUnavailableView(
                        "No Process Selected",
                        systemImage: "cpu",
                        description: Text("Select a process to inspect its details")
                    )
                }
            }
            .contentTransition(.opacity)
            .animation(ATILAnimation.subtle, value: viewModel.selectedProcess != nil)
        }
        .navigationTitle("ATIL")
        .focusedSceneValue(\.viewModel, viewModel)
        .task {
            viewModel.startMonitoring()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    viewModel.requestSearchFocus()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: .command)
                .help("Focus search")

                Toggle(isOn: $vm.showGrouped) {
                    Label("Group by App", systemImage: "rectangle.3.group")
                }
                .toggleStyle(.button)
                .help("Group processes by application bundle")
            }

            ToolbarItemGroup(placement: .primaryAction) {
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
                    Label { Text("Refresh") } icon: { refreshIcon }
                }
                .help("Refresh process list")
                .disabled(viewModel.monitor.isScanning)
            }
        }
        .sheet(isPresented: $showingRules) {
            RulesListView()
            .frame(minWidth: 560, minHeight: 480)
        }
        .sheet(isPresented: $showingHistory) {
            NavigationStack {
                HistoryListView()
            }
            .frame(minWidth: 560, minHeight: 420)
        }
        .sheet(isPresented: $vm.showingRuleBuilder) {
            if let rule = viewModel.ruleBuilderRule {
                RuleBuilderView(initialRule: rule) { saved in
                    viewModel.saveRule(saved)
                } onCancel: {
                    viewModel.showingRuleBuilder = false
                    viewModel.ruleBuilderRule = nil
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
