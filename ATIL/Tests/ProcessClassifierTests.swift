import Darwin
import Foundation
import Testing
@testable import ATIL

struct ProcessClassifierTests {
    private let classifier = ProcessClassifier()

    private func makeProcess(
        name: String = "test",
        pid: pid_t = 999,
        ppid: pid_t = 100,
        isOrphaned: Bool = false,
        parentAlive: Bool = true,
        hasTTY: Bool = false,
        hasSockets: Bool = false,
        hasOwningApp: Bool? = nil,
        residentMemory: UInt64 = 1_000_000,
        cpuTimeUser: TimeInterval = 0,
        idleSince: Date? = nil,
        bundleIdentifier: String? = nil,
        bundlePath: String? = nil,
        owningAppBundleIdentifier: String? = nil,
        owningAppBundlePath: String? = nil,
        executablePath: String? = "/usr/local/bin/test",
        launchdJob: LaunchdJobInfo? = nil
    ) -> ATILProcess {
        ATILProcess(
            identity: ProcessIdentity(pid: pid, startTime: Date()),
            pid: pid,
            ppid: ppid,
            uid: getuid(),
            gid: getgid(),
            name: name,
            executablePath: executablePath,
            startTime: Date(),
            residentMemory: residentMemory,
            virtualMemory: 10_000_000,
            cpuTimeUser: cpuTimeUser,
            cpuTimeSystem: 0,
            cpuPercent: 0,
            threadCount: 1,
            niceValue: 0,
            processState: .running,
            isOrphaned: isOrphaned,
            parentAlive: parentAlive,
            hasTTY: hasTTY,
            hasSockets: hasSockets,
            hasOwningApp: hasOwningApp ?? (owningAppBundleIdentifier != nil),
            bundleIdentifier: bundleIdentifier,
            bundlePath: bundlePath,
            owningAppBundleIdentifier: owningAppBundleIdentifier,
            owningAppBundlePath: owningAppBundlePath,
            category: .healthy,
            classificationReasons: [],
            lastSeen: Date(),
            idleSince: idleSince,
            launchdJob: launchdJob,
            appIcon: nil
        )
    }

    private func makeLaunchdJob(label: String = "dev.tuist.agent") -> LaunchdJobInfo {
        LaunchdJobInfo(
            label: label,
            plistPath: "/Library/LaunchDaemons/\(label).plist",
            domain: "system",
            programPath: "/usr/local/bin/\(label)",
            programArguments: nil,
            keepAlive: true,
            runAtLoad: true
        )
    }

    @Test @MainActor func ppidOneAppOwnedProcessIsHealthyAndNotOrphaned() {
        let p = makeProcess(
            name: "Mail Spotlight Extension",
            ppid: 1,
            isOrphaned: false,
            parentAlive: false,
            hasTTY: false,
            hasOwningApp: true,
            bundleIdentifier: "com.apple.mail.SpotlightIndexExtension",
            bundlePath: "/System/Applications/Mail.app/Contents/PlugIns/com.apple.mail.SpotlightIndexExtension.appex",
            owningAppBundleIdentifier: "com.apple.mail",
            owningAppBundlePath: "/System/Applications/Mail.app",
            executablePath: "/System/Applications/Mail.app/Contents/PlugIns/com.apple.mail.SpotlightIndexExtension.appex/Contents/MacOS/com.apple.mail.SpotlightIndexExtension"
        )
        let result = classifier.classify(p, safetyGate: SafetyGate.shared)
        #expect(result.category == .healthy)
        #expect(!result.classificationReasons.contains(.orphanedNoParent))
    }

