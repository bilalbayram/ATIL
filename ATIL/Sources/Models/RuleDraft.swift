import Foundation

struct RuleDraft: Sendable {
    enum SocketRequirement: String, CaseIterable, Identifiable, Sendable {
        case any
        case hasSockets
        case noSockets

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .any: "Any"
            case .hasSockets: "Has Sockets"
            case .noSockets: "No Sockets"
            }
        }
    }

    enum AppOwnershipRequirement: String, CaseIterable, Identifiable, Sendable {
        case any
        case hasOwningApp
        case noOwningApp

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .any: "Any"
            case .hasOwningApp: "Has Owning App"
            case .noOwningApp: "No Owning App"
            }
        }
    }

    enum ContextMode: String, CaseIterable, Identifiable, Sendable {
        case none
        case appRunning
        case appNotRunning

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .none: "No App Context"
            case .appRunning: "Only While App Is Running"
            case .appNotRunning: "Only While App Is Closed"
            }
        }
    }

    enum Template: String, CaseIterable, Identifiable, Sendable {
        case idleCleanup
        case memoryPressure
        case appClosedCleanup
        case orphanWatch

        var id: String { rawValue }

        var title: String {
            switch self {
            case .idleCleanup: "Idle Cleanup"
            case .memoryPressure: "Memory Pressure"
            case .appClosedCleanup: "After App Closes"
            case .orphanWatch: "Orphan Watch"
            }
        }

        var subtitle: String {
            switch self {
            case .idleCleanup:
                "Kill idle background helpers with no sockets or owning app."
            case .memoryPressure:
                "Suspend heavy processes once they cross a memory threshold."
            case .appClosedCleanup:
                "Clean up leftover helpers when the parent app is no longer running."
            case .orphanWatch:
                "Mark orphaned headless processes as suspicious for review."
            }
        }

        var symbolName: String {
            switch self {
            case .idleCleanup: "moon.zzz.fill"
            case .memoryPressure: "memorychip.fill"
            case .appClosedCleanup: "app.badge.checkmark"
            case .orphanWatch: "eye.trianglebadge.exclamationmark"
            }
        }
    }

    var id: Int64?
    var name: String = ""
    var matcherType: AutoRule.MatcherType = .name
    var matcherValue: String = ""
    var action: AutoRule.RuleAction = .kill
    var cooldownMinutes: Int = 10
    var enabled = true
    var createdAt = Date()

    var idleMinutes: Int? = nil
    var memoryMB: Int? = nil
    var requiresOrphaned = false
    var requiresZombie = false
    var requiresNoTTY = false
    var socketRequirement: SocketRequirement = .any
    var appOwnershipRequirement: AppOwnershipRequirement = .any

    var contextMode: ContextMode = .none
    var contextAppBundleId = ""

    init() {}

    init(rule: AutoRule) {
        id = rule.id
        name = rule.name
        matcherType = rule.matcherType
        matcherValue = rule.matcherValue
        action = rule.action
        cooldownMinutes = max(1, rule.cooldownSeconds / 60)
        enabled = rule.enabled
        createdAt = rule.createdAt

        switch (rule.contextAppBundleId, rule.contextAppMustBeRunning) {
        case let (.some(bundleId), .some(true)):
            contextMode = .appRunning
            contextAppBundleId = bundleId
        case let (.some(bundleId), .some(false)):
            contextMode = .appNotRunning
            contextAppBundleId = bundleId
        default:
            contextMode = .none
            contextAppBundleId = rule.contextAppBundleId ?? ""
        }

        for condition in rule.conditions {
            switch condition.type {
            case .cpuIdleGreaterThan:
                if let seconds = TimeInterval(condition.value), seconds > 0 {
                    idleMinutes = max(1, Int(seconds / 60))
                }

            case .memoryGreaterThan:
                if let bytes = UInt64(condition.value), bytes > 0 {
                    memoryMB = max(1, Int(bytes / 1_048_576))
                }

            case .isOrphaned:
                requiresOrphaned = true

            case .isZombie:
                requiresZombie = true

            case .noTTY:
                requiresNoTTY = true

            case .hasSockets:
                socketRequirement = .hasSockets

            case .noSockets:
                socketRequirement = .noSockets

            case .hasOwningApp:
                appOwnershipRequirement = .hasOwningApp

            case .noOwningApp:
                appOwnershipRequirement = .noOwningApp
            }
        }
    }

    var isValid: Bool {
        !matcherValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var suggestedName: String {
        buildRule(named: "Untitled Rule").suggestedName
    }

    var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? suggestedName : trimmed
    }

    var summarySentence: String {
        provisionalRule.summarySentence
    }

    var provisionalRule: AutoRule {
        buildRule(named: resolvedName)
    }

    func buildRule() -> AutoRule {
        buildRule(named: resolvedName)
    }

    mutating func apply(template: Template, selectedProcess: ATILProcess? = nil) {
        if matcherValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let selectedProcess {
            applyTarget(from: selectedProcess)
        }

        switch template {
        case .idleCleanup:
            action = .kill
            idleMinutes = 5
            memoryMB = nil
            requiresOrphaned = false
            requiresZombie = false
            requiresNoTTY = false
            socketRequirement = .noSockets
            appOwnershipRequirement = .noOwningApp
            cooldownMinutes = 10
            contextMode = .none

        case .memoryPressure:
            action = .suspend
            idleMinutes = nil
            memoryMB = 512
            requiresOrphaned = false
            requiresZombie = false
            requiresNoTTY = false
            socketRequirement = .any
            appOwnershipRequirement = .any
            cooldownMinutes = 15
            contextMode = .none

        case .appClosedCleanup:
            action = .kill
            idleMinutes = 5
            memoryMB = nil
            requiresOrphaned = false
            requiresZombie = false
            requiresNoTTY = false
            socketRequirement = .noSockets
            appOwnershipRequirement = .any
            cooldownMinutes = 10
            if let bundleId = selectedProcess?.owningAppBundleIdentifier ?? selectedProcess?.bundleIdentifier,
               !bundleId.isEmpty {
                contextMode = .appNotRunning
                contextAppBundleId = bundleId
            }

        case .orphanWatch:
            action = .markSuspicious
            idleMinutes = 5
            memoryMB = nil
            requiresOrphaned = true
            requiresZombie = false
            requiresNoTTY = true
            socketRequirement = .noSockets
            appOwnershipRequirement = .noOwningApp
            cooldownMinutes = 10
            contextMode = .none
        }
    }

    mutating func applyTarget(from process: ATILProcess) {
        if let launchdLabel = process.launchdJob?.label {
            matcherType = .launchdLabel
            matcherValue = launchdLabel
        } else if let bundleId = process.bundleIdentifier {
            matcherType = .bundleId
            matcherValue = bundleId
        } else if let executablePath = process.executablePath {
            matcherType = .path
            matcherValue = executablePath
        } else {
            matcherType = .name
            matcherValue = process.name
        }
    }

    private func buildRule(named ruleName: String) -> AutoRule {
        var conditions: [RuleCondition] = []

        if let idleMinutes, idleMinutes > 0 {
            conditions.append(
                RuleCondition(
                    type: .cpuIdleGreaterThan,
                    value: String(idleMinutes * 60)
                )
            )
        }

        if let memoryMB, memoryMB > 0 {
            conditions.append(
                RuleCondition(
                    type: .memoryGreaterThan,
                    value: String(memoryMB * 1_048_576)
                )
            )
        }

        if requiresOrphaned {
            conditions.append(RuleCondition(type: .isOrphaned, value: "true"))
        }
        if requiresZombie {
            conditions.append(RuleCondition(type: .isZombie, value: "true"))
        }
        if requiresNoTTY {
            conditions.append(RuleCondition(type: .noTTY, value: "true"))
        }

        switch socketRequirement {
        case .any:
            break
        case .hasSockets:
            conditions.append(RuleCondition(type: .hasSockets, value: "true"))
        case .noSockets:
            conditions.append(RuleCondition(type: .noSockets, value: "true"))
        }

        switch appOwnershipRequirement {
        case .any:
            break
        case .hasOwningApp:
            conditions.append(RuleCondition(type: .hasOwningApp, value: "true"))
        case .noOwningApp:
            conditions.append(RuleCondition(type: .noOwningApp, value: "true"))
        }

        let trimmedContextBundleId = contextAppBundleId.trimmingCharacters(in: .whitespacesAndNewlines)

        var rule = AutoRule(
            id: id,
            name: ruleName,
            matcherType: matcherType,
            matcherValue: matcherValue.trimmingCharacters(in: .whitespacesAndNewlines),
            conditionJSON: "[]",
            contextAppBundleId: contextMode == .none || trimmedContextBundleId.isEmpty ? nil : trimmedContextBundleId,
            contextAppMustBeRunning: contextMode == .none ? nil : contextMode == .appRunning,
            action: action,
            cooldownSeconds: max(1, cooldownMinutes) * 60,
            enabled: enabled,
            createdAt: createdAt
        )
        rule.conditions = conditions
        return rule
    }
}
