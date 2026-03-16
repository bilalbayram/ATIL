import SwiftUI

/// Lists all auto-action rules with ability to add, edit, toggle, and delete.
struct RulesListView: View {
    @State private var rules: [AutoRule] = []
    @State private var editingRule: AutoRule?
    @State private var showingRuleBuilder = false
    @State private var ruleToDelete: AutoRule?

    private let ruleRepo = RuleRepository(db: DatabaseManager.shared)

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header bar
            HStack {
                Text("\(rules.count) rule\(rules.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add Rule", systemImage: "plus") {
                    editingRule = nil
                    showingRuleBuilder = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // MARK: - Content
            if rules.isEmpty {
                ContentUnavailableView {
                    Label("No Rules", systemImage: "bolt.slash")
                } description: {
                    Text("Create rules to automatically manage processes")
                } actions: {
                    Button("Create Rule") {
                        editingRule = nil
                        showingRuleBuilder = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(rules) { rule in
                        RuleRowView(rule: rule) {
                            toggleRule(rule)
                        } onEdit: {
                            editingRule = rule
                            showingRuleBuilder = true
                        } onDelete: {
                            ruleToDelete = rule
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
                Text("Are you sure you want to delete \"\(rule.name)\"? This cannot be undone.")
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
        withAnimation(ATILAnimation.subtle) {
            rules = (try? ruleRepo.allRules()) ?? []
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
}

// MARK: - Rule Row

private struct RuleRowView: View {
    let rule: AutoRule
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Leading: action icon
            Image(systemName: actionIconName)
                .foregroundStyle(actionIconColor)
                .font(.system(size: 16))
                .frame(width: 24, height: 24)

            // Center: name + match description + condition pills
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(rule.enabled ? .primary : .secondary)

                Text("\(rule.matcherType.displayName): \(rule.matcherValue) \u{2192} \(rule.action.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !rule.conditions.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(Array(rule.conditions.enumerated()), id: \.offset) { _, condition in
                            StatusBadgeView(
                                text: conditionPillText(condition),
                                color: .secondary
                            )
                        }
                    }
                }
            }

            Spacer()

            // Trailing: status pill + action buttons
            VStack(alignment: .trailing, spacing: 6) {
                StatusBadgeView(
                    text: rule.enabled ? "active" : "paused",
                    color: rule.enabled ? .green : .secondary
                )

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
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Action Icon

    private var actionIconName: String {
        switch rule.action {
        case .kill: "xmark.circle.fill"
        case .suspend: "pause.circle.fill"
        case .markRedundant: "archivebox.circle.fill"
        case .markSuspicious: "exclamationmark.triangle.fill"
        }
    }

    private var actionIconColor: Color {
        switch rule.action {
        case .kill: .red
        case .suspend: .orange
        case .markRedundant: .blue
        case .markSuspicious: .yellow
        }
    }

    // MARK: - Condition Pill Text

    private func conditionPillText(_ condition: RuleCondition) -> String {
        switch condition.type {
        case .cpuIdleGreaterThan:
            if let seconds = TimeInterval(condition.value) {
                return "idle > \(formatDuration(seconds))"
            }
            return "idle > \(condition.value)"
        case .memoryGreaterThan:
            if let bytes = UInt64(condition.value) {
                return "mem > \(formatBytes(bytes))"
            }
            return "mem > \(condition.value)"
        default:
            return condition.type.displayName
        }
    }
}
