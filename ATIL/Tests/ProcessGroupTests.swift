import Darwin
import Foundation
import Testing
@testable import ATIL

struct ProcessGroupTests {
    private func makeProcess(
        pid: pid_t,
        path: String,
        bundleIdentifier: String? = nil,
        bundlePath: String? = nil,
        owningAppBundleIdentifier: String? = nil,
        owningAppBundlePath: String? = nil,
        classificationReasons: Set<ClassificationReason> = [.unknownBinary]
    ) -> ATILProcess {
        ATILProcess(
            identity: ProcessIdentity(pid: pid, startTime: Date()),
            pid: pid,
            ppid: 1,
            uid: getuid(),
            gid: getgid(),
            name: (path as NSString).lastPathComponent,
            executablePath: path,
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
            hasOwningApp: owningAppBundleIdentifier != nil,
            bundleIdentifier: bundleIdentifier,
            bundlePath: bundlePath,
            owningAppBundleIdentifier: owningAppBundleIdentifier,
            owningAppBundlePath: owningAppBundlePath,
            category: .suspicious,
            classificationReasons: classificationReasons,
            lastSeen: Date(),
            idleSince: nil,
            launchdJob: nil,
            appIcon: nil
        )
    }

    @Test func rawBinariesStaySeparateByPath() {
        let groups = ProcessGroup.group([
            makeProcess(pid: 100, path: "/opt/project-a/bin/python3"),
            makeProcess(pid: 101, path: "/opt/project-b/bin/python3"),
        ])

        #expect(groups.count == 2)
        #expect(Set(groups.map(\.id)) == [
            "/opt/project-a/bin/python3",
            "/opt/project-b/bin/python3",
        ])
    }

    @Test func helpersGroupUnderOwningApp() {
        let groups = ProcessGroup.group([
            makeProcess(
                pid: 200,
                path: "/Applications/Codex.app/Contents/Frameworks/Codex Helper.app/Contents/MacOS/Codex Helper",
                bundleIdentifier: "com.openai.codex.helper",
                bundlePath: "/Applications/Codex.app/Contents/Frameworks/Codex Helper.app",
                owningAppBundleIdentifier: "com.openai.codex",
                owningAppBundlePath: "/Applications/Codex.app",
                classificationReasons: []
            ),
            makeProcess(
                pid: 201,
                path: "/Applications/Codex.app/Contents/Frameworks/Codex Helper (Renderer).app/Contents/MacOS/Codex Helper (Renderer)",
                bundleIdentifier: "com.openai.codex.helper.renderer",
                bundlePath: "/Applications/Codex.app/Contents/Frameworks/Codex Helper (Renderer).app",
                owningAppBundleIdentifier: "com.openai.codex",
                owningAppBundlePath: "/Applications/Codex.app",
                classificationReasons: []
            ),
        ])

        #expect(groups.count == 1)
        #expect(groups.first?.id == "com.openai.codex")
        #expect(groups.first?.processCount == 2)
    }

    @Test func orphanBadgeTracksClassificationReason() {
        let orphaned = makeProcess(
            pid: 300,
            path: "/opt/custom/bin/orphan",
            classificationReasons: [.orphanedNoParent]
        )
        let appOwned = makeProcess(
            pid: 301,
            path: "/Applications/Codex.app/Contents/Frameworks/Codex Helper.app/Contents/MacOS/Codex Helper",
            bundleIdentifier: "com.openai.codex.helper",
            bundlePath: "/Applications/Codex.app/Contents/Frameworks/Codex Helper.app",
            owningAppBundleIdentifier: "com.openai.codex",
            owningAppBundlePath: "/Applications/Codex.app",
            classificationReasons: []
        )

        #expect(orphaned.shouldDisplayOrphanBadge)
        #expect(!appOwned.shouldDisplayOrphanBadge)
    }
}
