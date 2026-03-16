import AppKit
import SwiftUI

/// Intent-first rule builder that keeps the UI simple while compiling down to AutoRule.
struct RuleBuilderView: View {
    @Environment(ProcessListViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let initialRule: AutoRule
    let onSave: (AutoRule) -> Void
    let onCancel: () -> Void

    @State private var draft: RuleDraft

    init(
        initialRule: AutoRule,
        onSave: @escaping (AutoRule) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialRule = initialRule
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: RuleDraft(rule: initialRule))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryCard
                    templatesCard
                    targetCard
                    conditionsCard
                    actionCard
                    contextCard
                    previewCard
                }
                .padding(20)
            }

            Divider()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if let validationMessage {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Rule name: \(draft.resolvedName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button("Save Rule") {
                    onSave(draft.buildRule())
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.isValid)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .frame(minWidth: 720, minHeight: 760)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(initialRule.id == nil ? "New Auto-Action Rule" : "Edit Auto-Action Rule")
                        .font(.headline)
                    Text("Build rules around intent, not matcher syntax.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                RuleInfoChip(
                    label: draft.enabled ? "starts active" : "starts paused",
                    color: draft.enabled ? .green : .secondary
                )
            }

            Text(draft.summarySentence)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 6) {
                RuleInfoChip(
                    label: draft.isValid
                        ? "\(previewMatches.count) matches now"
                        : "choose a target",
                    color: draft.isValid
                        ? (previewMatches.isEmpty ? .secondary : .green)
                        : .orange
                )
                RuleInfoChip(
                    label: "cooldown \(formatDuration(TimeInterval(draft.cooldownMinutes * 60)))",
                    color: .secondary
                )
                RuleInfoChip(
                    label: draft.action.displayName.lowercased(),
                    color: draft.action.tintColor
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(draft.action.tintColor.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(draft.action.tintColor.opacity(0.18))
        )
    }

    private var templatesCard: some View {
        RuleEditorCard(
            title: "Start From A Template",
            subtitle: "These presets set practical defaults. They do not lock you in."
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                ForEach(RuleDraft.Template.allCases) { template in
                    Button {
                        withAnimation(ATILAnimation.subtle(reduceMotion: reduceMotion)) {
                            draft.apply(template: template, selectedProcess: viewModel.selectedProcess)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: template.symbolName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)

                            Text(template.title)
                                .font(.subheadline.weight(.semibold))

                            Text(template.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                    }
                    .buttonStyle(TemplateButtonStyle())
                }
            }
        }
    }

    private var targetCard: some View {
        RuleEditorCard(
            title: "1. Choose The Target",
            subtitle: "Pick something live, or type a matcher manually when you need precision."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Optional label", text: $draft.name, prompt: Text(draft.suggestedName))

                Picker("Match by", selection: $draft.matcherType) {
                    ForEach(AutoRule.MatcherType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }

                HStack(spacing: 10) {
                    if let selectedProcess = viewModel.selectedProcess {
                        Button("Use Selected Process") {
                            withAnimation(ATILAnimation.subtle(reduceMotion: reduceMotion)) {
                                draft.applyTarget(from: selectedProcess)
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    if !suggestedOptions.isEmpty {
                        Menu(currentSuggestionMenuTitle) {
                            ForEach(suggestedOptions) { option in
                                Button {
                                    withAnimation(ATILAnimation.subtle(reduceMotion: reduceMotion)) {
                                        draft.matcherType = option.matcherType
                                        draft.matcherValue = option.matcherValue
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(option.title)
                                        if let subtitle = option.subtitle {
                                            Text(subtitle)
                                                .font(.caption)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                TextField(targetFieldTitle, text: $draft.matcherValue, prompt: Text(targetPlaceholder))
                    .font(targetFieldNeedsMonospace ? .body.monospaced() : .body)

                Text(targetHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var conditionsCard: some View {
        RuleEditorCard(
            title: "2. Decide When It Should Fire",
            subtitle: "Most rules need one or two constraints, not a long chain of raw conditions."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Only after the process has been idle", isOn: idleEnabledBinding)

                    if draft.idleMinutes != nil {
                        Stepper(
                            "Idle threshold: \(formatDuration(TimeInterval(idleMinutes * 60)))",
                            value: idleMinutesBinding,
                            in: 1...720
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Only above a memory threshold", isOn: memoryEnabledBinding)

                    if draft.memoryMB != nil {
                        Stepper(
                            "Memory threshold: \(formatBytes(UInt64(memoryMB) * 1_048_576))",
                            value: memoryMBBinding,
                            in: 32...32768,
                            step: 32
                        )
                    }
                }

                Divider()

                Picker("Sockets", selection: $draft.socketRequirement) {
                    ForEach(RuleDraft.SocketRequirement.allCases) { requirement in
                        Text(requirement.displayName).tag(requirement)
                    }
                }

                Picker("Owning App", selection: $draft.appOwnershipRequirement) {
                    ForEach(RuleDraft.AppOwnershipRequirement.allCases) { requirement in
                        Text(requirement.displayName).tag(requirement)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    Toggle("Must be orphaned", isOn: $draft.requiresOrphaned)
                    Toggle("Must be zombie", isOn: $draft.requiresZombie)
                    Toggle("Must have no terminal", isOn: $draft.requiresNoTTY)
                }

                if !draft.provisionalRule.conditions.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(draft.provisionalRule.conditions.enumerated()), id: \.offset) { _, condition in
                            StatusBadgeView(text: condition.badgeText, color: .secondary)
                        }
                    }
                }
            }
        }
    }

    private var actionCard: some View {
        RuleEditorCard(
            title: "3. Pick The Action",
            subtitle: "Kill and suspend act immediately. The mark actions only affect classification."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(AutoRule.RuleAction.allCases, id: \.self) { action in
                        Button {
                            withAnimation(ATILAnimation.subtle(reduceMotion: reduceMotion)) {
                                draft.action = action
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: action.symbolName)
                                    .foregroundStyle(action.tintColor)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(action.displayName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(actionDetail(for: action))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .padding(12)
                        }
                        .buttonStyle(ActionChoiceButtonStyle(isSelected: draft.action == action, color: action.tintColor))
                    }
                }

                Stepper(
                    "Cooldown: \(formatDuration(TimeInterval(draft.cooldownMinutes * 60)))",
                    value: $draft.cooldownMinutes,
                    in: 1...120
                )

                Toggle("Start this rule active", isOn: $draft.enabled)
            }
        }
    }

    private var contextCard: some View {
        RuleEditorCard(
            title: "4. Optional App Context",
            subtitle: "Useful when a helper should only be cleaned up after a parent app closes."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("App context", selection: $draft.contextMode) {
                    ForEach(RuleDraft.ContextMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                if draft.contextMode != .none {
                    HStack(spacing: 10) {
                        if !appOptions.isEmpty {
                            Menu("Choose Current App") {
                                ForEach(appOptions) { app in
                                    Button {
                                        draft.contextAppBundleId = app.bundleId
                                    } label: {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(app.title)
                                            Text(app.bundleId)
                                                .font(.caption)
                                        }
                                    }
                                }
                            }
                        }

                        TextField("App bundle ID", text: $draft.contextAppBundleId, prompt: Text("com.spotify.client"))
                            .font(.body.monospaced())
                    }

                    Text(contextHelpText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var previewCard: some View {
        RuleEditorCard(
            title: "Live Preview",
            subtitle: "Preview uses the current process snapshot and the same evaluation logic as the rule engine."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if !draft.isValid {
                    Text("Choose a target to see live matches.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if previewMatches.isEmpty {
                    Text("Nothing matches the current snapshot.")
                        .font(.subheadline.weight(.semibold))
                    Text("You can still save the rule. It will activate whenever a future process matches.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text("\(previewMatches.count) process\(previewMatches.count == 1 ? "" : "es") match right now")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }

                    ForEach(previewMatches.prefix(5)) { process in
                        PreviewProcessRow(process: process)
                    }

                    if previewMatches.count > 5 {
                        Text("... and \(previewMatches.count - 5) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var previewMatches: [ATILProcess] {
        guard draft.isValid else { return [] }
        return viewModel.monitor.ruleEngine.previewMatches(
            for: draft.provisionalRule,
            in: viewModel.monitor.snapshot
        )
    }

    private var appOptions: [RuleAppOption] {
        var options: [String: RuleAppOption] = [:]

        for app in NSWorkspace.shared.runningApplications {
            guard let bundleId = app.bundleIdentifier else { continue }
            let title = app.localizedName ?? bundleId
            options[bundleId] = RuleAppOption(bundleId: bundleId, title: title)
        }

        for process in viewModel.monitor.snapshot {
            guard let bundleId = process.bundleIdentifier else { continue }
            if options[bundleId] == nil {
                options[bundleId] = RuleAppOption(bundleId: bundleId, title: process.name)
            }
        }

        return options.values.sorted { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private var processNameOptions: [RuleMatchOption] {
        let grouped = Dictionary(grouping: viewModel.monitor.snapshot, by: \.name)
        return grouped.map { name, processes in
            RuleMatchOption(
                matcherType: .name,
                matcherValue: name,
                title: name,
                subtitle: "\(processes.count) live match\(processes.count == 1 ? "" : "es")"
            )
        }
        .sorted(by: optionSort)
    }

    private var pathOptions: [RuleMatchOption] {
        var uniqueProcessesByPath: [String: ATILProcess] = [:]
        for process in viewModel.monitor.snapshot {
            guard let path = process.executablePath,
                  uniqueProcessesByPath[path] == nil
            else {
                continue
            }
            uniqueProcessesByPath[path] = process
        }

        return uniqueProcessesByPath.map { path, process in
            RuleMatchOption(
                matcherType: .path,
                matcherValue: path,
                title: process.name,
                subtitle: path
            )
        }
        .sorted(by: optionSort)
    }

    private var launchdOptions: [RuleMatchOption] {
        var uniqueProcessesByLabel: [String: ATILProcess] = [:]
        for process in viewModel.monitor.snapshot {
            guard let label = process.launchdJob?.label,
                  uniqueProcessesByLabel[label] == nil
            else {
                continue
            }
            uniqueProcessesByLabel[label] = process
        }

        return uniqueProcessesByLabel.map { label, process in
            RuleMatchOption(
                matcherType: .launchdLabel,
                matcherValue: label,
                title: label,
                subtitle: process.name
            )
        }
        .sorted(by: optionSort)
    }

    private var suggestedOptions: [RuleMatchOption] {
        switch draft.matcherType {
        case .name:
            return processNameOptions
        case .path:
            return pathOptions
        case .bundleId:
            return appOptions.map { app in
                RuleMatchOption(
                    matcherType: .bundleId,
                    matcherValue: app.bundleId,
                    title: app.title,
                    subtitle: app.bundleId
                )
            }
        case .launchdLabel:
            return launchdOptions
        case .regex:
            return []
        }
    }

    private var currentSuggestionMenuTitle: String {
        switch draft.matcherType {
        case .name:
            "Use Current Process Name"
        case .path:
            "Use Current Executable"
        case .bundleId:
            "Use Current App"
        case .launchdLabel:
            "Use Launchd Job"
        case .regex:
            "Suggestions Unavailable"
        }
    }

    private var targetFieldTitle: String {
        switch draft.matcherType {
        case .name:
            "Process name"
        case .path:
            "Executable path"
        case .bundleId:
            "App bundle ID"
        case .launchdLabel:
            "Launchd label"
        case .regex:
            "Regex pattern"
        }
    }

    private var targetPlaceholder: String {
        switch draft.matcherType {
        case .name:
            "Spotify Helper"
        case .path:
            "/usr/libexec/rapportd"
        case .bundleId:
            "com.spotify.client"
        case .launchdLabel:
            "com.apple.bird"
        case .regex:
            ".*Helper.*"
        }
    }

    private var targetHelpText: String {
        switch draft.matcherType {
        case .name:
            "Exact process-name match. Best for one-off helpers with stable names."
        case .path:
            "Exact executable path. Best when multiple processes share the same display name."
        case .bundleId:
            "Targets every process owned by the chosen app bundle."
        case .launchdLabel:
            "Useful for agents and daemons that respawn under launchd."
        case .regex:
            "Advanced mode. Regex is matched against process names only."
        }
    }

    private var targetFieldNeedsMonospace: Bool {
        switch draft.matcherType {
        case .name:
            false
        case .path, .bundleId, .launchdLabel, .regex:
            true
        }
    }

    private var contextHelpText: String {
        switch draft.contextMode {
        case .none:
            ""
        case .appRunning:
            "The rule will only fire while this app is running."
        case .appNotRunning:
            "The rule will only fire after this app has closed."
        }
    }

    private var validationMessage: String? {
        if draft.matcherValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Choose a target or enter a matcher value."
        }
        return nil
    }

    private var idleEnabledBinding: Binding<Bool> {
        Binding(
            get: { draft.idleMinutes != nil },
            set: { enabled in
                draft.idleMinutes = enabled ? max(draft.idleMinutes ?? 5, 1) : nil
            }
        )
    }

    private var memoryEnabledBinding: Binding<Bool> {
        Binding(
            get: { draft.memoryMB != nil },
            set: { enabled in
                draft.memoryMB = enabled ? max(draft.memoryMB ?? 512, 32) : nil
            }
        )
    }

    private var idleMinutesBinding: Binding<Int> {
        Binding(
            get: { max(draft.idleMinutes ?? 5, 1) },
            set: { draft.idleMinutes = max($0, 1) }
        )
    }

    private var memoryMBBinding: Binding<Int> {
        Binding(
            get: { max(draft.memoryMB ?? 512, 32) },
            set: { draft.memoryMB = max($0, 32) }
        )
    }

    private var idleMinutes: Int {
        max(draft.idleMinutes ?? 5, 1)
    }

    private var memoryMB: Int {
        max(draft.memoryMB ?? 512, 32)
    }

    private func actionDetail(for action: AutoRule.RuleAction) -> String {
        switch action {
        case .kill:
            "Terminate matching processes."
        case .suspend:
            "Freeze them without killing."
        case .markRedundant:
            "Change classification to redundant."
        case .markSuspicious:
            "Change classification to suspicious."
        }
    }

    private func optionSort(lhs: RuleMatchOption, rhs: RuleMatchOption) -> Bool {
        lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

private struct RuleEditorCard<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            content
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07))
        )
    }
}

private struct RuleInfoChip: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(color)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct PreviewProcessRow: View {
    let process: ATILProcess

    var body: some View {
        HStack(spacing: 10) {
            ProcessIconView(process: process)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(process.name)
                    .font(.subheadline.weight(.medium))
                Text(process.executablePath ?? formatPID(process.pid))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            FlowLayout(spacing: 4) {
                if let idleSince = process.idleSince {
                    StatusBadgeView(
                        text: "idle \(formatDuration(Date().timeIntervalSince(idleSince)))",
                        color: .yellow
                    )
                }
                StatusBadgeView(text: formatBytes(process.residentMemory), color: .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct RuleAppOption: Identifiable, Hashable {
    let bundleId: String
    let title: String

    var id: String { bundleId }
}

private struct RuleMatchOption: Identifiable, Hashable {
    let matcherType: AutoRule.MatcherType
    let matcherValue: String
    let title: String
    let subtitle: String?

    var id: String { "\(matcherType.rawValue):\(matcherValue)" }
}

private struct TemplateButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.09 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.08))
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(ATILAnimation.quick, value: configuration.isPressed)
    }
}

private struct ActionChoiceButtonStyle: ButtonStyle {
    let isSelected: Bool
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill((isSelected ? color.opacity(0.12) : Color.primary.opacity(0.04)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? color.opacity(0.35) : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.2 : 1
                    )
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(ATILAnimation.quick, value: configuration.isPressed)
    }
}
