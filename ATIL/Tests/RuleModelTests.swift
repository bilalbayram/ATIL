import Darwin
import Foundation
import Testing
@testable import ATIL

struct RuleModelTests {
    private func makeProcess(
        hasSockets: Bool,
        hasOwningApp: Bool = false
    ) -> ATILProcess {
        ATILProcess(
            identity: ProcessIdentity(pid: 777, startTime: Date()),
            pid: 777,
            ppid: 1,
            uid: getuid(),
            gid: getgid(),
            name: "python3",
            executablePath: "/usr/local/bin/python3",
            startTime: Date(),
            residentMemory: 1_000_000,
            virtualMemory: 2_000_000,
            cpuTimeUser: 0,
            cpuTimeSystem: 0,
            cpuPercent: 0,
            threadCount: 1,
            niceValue: 0,
            processState: .running,
            isOrphaned: false,
            parentAlive: true,
            hasTTY: false,
            hasSockets: hasSockets,
            hasOwningApp: hasOwningApp,
            bundleIdentifier: nil,
            bundlePath: nil,
            owningAppBundleIdentifier: nil,
            owningAppBundlePath: nil,
            category: .healthy,
            classificationReasons: [],
            lastSeen: Date(),
            idleSince: nil,
            launchdJob: nil,
            appIcon: nil
        )
    }

    @Test func noSocketsConditionReflectsProcessState() {
        let condition = RuleCondition(type: .noSockets, value: "true")

        #expect(condition.isMet(for: makeProcess(hasSockets: false)))
        #expect(!condition.isMet(for: makeProcess(hasSockets: true)))
    }

    @Test func launchdLabelMatcherUsesResolvedJobLabel() {
        let process = ATILProcess(
            identity: ProcessIdentity(pid: 888, startTime: Date()),
            pid: 888,
            ppid: 1,
            uid: getuid(),
            gid: getgid(),
            name: "agent",
            executablePath: "/usr/local/bin/agent",
            startTime: Date(),
            residentMemory: 1_000_000,
            virtualMemory: 2_000_000,
            cpuTimeUser: 0,
            cpuTimeSystem: 0,
            cpuPercent: 0,
            threadCount: 1,
            niceValue: 0,
            processState: .running,
            isOrphaned: false,
            parentAlive: true,
            hasTTY: false,
            hasSockets: false,
            hasOwningApp: false,
            bundleIdentifier: nil,
            bundlePath: nil,
            owningAppBundleIdentifier: nil,
            owningAppBundlePath: nil,
            category: .healthy,
            classificationReasons: [],
            lastSeen: Date(),
            idleSince: nil,
            launchdJob: LaunchdJobInfo(
                label: "dev.tuist.agent",
                plistPath: "/Library/LaunchDaemons/dev.tuist.agent.plist",
                domain: "system",
                programPath: "/usr/local/bin/agent",
                programArguments: nil,
                keepAlive: true,
                runAtLoad: false
            ),
            appIcon: nil
        )

        let rule = AutoRule(
            name: "Match agent",
            matcherType: .launchdLabel,
            matcherValue: "dev.tuist.agent",
            conditionJSON: "[]",
            action: .kill,
            cooldownSeconds: 600,
            enabled: true,
            createdAt: Date()
        )

        #expect(rule.matches(process))
    }

    @Test func summarySentenceUsesPlainEnglish() {
        var rule = AutoRule(
            name: "Kill helpers",
            matcherType: .bundleId,
            matcherValue: "com.spotify.client",
            conditionJSON: "[]",
            contextAppBundleId: "com.spotify.client",
            contextAppMustBeRunning: false,
            action: .kill,
            cooldownSeconds: 600,
            enabled: true,
            createdAt: Date()
        )
        rule.conditions = [
            RuleCondition(type: .cpuIdleGreaterThan, value: "300"),
            RuleCondition(type: .noSockets, value: "true"),
        ]

        let summary = rule.summarySentence

        #expect(summary.contains("processes from app com.spotify.client"))
        #expect(summary.contains("idle for over 5m"))
        #expect(summary.contains("they have no open sockets"))
        #expect(summary.contains("kill them"))
        #expect(summary.contains("only when com.spotify.client is not running"))
    }

    @Test func draftBuildsTypedConditionsIntoRule() {
        var draft = RuleDraft()
        draft.matcherType = .name
        draft.matcherValue = "Spotify Helper"
        draft.action = .suspend
        draft.idleMinutes = 10
        draft.memoryMB = 512
        draft.socketRequirement = .noSockets
        draft.appOwnershipRequirement = .noOwningApp
        draft.requiresNoTTY = true
        draft.contextMode = .appNotRunning
        draft.contextAppBundleId = "com.spotify.client"

        let rule = draft.buildRule()

        #expect(rule.name == draft.suggestedName)
        #expect(rule.action == .suspend)
        #expect(rule.cooldownSeconds == 600)
        #expect(rule.contextAppBundleId == "com.spotify.client")
        #expect(rule.contextAppMustBeRunning == false)
        #expect(rule.conditions.contains(where: {
            $0.type == .cpuIdleGreaterThan && $0.value == "600"
        }))
        #expect(rule.conditions.contains(where: {
            $0.type == .memoryGreaterThan && $0.value == String(512 * 1_048_576)
        }))
        #expect(rule.conditions.contains(where: { $0.type == .noSockets }))
        #expect(rule.conditions.contains(where: { $0.type == .noOwningApp }))
        #expect(rule.conditions.contains(where: { $0.type == .noTTY }))
    }

    @Test func draftRoundTripsExistingRule() {
        var rule = AutoRule(
            id: 42,
            name: "Mark orphaned agents",
            matcherType: .launchdLabel,
            matcherValue: "com.example.agent",
            conditionJSON: "[]",
            contextAppBundleId: nil,
            contextAppMustBeRunning: nil,
            action: .markSuspicious,
            cooldownSeconds: 900,
            enabled: false,
            createdAt: Date()
        )
        rule.conditions = [
            RuleCondition(type: .isOrphaned, value: "true"),
            RuleCondition(type: .noOwningApp, value: "true"),
            RuleCondition(type: .cpuIdleGreaterThan, value: "300"),
        ]

        let draft = RuleDraft(rule: rule)

        #expect(draft.name == "Mark orphaned agents")
        #expect(draft.matcherType == .launchdLabel)
        #expect(draft.matcherValue == "com.example.agent")
        #expect(draft.action == .markSuspicious)
        #expect(draft.cooldownMinutes == 15)
        #expect(draft.enabled == false)
        #expect(draft.requiresOrphaned)
        #expect(draft.appOwnershipRequirement == .noOwningApp)
        #expect(draft.idleMinutes == 5)
    }
}
