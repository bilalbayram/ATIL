import Darwin
import Foundation
import Testing
@testable import ATIL

struct ProcessGroupTests {
    private func makeProcess(
        pid: pid_t,
        path: String
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
            hasOwningApp: false,
            bundleIdentifier: nil,
            bundlePath: nil,
            category: .suspicious,
            classificationReasons: [.unknownBinary],
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
}
