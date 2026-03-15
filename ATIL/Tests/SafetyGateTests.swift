import Darwin
import Foundation
import Testing
@testable import ATIL

struct SafetyGateTests {

    private func makeProcess(
        pid: pid_t = 999,
        name: String = "test_process",
        uid: uid_t = getuid(),
        bundleIdentifier: String? = nil,
        executablePath: String? = "/usr/bin/test"
    ) -> ATILProcess {
        ATILProcess(
            identity: ProcessIdentity(pid: pid, startTime: Date()),
            pid: pid,
            ppid: 1,
            uid: uid,
            gid: getgid(),
            name: name,
            executablePath: executablePath,
            startTime: Date(),
            residentMemory: 1_000_000,
            virtualMemory: 10_000_000,
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
            hasOwningApp: bundleIdentifier != nil,
            bundleIdentifier: bundleIdentifier,
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

    @Test @MainActor func protectedProcessNames() {
        let gate = SafetyGate.shared
        let protectedNames = [
            "kernel_task", "launchd", "WindowServer", "Dock", "Finder",
            "loginwindow", "securityd",
        ]
        for name in protectedNames {
            let p = makeProcess(name: name)
            #expect(gate.isProtected(p), "\(name) should be protected")
        }
    }

    @Test @MainActor func selfProtection() {
        let gate = SafetyGate.shared
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let p = makeProcess(pid: selfPID, name: "some_random_name")
        #expect(gate.isProtected(p), "Our own PID should always be protected")
    }

    @Test @MainActor func unprotectedProcess() {
        let gate = SafetyGate.shared
        let p = makeProcess(name: "my_custom_helper")
        #expect(!gate.isProtected(p), "Arbitrary process should not be protected")
    }

    @Test @MainActor func ignoreAndUnignore() {
        let gate = SafetyGate.shared
        let p = makeProcess(bundleIdentifier: "com.test.ignored", executablePath: "/usr/local/bin/test")
        #expect(!gate.isIgnored(p))
        gate.ignore(p)
        #expect(gate.isIgnored(p))
        gate.unignore(p)
        #expect(!gate.isIgnored(p))
    }
}
