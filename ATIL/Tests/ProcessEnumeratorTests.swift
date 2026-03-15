import Foundation
import Testing
@testable import ATIL

struct ProcessEnumeratorTests {
    let enumerator = ProcessEnumerator()

    @Test func listPIDsReturnsNonEmpty() {
        let pids = enumerator.listAllPIDs()
        #expect(!pids.isEmpty, "Should enumerate at least one PID")
    }

    @Test func selfPIDAppears() {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let pids = enumerator.listAllPIDs()
        #expect(pids.contains(selfPID), "Our own PID should appear in the list")
    }

    @Test func selfBSDInfoIsReachable() {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let info = enumerator.getBSDInfo(pid: selfPID)
        #expect(info != nil, "Our own PID should be queryable via BSD info")
    }

    @Test func canGetSelfPath() {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let path = enumerator.getPath(pid: selfPID)
        #expect(path != nil, "Should be able to get our own executable path")
    }

    @Test func buildsSelfProcess() {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let pids = enumerator.listAllPIDs()
        let context = ProcessEnumerator.EnumerationContext(
            now: Date(),
            currentUID: getuid(),
            alivePIDs: Set(pids),
            previousIdleTimes: [:],
            previousCPUTimes: [:],
            previousSeenTimes: [:],
            launchdMap: [:]
        )
        let appMap = enumerator.buildRunningAppMap()
        let process = enumerator.buildProcess(
            pid: selfPID,
            appMap: appMap,
            runningAppBundlePaths: enumerator.buildRunningAppBundlePaths(),
            context: context
        )
        #expect(process != nil, "Should be able to build a process for our own PID")
        #expect(process?.pid == selfPID)
    }
}
