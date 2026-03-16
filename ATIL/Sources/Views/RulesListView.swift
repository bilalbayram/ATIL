import Foundation
import SwiftUI

/// Lists all auto-action rules with quick-create affordances and live status context.
struct RulesListView: View {
    @Environment(ProcessListViewModel.self) private var viewModel

    @State private var rules: [AutoRule] = []
    @State private var editingRule: AutoRule?
    @State private var ruleToDelete: AutoRule?
    @State private var activityByRuleId: [Int64: RuleRepository.ActivitySummary] = [:]

    private let ruleRepo = RuleRepository(db: DatabaseManager.shared)

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            if rules.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(rules) { rule in
                        RuleRowView(
                            rule: rule,
                            activity: rule.id.flatMap { activityByRuleId[$0] }
                        ) {
                            toggleRule(rule)
                        } onEdit: {
                            presentRuleBuilder(for: rule)
                        } onDelete: {
                            ruleToDelete = rule
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .alert("Delete Rule", isPresented: Binding(
            get: { ruleToDelete != nil },
            set: { if !$0 { ruleToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { ruleToDelete = nil }
            Button("Delete", role: .destructive) {
                if let rule = ruleToDelete {
                    deleteRule(rule)
                    ruleToDelete = nil
                }
            }
        } message: {
            if let rule = ruleToDelete {
                Text("Delete \"\(rule.name.isEmpty ? rule.suggestedName : rule.name)\"? This cannot be undone.")
            }
        }
        .sheet(item: $editingRule) { rule in
            RuleBuilderView(initialRule: rule) { saved in
                saveRule(saved)
                dismissRuleBuilder()
            } onCancel: {
                dismissRuleBuilder()
            }
        }
        .onAppear(perform: loadRules)
    }

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Action Rules")
                        .font(.title3.weight(.semibold))
                    Text("\(rules.count) rule\(rules.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if viewModel.selectedProcess != nil {
                    Button("From Selected", systemImage: "sparkles") {
                        createRuleFromSelectedProcess()
                    }
                    .buttonStyle(.bordered)
                }

                Button("New Rule", systemImage: "plus") {
                    presentBlankRuleBuilder()
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Plain-English summaries, live match counts, and quick creation from the current selection.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Rules Yet", systemImage: "bolt.slash")
        } description: {
            Text("Create rules from the current selection, or start from a template and preview the matches live.")
        } actions: {
            if viewModel.selectedProcess != nil {
                Button("Create From Selected Process") {
                    createRuleFromSelectedProcess()
                }
                .buttonStyle(.borderedProminent)
            }

            Button("Create Blank Rule") {
                presentBlankRuleBuilder()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var blankRule: AutoRule {
        AutoRule(
            name: "",
            matcherType: .name,
            matcherValue: "",
            conditionJSON: "[]",
            contextAppBundleId: nil,
            contextAppMustBeRunning: nil,
            action: .kill,
            cooldownSeconds: 600,
            enabled: true,
            createdAt: Date()
        )
    }

    private func loadRules() {
        withAnimation(ATILAnimation.subtle) {
            rules = (try? ruleRepo.allRules()) ?? []
            activityByRuleId = (try? ruleRepo.activitySummaries()) ?? [:]
        }
    }

    private func saveRule(_ rule: AutoRule) {
        _ = try? ruleRepo.save(rule)
        loadRules()
    }

    private func toggleRule(_ rule: AutoRule) {
        _ = try? ruleRepo.toggleEnabled(rule)
        loadRules()
    }

    private func deleteRule(_ rule: AutoRule) {
        try? ruleRepo.delete(rule)
        loadRules()
    }

    private func createRuleFromSelectedProcess() {
        guard let process = viewModel.selectedProcess else { return }
        presentRuleBuilder(for: viewModel.monitor.ruleEngine.createRuleFromProcess(process, action: .kill))
    }

    private func presentBlankRuleBuilder() {
        presentRuleBuilder(for: blankRule)
    }

    private func presentRuleBuilder(for rule: AutoRule) {
        editingRule = rule
    }

    private func dismissRuleBuilder() {
        editingRule = nil
    }
}

private struct RuleRowView: View {
    @Environment(ProcessListViewModel.self) private var viewModel

    let rule: AutoRule
    let activity: RuleRepository.ActivitySummary?
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: rule.action.symbolName)
                .foregroundStyle(rule.action.tintColor)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(rule.name.isEmpty ? rule.suggestedName : rule.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(rule.enabled ? .primary : .secondary)

                    StatusBadgeView(
                        text: rule.enabled ? "active" : "paused",
                        color: rule.enabled ? .green : .secondary
                    )
                }

                Text(rule.summarySentence)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                FlowLayout(spacing: 6) {
                    StatusBadgeView(
                        text: "\(matchCount) match\(matchCount == 1 ? "" : "es") now",
                        color: matchCount == 0 ? .secondary : .green
                    )

                    StatusBadgeView(
                        text: "cooldown \(formatDuration(TimeInterval(rule.cooldownSeconds)))",
                        color: .secondary
                    )

                    if let lastTriggeredAt = activity?.lastTriggeredAt {
                        StatusBadgeView(
                            text: "last fired \(relativeTimestamp(lastTriggeredAt))",
                            color: .secondary
                        )
                    }

                    if let triggerCountToday = activity?.triggerCountToday, triggerCountToday > 0 {
                        StatusBadgeView(
                            text: "\(triggerCountToday) today",
                            color: .secondary
                        )
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onToggle) {
                    Image(systemName: rule.enabled ? "pause.fill" : "play.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(rule.enabled ? .orange : .green)
                }
                .buttonStyle(PlainPressableButtonStyle())
                .help(rule.enabled ? "Pause rule" : "Activate rule")

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                }
                .buttonStyle(PlainPressableButtonStyle())
                .help("Edit rule")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
                .buttonStyle(PlainPressableButtonStyle())
                .help("Delete rule")
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 8)
    }

    private var matchCount: Int {
        viewModel.monitor.ruleEngine.previewMatches(
            for: rule,
            in: viewModel.monitor.snapshot
        ).count
    }
}

private func relativeTimestamp(_ date: Date) -> String {
    RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
}