    @Test @MainActor func launchdManagedAgentIsHealthyByDefault() {
        let p = makeProcess(
            name: "Little Snitch Agent",
            ppid: 1,
            isOrphaned: false,
            parentAlive: false,
            hasTTY: false,
            bundleIdentifier: "at.obdev.littlesnitch.agent",
            bundlePath: "/Applications/Little Snitch.app/Contents/Components/Little Snitch Agent.app",
            executablePath: "/Applications/Little Snitch.app/Contents/Components/Little Snitch Agent.app/Contents/MacOS/Little Snitch Agent",
            launchdJob: makeLaunchdJob(label: "at.obdev.littlesnitch.agent")
        )
        let result = classifier.classify(p, safetyGate: SafetyGate.shared)
        #expect(result.category == .healthy)
        #expect(result.classificationReasons.contains(.launchdManaged))
        #expect(!result.classificationReasons.contains(.orphanedNoParent))
    }

    @Test @MainActor func nestedHelperAppIsHealthyWhenOwningAppIsRunning() {
        let p = makeProcess(
            name: "Codex Helper",
            ppid: 21091,
            hasTTY: false,
            hasOwningApp: true,
            bundleIdentifier: "com.openai.codex.helper",
            bundlePath: "/Applications/Codex.app/Contents/Frameworks/Codex Helper.app",
            owningAppBundleIdentifier: "com.openai.codex",
            owningAppBundlePath: "/Applications/Codex.app",
            executablePath: "/Applications/Codex.app/Contents/Frameworks/Codex Helper.app/Contents/MacOS/Codex Helper"
        )
        let result = classifier.classify(p, safetyGate: SafetyGate.shared)
        #expect(result.category == .healthy)
        #expect(result.classificationReasons.contains(.activeApp))
    }

    @Test @MainActor func unknownIdleUnmanagedBinaryBecomesRedundant() {
        let p = makeProcess(
            ppid: 1,
            isOrphaned: true,
            parentAlive: false,
            hasTTY: false,
            idleSince: Date().addingTimeInterval(-600), // 10 min idle
            bundleIdentifier: nil,
            executablePath: "/opt/custom/bin/something"
        )
        let result = classifier.classify(p, safetyGate: SafetyGate.shared)
        #expect(result.category == .redundant)
    }

    @Test @MainActor func healthyAppProcess() {
        let p = makeProcess(
            hasTTY: false,
            cpuTimeUser: 5.0,
            idleSince: nil,
            bundleIdentifier: "com.apple.Safari",
            bundlePath: "/Applications/Safari.app",
            owningAppBundleIdentifier: "com.apple.Safari",
            owningAppBundlePath: "/Applications/Safari.app",
            executablePath: "/Applications/Safari.app/Contents/MacOS/Safari"
        )
        let result = classifier.classify(p, safetyGate: SafetyGate.shared)
        #expect(result.category == .healthy)
    }

    @Test @MainActor func protectedProcessIsAlwaysHealthy() {
        let p = makeProcess(
            name: "WindowServer",
            ppid: 1,
            isOrphaned: true,
            parentAlive: false,
            idleSince: Date().addingTimeInterval(-600)
        )
        let result = classifier.classify(p, safetyGate: SafetyGate.shared)
        #expect(result.category == .healthy, "Protected process must always be healthy")
        #expect(result.classificationReasons.contains(.protectedProcess))
    }

    @Test @MainActor func unknownBinaryIsSuspicious() {
        let p = makeProcess(
            bundleIdentifier: nil,
            executablePath: "/opt/custom/bin/mystery"
        )
        let result = classifier.classify(p, safetyGate: SafetyGate.shared)
        #expect(result.category == .suspicious)
        #expect(result.classificationReasons.contains(.unknownBinary))
    }

    @Test @MainActor func highMemoryBelowIdleThresholdDoesNotTriggerHighMemoryLowActivity() {
        let p = makeProcess(
            residentMemory: 250 * 1_048_576,
            idleSince: Date().addingTimeInterval(-120),
            bundleIdentifier: nil,
            executablePath: "/opt/custom/bin/mystery"
        )
        let result = classifier.classify(p, safetyGate: SafetyGate.shared)
        #expect(!result.classificationReasons.contains(.highMemoryLowActivity))
    }
}
