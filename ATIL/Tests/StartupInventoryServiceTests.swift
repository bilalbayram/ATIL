import Foundation
import Testing
@testable import ATIL

struct StartupInventoryServiceTests {
    @Test func parseDisabledStateOutput() {
        let output = """
            disabled services = {
                "com.example.enabled" => enabled
                "com.example.disabled" => disabled
            }
            """

        let states = LaunchdDisabledStateReader.parse(output)

        #expect(states["com.example.enabled"] == false)
        #expect(states["com.example.disabled"] == true)
    }

    @Test func runningLaunchdJobBecomesRunningStartupItem() {
        let job = makeLaunchdJob(domain: "gui/\(getuid())")
        let process = makeProcess(launchdJob: job)
        let service = StartupInventoryService(
            launchdJobsProvider: { [job] },
            disabledStatesProvider: { ["gui/\(getuid())": [job.label: false]] },
            discoveryProvider: {
                StartupDiscoveryContext(installedApps: [], appsByBundleIdentifier: [:], loginItems: [])
            },
            curatedAttributionsProvider: { [:] }
        )

        let items = service.scan(processes: [process])

        #expect(items.count == 1)
        #expect(items[0].state == .running)
        #expect(items[0].kind == .launchAgent)
        #expect(items[0].matchedProcessIDs == [process.pid])
    }

    @Test func disabledLoginHelperLabelBecomesSyntheticLoginItem() {
        let parentApp = InstalledAppInfo(
            bundlePath: "/Applications/WireGuard.app",
            bundleIdentifier: "com.wireguard.macos",
            displayName: "WireGuard",
            executablePath: "/Applications/WireGuard.app/Contents/MacOS/WireGuard",
            teamIdentifier: "TEAM123"
        )
        let helper = DiscoveredLoginItem(
            helperBundlePath: "/Applications/WireGuard.app/Contents/Library/LoginItems/WireGuardHelper.app",
            helperBundleIdentifier: "com.wireguard.macos.login-item-helper",
            helperDisplayName: "WireGuard Helper",
            helperExecutablePath: "/Applications/WireGuard.app/Contents/Library/LoginItems/WireGuardHelper.app/Contents/MacOS/WireGuardHelper",
            parentApp: parentApp
        )
        let service = StartupInventoryService(
            launchdJobsProvider: { [] },
            disabledStatesProvider: { ["gui/\(getuid())": [helper.helperBundleIdentifier!: false]] },
            discoveryProvider: {
                StartupDiscoveryContext(
                    installedApps: [parentApp],
                    appsByBundleIdentifier: [parentApp.bundleIdentifier!: parentApp],
                    loginItems: [helper]
                )
            },
            curatedAttributionsProvider: { [:] }
        )

        let items = service.scan(processes: [])

        #expect(items.count == 1)
        #expect(items[0].kind == .loginItem)
        #expect(items[0].label == helper.helperBundleIdentifier)
        #expect(items[0].app.bundleIdentifier == parentApp.bundleIdentifier)
    }
}
