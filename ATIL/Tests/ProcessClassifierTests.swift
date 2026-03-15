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
        residentMemory: UInt64 = 1_000_000,
        cpuTimeUser: TimeInterval = 0,
        idleSince: Date? = nil,
        bundleIdentifier: String? = nil,
        executablePath: String? = "/usr/local/bin/test"
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
            hasSockets: false,
            hasOwningApp: bundleIdentifier != nil,
            bundleIdentifier: bundleIdentifier,
            bundlePath: nil,
            category: .healthy,
            classificationReasons: [],
            lastSeen: Date(),
            idleSince: idleSince,
            launchdJob: nil,
            appIcon: nil
        )
    }

    @Test @MainActor func orphanedAloneIsNotRedundant() {
        // Per spec: "Orphaned is a signal, not a verdict" — never mark redundant on orphan alone
        // Process has a bundle ID and a known system path, so only orphan signal fires
        let p = makeProcess(
            ppid: 1,
            isOrphaned: true,
            parentAlive: false,
            hasTTY: true,
            bundleIdentifier: "com.example.helper",
            executablePath: "/System/Library/Frameworks/helper"
        )
        let result = classifier.classify(p, safetyGate: SafetyGate.shared)
        #expect(result.category != .redundant, "Orphaned alone should not be redundant")
    }

    @Test @MainActor func multipleRedundantSignalsMarkRedundant() {
        // 3+ signals: orphaned + long idle + no TTY + unknown binary
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
        #expect(result.category == .redundant, "3+ redundant signals should classify as redundant")
    }

    @Test @MainActor func healthyAppProcess() {
        let p = makeProcess(
            hasTTY: false,
            cpuTimeUser: 5.0,
            idleSince: nil,
            bundleIdentifier: "com.apple.Safari",
            executablePath: "/Applications/Safari.app/Contents/MacOS/Safari"
        )
        let result = classifier.classify(p, safetyGate: SafetyGate.shared)
        #expect(result.category == .healthy, "Active app with bundle ID should be healthy")
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
        #expect(result.category == .suspicious, "Unknown binary should be suspicious")
    }
}
