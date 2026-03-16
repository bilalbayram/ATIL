import Foundation
import Testing
@testable import ATIL

struct StartupBlockTests {
    @Test func ruleMatchesBundleIdentifierBeforeFallbacks() {
        let rule = StartupBlockRule(
            displayName: "Steam",
            bundleIdentifier: "com.valvesoftware.steam",
            teamIdentifier: "VALVE123",
            bundlePath: "/Applications/Steam.app",
            knownLabels: ["com.valvesoftware.steamclean"],
            knownExecutablePaths: ["/Users/test/Steam/steamclean"]
        )
        let matchingItem = makeStartupItem(app: makeStartupAppIdentity())
        let nonMatchingItem = makeStartupItem(
            label: "com.valvesoftware.steamclean",
            executablePath: "/Users/test/Steam/steamclean",
            app: makeStartupAppIdentity(bundleIdentifier: "com.valvesoftware.steamcmd")
        )

        #expect(rule.matches(matchingItem))
        #expect(!rule.matches(nonMatchingItem))
    }

    @Test func ruleFallsBackToTeamAndLabelWhenBundleIdentifierMissing() {
        let rule = StartupBlockRule(
            displayName: "Unknown Helper",
            bundleIdentifier: nil,
            teamIdentifier: "TEAM123",
            bundlePath: nil,
            knownLabels: ["com.example.helper"],
            knownExecutablePaths: []
        )
        let item = makeStartupItem(
            label: "com.example.helper",
            app: makeStartupAppIdentity(
                displayName: "Example",
                bundleIdentifier: nil,
                teamIdentifier: "TEAM123",
                bundlePath: nil
            )
        )

        #expect(rule.matches(item))
    }

    @Test func repositoryRoundTripsRule() throws {
        let db = try DatabaseManager(inMemory: true)
        let repo = StartupBlockRepository(db: db)
        let input = StartupBlockRule(
            displayName: "Steam",
            bundleIdentifier: "com.valvesoftware.steam",
            teamIdentifier: "VALVE123",
            bundlePath: "/Applications/Steam.app",
            knownLabels: ["com.valvesoftware.steamclean"],
            knownExecutablePaths: ["/Users/test/Steam/steamclean"]
        )

        let saved = try repo.save(input)
        let rules = try repo.allRules()

        #expect(saved.id != nil)
        #expect(rules.count == 1)
        #expect(rules[0].bundleIdentifier == input.bundleIdentifier)
        #expect(rules[0].knownLabels == input.knownLabels)
    }
}
