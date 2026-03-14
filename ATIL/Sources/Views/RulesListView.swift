import SwiftUI

/// Lists all auto-action rules with ability to add, edit, toggle, and delete.
struct RulesListView: View {
    @State private var rules: [AutoRule] = []
    @State private var editingRule: AutoRule?
    @State private var showingRuleBuilder = false

    private let ruleRepo = RuleRepository(db: DatabaseManager.shared)

    var body: some View {
        VStack(spacing: 0) {
            if rules.isEmpty {
                ContentUnavailableView(
                    "No Rules",
                    systemImage: "bolt.slash",
                    description: Text("Create rules to automatically manage processes")
                )
            } else {
                List {
                    ForEach(rules) { rule in
                        RuleRowView(rule: rule) {
                            toggleRule(rule)
                        } onEdit: {
                            editingRule = rule
                            showingRuleBuilder = true
                        } onDelete: {
                            deleteRule(rule)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingRule = nil
                    showingRuleBuilder = true
                } label: {
                    Label("New Rule", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingRuleBuilder) {
            let rule = editingRule ?? AutoRule(
                name: "",
                matcherType: .name,
                matcherValue: "",
                conditionJSON: "[]",
                action: .kill,
                cooldownSeconds: 600,
                enabled: true,
                createdAt: Date()
            )
            RuleBuilderView(rule: .constant(rule)) { saved in
                saveRule(saved)
                showingRuleBuilder = false
            } onCancel: {
                showingRuleBuilder = false
            }
        }
        .onAppear { loadRules() }
        .navigationTitle("Auto-Action Rules")
    }

    private func loadRules() {
        rules = (try? ruleRepo.allRules()) ?? []
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
}

private struct RuleRowView: View {
    let rule: AutoRule
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .font(.body.weight(rule.enabled ? .medium : .regular))
                    .foregroundStyle(rule.enabled ? .primary : .secondary)

                Text("\(rule.matcherType.rawValue): \(rule.matcherValue) → \(rule.action.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}
