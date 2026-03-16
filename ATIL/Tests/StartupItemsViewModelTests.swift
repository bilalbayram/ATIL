import Foundation
import Testing
@testable import ATIL

struct StartupItemsViewModelTests {
    @Test @MainActor func blockedFilterOnlyShowsBlockedGroups() async throws {
        let db = try DatabaseManager(inMemory: true)
        let repo = StartupBlockRepository(db: db)
        let blockedApp = makeStartupAppIdentity(displayName: "Steam")
        let blockedItem = makeStartupItem(app: blockedApp)
        let otherItem = makeStartupItem(
            id: "item-2",
            label: "com.spotify.client.startuphelper",
            executablePath: "/Applications/Spotify.app/Contents/MacOS/Spotify",
            app: makeStartupAppIdentity(
                displayName: "Spotify",
                bundleIdentifier: "com.spotify.client",
                teamIdentifier: "SPOT123",
                bundlePath: "/Applications/Spotify.app"
            )
        )
        let vm = StartupItemsViewModel(
            processProvider: { [] },
            processRefreshAction: {},
            blockRepository: repo
        )

        let rule = try repo.save(StartupBlockRule(app: blockedApp, items: [blockedItem]))
        vm.applySnapshot(items: [blockedItem, otherItem], rules: [rule])
        vm.activeFilters = [.blocked]

        #expect(vm.groups.count == 1)
        #expect(vm.groups[0].app.displayName == "Steam")
    }

    @Test @MainActor func focusSelectsMatchingGroupAndItem() {
        let job = makeLaunchdJob(label: "com.valvesoftware.steamclean", domain: "gui/\(getuid())")
        let process = makeProcess(launchdJob: job)
        let vm = StartupItemsViewModel(
            processProvider: { [process] },
            processRefreshAction: {}
        )
        let focusedItem = makeStartupItem(
            label: job.label,
            app: makeStartupAppIdentity()
        )
        let otherItem = makeStartupItem(
            id: "item-2",
            label: "com.spotify.client.startuphelper",
            executablePath: "/Applications/Spotify.app/Contents/MacOS/Spotify",
            app: makeStartupAppIdentity(
                displayName: "Spotify",
                bundleIdentifier: "com.spotify.client",
                teamIdentifier: "SPOT123",
                bundlePath: "/Applications/Spotify.app"
            )
        )

        vm.focus(on: process)
        vm.applySnapshot(items: [otherItem, focusedItem], rules: [])

        #expect(vm.selectedGroup?.app.displayName == "Steam")
        #expect(vm.selectedItem?.label == job.label)
    }
}
