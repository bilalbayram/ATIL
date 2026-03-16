import SwiftUI

/// Form-based rule builder for creating and editing auto-action rules.
struct RuleBuilderView: View {
    @Binding var rule: AutoRule
    let onSave: (AutoRule) -> Void
    let onCancel: () -> Void

    @State private var conditions: [RuleCondition] = []

    var body: some View {
        VStack(spacing: 0) {
            Form {
                // MARK: - Rule Name
                Section("Rule Name") {
                    TextField("e.g. Kill idle Spotify helpers", text: $rule.name)
                }

                // MARK: - Match Process
                Section("Match Process") {
                    Picker("Match by", selection: $rule.matcherType) {
                        ForEach(AutoRule.MatcherType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    TextField("Value", text: $rule.matcherValue)
                        .font(.body.monospaced())
                    Text(matcherHint)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // MARK: - Conditions
                Section("Conditions") {
                    ForEach(conditions.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Picker("Condition", selection: $conditions[index].type) {
                                    ForEach(RuleCondition.ConditionType.allCases, id: \.self) { type in
                                        Text(type.displayName).tag(type)
                                    }
                                }
                                .labelsHidden()

                                Spacer()

                                Button(role: .destructive) {
                                    conditions.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(PlainPressableButtonStyle())
                            }

                            if conditions[index].type.needsValue {
                                HStack(spacing: 8) {
                                    TextField(
                                        conditionPlaceholder(conditions[index].type),
                                        text: $conditions[index].value
                                    )
                                    .textFieldStyle(.roundedBorder)

                                    Text(conditionUnitLabel(conditions[index].type))
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }

                                // Live conversion hint
                                if let hint = conditionConversionHint(conditions[index]) {
                                    Text("= \(hint)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Button {
                        conditions.append(RuleCondition(type: .cpuIdleGreaterThan, value: "300"))
                    } label: {
                        Label("Add Condition", systemImage: "plus")
                    }
                }

                // MARK: - Action
                Section("Action") {
                    Picker("When matched", selection: $rule.action) {
                        ForEach(AutoRule.RuleAction.allCases, id: \.self) { action in
                            Text(action.displayName).tag(action)
                        }
                    }

                    Stepper("Cooldown: \(rule.cooldownSeconds / 60) min", value: $rule.cooldownSeconds, in: 60...3600, step: 60)

                    Text("Minimum time between repeated actions on the same process")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // MARK: - Context
                Section {
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
                } header: {
                    Text("Context (Optional)")
                } footer: {
                    Text("Restrict this rule to fire only when a specific app is running or not.")
                }
            }
            .formStyle(.grouped)

            // MARK: - Footer bar
            Divider()

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Rule") {
                    rule.conditions = conditions
                    onSave(rule)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(rule.name.isEmpty || rule.matcherValue.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .frame(minWidth: 500, minHeight: 450)
        .onAppear {
            conditions = rule.conditions
        }
    }

    // MARK: - Matcher Hints

    private var matcherHint: String {
        switch rule.matcherType {
        case .name: "Exact process name match"
        case .path: "Full path, e.g. /usr/libexec/rapportd"
        case .bundleId: "e.g. com.spotify.client"
        case .launchdLabel: "e.g. com.apple.bird"
        case .regex: "Matched against process name"
        }
    }

    // MARK: - Condition Helpers

    private func conditionPlaceholder(_ type: RuleCondition.ConditionType) -> String {
        switch type {
        case .cpuIdleGreaterThan: "300"
        case .memoryGreaterThan: "104857600"
        default: ""
        }
    }

    private func conditionUnitLabel(_ type: RuleCondition.ConditionType) -> String {
        switch type {
        case .cpuIdleGreaterThan: "seconds"
        case .memoryGreaterThan: "bytes"
        default: ""
        }
    }

    private func conditionConversionHint(_ condition: RuleCondition) -> String? {
        switch condition.type {
        case .cpuIdleGreaterThan:
            guard let seconds = TimeInterval(condition.value), seconds > 0 else { return nil }
            return formatDuration(seconds)
        case .memoryGreaterThan:
            guard let bytes = UInt64(condition.value), bytes > 0 else { return nil }
            return formatBytes(bytes)
        default:
            return nil
        }
    }
}
