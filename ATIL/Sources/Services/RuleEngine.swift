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

    /// Evaluate all enabled rules against the process list.
    /// Returns results for actions that were taken.
    func evaluate(processes: [ATILProcess]) async -> [RuleResult] {
        guard let rules = try? ruleRepo.enabledRules(), !rules.isEmpty else {
            return []
        }

        // Build running app set for context checks
        let runningApps = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )

        var results: [RuleResult] = []

        for rule in rules {
            guard let ruleId = rule.id else { continue }

            for process in processes {
                // Safety gate check
                if safetyGate.isProtected(process) || safetyGate.isIgnored(process) {
                    continue
                }

                // Match check
                guard rule.matches(process) else { continue }

                // Conditions check
                guard rule.conditionsMet(for: process) else { continue }

                // Context check (another app must/must not be running)
                if let contextApp = rule.contextAppBundleId {
                    let isRunning = runningApps.contains(contextApp)
                    if let mustBeRunning = rule.contextAppMustBeRunning {
                        if mustBeRunning && !isRunning { continue }
                        if !mustBeRunning && isRunning { continue }
                    }
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
                    // This is handled in classification, not as an action
                    actionTaken = "markRedundant"
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

        if let bundleId = process.bundleIdentifier {
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
        if !process.hasTTY {
            conditions.append(RuleCondition(type: .noTTY, value: "true"))
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
}
