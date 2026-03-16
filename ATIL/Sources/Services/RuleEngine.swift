import AppKit
import Foundation

/// Evaluates auto-action rules against the current process snapshot.
@MainActor
final class RuleEngine {
    private let ruleRepo = RuleRepository(db: DatabaseManager.shared)
    private let actionService = ProcessActionService()
    private let safetyGate = SafetyGate.shared

    struct RuleResult {
        let rule: AutoRule
        let process: ATILProcess
        let actionTaken: String
    }

    func categoryOverrides(for processes: [ATILProcess]) -> [ProcessIdentity: ProcessCategory] {
        guard let rules = try? ruleRepo.enabledRules(), !rules.isEmpty else {
            return [:]
        }

        let runningApps = runningAppSet()
        var overrides: [ProcessIdentity: ProcessCategory] = [:]

        for rule in rules where rule.action == .markRedundant || rule.action == .markSuspicious {
            for process in processes {
                guard shouldEvaluate(rule: rule, process: process, runningApps: runningApps) else {
                    continue
                }

                let proposedCategory: ProcessCategory = rule.action == .markRedundant ? .redundant : .suspicious
                let current = overrides[process.identity] ?? .healthy
                if proposedCategory < current {
                    overrides[process.identity] = proposedCategory
                }
            }
        }

        return overrides
    }

    /// Evaluate all enabled rules against the process list.
    /// Returns results for actions that were taken.
    func evaluate(processes: [ATILProcess]) async -> [RuleResult] {
        guard let rules = try? ruleRepo.enabledRules(), !rules.isEmpty else {
            return []
        }

        let runningApps = runningAppSet()

        var results: [RuleResult] = []

        for rule in rules where rule.action == .kill || rule.action == .suspend {
            guard let ruleId = rule.id else { continue }

            for process in processes {
                guard shouldEvaluate(rule: rule, process: process, runningApps: runningApps) else {
                    continue
                }

                // Cooldown check
                let processId = "\(process.pid):\(process.startTime.timeIntervalSince1970)"
                if let inCooldown = try? ruleRepo.isInCooldown(
                    ruleId: ruleId,
                    processIdentity: processId,
                    cooldownSeconds: rule.cooldownSeconds
                ), inCooldown {
                    continue
                }

                // Execute action
                let actionTaken: String
                switch rule.action {
                case .kill:
                    guard process.isUserOwned else { continue }
                    let _ = try? await actionService.kill(process: process)
                    actionTaken = "kill"

                case .suspend:
                    guard process.isUserOwned else { continue }
                    let _ = try? actionService.suspend(process: process)
                    actionTaken = "suspend"

                case .markRedundant:
                    continue

                case .markSuspicious:
                    continue
                }

                // Record event
                try? ruleRepo.recordEvent(
                    ruleId: ruleId,
                    processIdentity: processId,
                    action: actionTaken
                )

                results.append(RuleResult(rule: rule, process: process, actionTaken: actionTaken))
            }
        }

        return results
    }

    /// Create a rule pre-filled from a process (for "Create rule from action" flow).
    func createRuleFromProcess(_ process: ATILProcess, action: AutoRule.RuleAction) -> AutoRule {
        let matcherType: AutoRule.MatcherType
        let matcherValue: String

        if let launchdLabel = process.launchdJob?.label {
            matcherType = .launchdLabel
            matcherValue = launchdLabel
        } else if let bundleId = process.bundleIdentifier {
            matcherType = .bundleId
            matcherValue = bundleId
        } else if let path = process.executablePath {
            matcherType = .path
            matcherValue = path
        } else {
            matcherType = .name
            matcherValue = process.name
        }

        var conditions: [RuleCondition] = []
        if process.isOrphaned {
            conditions.append(RuleCondition(type: .isOrphaned, value: "true"))
        }
        if !process.hasOwningApp {
            conditions.append(RuleCondition(type: .noOwningApp, value: "true"))
        }
        if !process.hasSockets {
            conditions.append(RuleCondition(type: .noSockets, value: "true"))
        }
        // Default: idle > 5 minutes
        conditions.append(RuleCondition(type: .cpuIdleGreaterThan, value: "300"))

        var rule = AutoRule(
            name: "Auto \(action.rawValue): \(process.name)",
            matcherType: matcherType,
            matcherValue: matcherValue,
            conditionJSON: "[]",
            contextAppBundleId: nil,
            contextAppMustBeRunning: nil,
            action: action,
            cooldownSeconds: 600,
            enabled: true,
            createdAt: Date()
        )
        rule.conditions = conditions
        return rule
    }

    func previewMatches(for rule: AutoRule, in processes: [ATILProcess]) -> [ATILProcess] {
        let runningApps = runningAppSet()
        return processes.filter { process in
            shouldEvaluate(rule: rule, process: process, runningApps: runningApps)
        }
    }

    private func runningAppSet() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    private func shouldEvaluate(
        rule: AutoRule,
        process: ATILProcess,
        runningApps: Set<String>
    ) -> Bool {
        if safetyGate.isProtected(process) || safetyGate.isIgnored(process) {
            return false
        }

        guard rule.matches(process), rule.conditionsMet(for: process) else {
            return false
        }

        if let contextApp = rule.contextAppBundleId {
            let isRunning = runningApps.contains(contextApp)
            if let mustBeRunning = rule.contextAppMustBeRunning {
                if mustBeRunning && !isRunning { return false }
                if !mustBeRunning && isRunning { return false }
            }
        }

        return true
    }
}
