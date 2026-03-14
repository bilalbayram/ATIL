import SwiftUI

/// Form-based rule builder for creating auto-action rules.
struct RuleBuilderView: View {
    @Binding var rule: AutoRule
    let onSave: (AutoRule) -> Void
    let onCancel: () -> Void

    @State private var conditions: [RuleCondition] = []

    var body: some View {
        Form {
            Section("Rule Name") {
                TextField("Name", text: $rule.name)
            }

            Section("Match Process") {
                Picker("Match by", selection: $rule.matcherType) {
                    ForEach(AutoRule.MatcherType.allCases, id: \.self) { type in
                        Text(type.rawValue.capitalized).tag(type)
                    }
                }
                TextField("Value", text: $rule.matcherValue)
                    .font(.body.monospaced())
            }

            Section("Conditions") {
                ForEach(conditions.indices, id: \.self) { index in
                    HStack {
                        Picker("", selection: $conditions[index].type) {
                            ForEach(RuleCondition.ConditionType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .frame(width: 140)

                        if conditions[index].type.needsValue {
                            TextField("Value", text: $conditions[index].value)
                                .frame(width: 100)
                        }

                        Button(role: .destructive) {
                            conditions.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    conditions.append(RuleCondition(type: .cpuIdleGreaterThan, value: "300"))
                } label: {
                    Label("Add Condition", systemImage: "plus")
                }
            }

            Section("Context (Optional)") {
                TextField("App Bundle ID (e.g. com.spotify.client)", text: Binding(
                    get: { rule.contextAppBundleId ?? "" },
                    set: { rule.contextAppBundleId = $0.isEmpty ? nil : $0 }
                ))

                if rule.contextAppBundleId != nil {
                    Picker("App must be", selection: Binding(
                        get: { rule.contextAppMustBeRunning ?? false },
                        set: { rule.contextAppMustBeRunning = $0 }
                    )) {
                        Text("Not Running").tag(false)
                        Text("Running").tag(true)
                    }
                }
            }

            Section("Action") {
                Picker("When matched", selection: $rule.action) {
                    ForEach(AutoRule.RuleAction.allCases, id: \.self) { action in
                        Text(action.displayName).tag(action)
                    }
                }

                Stepper("Cooldown: \(rule.cooldownSeconds / 60) min", value: $rule.cooldownSeconds, in: 60...3600, step: 60)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    rule.conditions = conditions
                    onSave(rule)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 450, minHeight: 400)
        .onAppear {
            conditions = rule.conditions
        }
    }
}
