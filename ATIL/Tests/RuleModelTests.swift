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
}
