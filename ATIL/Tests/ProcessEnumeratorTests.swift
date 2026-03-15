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

    @Test func helperBundleResolutionUsesNearestBundleAndOwningApp() {
        let helperPath = "/Applications/Codex.app/Contents/Frameworks/Codex Helper.app/Contents/MacOS/Codex Helper"

        #expect(
            enumerator.nearestBundlePath(forExecutablePath: helperPath)
                == "/Applications/Codex.app/Contents/Frameworks/Codex Helper.app"
        )
        #expect(
            enumerator.owningAppBundlePath(forExecutablePath: helperPath)
                == "/Applications/Codex.app"
        )
    }

    @Test func appexAndXPCResolveToOwningApp() {
        let appexPath = "/System/Applications/Mail.app/Contents/PlugIns/com.apple.mail.SpotlightIndexExtension.appex/Contents/MacOS/com.apple.mail.SpotlightIndexExtension"
        let xpcPath = "/Applications/Xcode.app/Contents/SharedFrameworks/SourceKit.framework/Versions/A/XPCServices/com.apple.dt.SKAgent.xpc/Contents/MacOS/com.apple.dt.SKAgent"

        #expect(
            enumerator.nearestBundlePath(forExecutablePath: appexPath)
                == "/System/Applications/Mail.app/Contents/PlugIns/com.apple.mail.SpotlightIndexExtension.appex"
        )
        #expect(
            enumerator.owningAppBundlePath(forExecutablePath: appexPath)
                == "/System/Applications/Mail.app"
        )
        #expect(
            enumerator.nearestBundlePath(forExecutablePath: xpcPath)
                == "/Applications/Xcode.app/Contents/SharedFrameworks/SourceKit.framework/Versions/A/XPCServices/com.apple.dt.SKAgent.xpc"
        )
        #expect(
            enumerator.owningAppBundlePath(forExecutablePath: xpcPath)
                == "/Applications/Xcode.app"
        )
    }

    @Test func launchdManagedAndAppOwnedProcessesAreNotLikelyOrphans() {
        let launchdJob = LaunchdJobInfo(
            label: "at.obdev.littlesnitch.agent",
            plistPath: "/Library/LaunchAgents/at.obdev.littlesnitch.agent.plist",
            domain: "gui/\(getuid())",
            programPath: "/Applications/Little Snitch.app/Contents/Components/Little Snitch Agent.app/Contents/MacOS/Little Snitch Agent",
            programArguments: nil,
            keepAlive: true,
            runAtLoad: true
        )

        #expect(
            !ProcessHeuristics.isLikelyOrphaned(
                ppid: 1,
                launchdJob: launchdJob,
                owningAppBundlePath: nil,
                owningAppBundleIdentifier: nil,
                bundlePath: "/Applications/Little Snitch.app/Contents/Components/Little Snitch Agent.app",
                bundleIdentifier: "at.obdev.littlesnitch.agent",
                executablePath: launchdJob.programPath
            )
        )

        #expect(
            !ProcessHeuristics.isLikelyOrphaned(
                ppid: 1,
                launchdJob: nil,
                owningAppBundlePath: "/System/Applications/Mail.app",
                owningAppBundleIdentifier: "com.apple.mail",
                bundlePath: "/System/Applications/Mail.app/Contents/PlugIns/com.apple.mail.SpotlightIndexExtension.appex",
                bundleIdentifier: "com.apple.mail.SpotlightIndexExtension",
                executablePath: "/System/Applications/Mail.app/Contents/PlugIns/com.apple.mail.SpotlightIndexExtension.appex/Contents/MacOS/com.apple.mail.SpotlightIndexExtension"
            )
        )
    }
}
