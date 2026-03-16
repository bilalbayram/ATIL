import Foundation

struct StartupBlockRule: Identifiable, Equatable, Sendable {
    var id: Int64?
    let displayName: String
    let bundleIdentifier: String?
    let teamIdentifier: String?
    let bundlePath: String?
    let knownLabels: [String]
    let knownExecutablePaths: [String]
    let createdAt: Date

    init(
        id: Int64? = nil,
        displayName: String,
        bundleIdentifier: String?,
        teamIdentifier: String?,
        bundlePath: String?,
        knownLabels: [String],
        knownExecutablePaths: [String],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.teamIdentifier = teamIdentifier
        self.bundlePath = bundlePath
        self.knownLabels = knownLabels
        self.knownExecutablePaths = knownExecutablePaths
        self.createdAt = createdAt
    }

    init(app: StartupAppIdentity, items: [StartupItem]) {
        self.init(
            displayName: app.displayName,
            bundleIdentifier: app.bundleIdentifier,
            teamIdentifier: app.teamIdentifier,
            bundlePath: app.bundlePath,
            knownLabels: Array(Set(items.compactMap(\.label))).sorted(),
            knownExecutablePaths: Array(Set(items.compactMap(\.executablePath))).sorted()
        )
    }

    func matches(_ item: StartupItem) -> Bool {
        if let bundleIdentifier {
            if let itemBundleIdentifier = item.app.bundleIdentifier {
                return itemBundleIdentifier == bundleIdentifier
            }
        }

        guard let teamIdentifier, let itemTeamIdentifier = item.app.teamIdentifier else {
            return false
        }
        guard teamIdentifier == itemTeamIdentifier else { return false }

        if let bundlePath, item.app.bundlePath == bundlePath {
            return true
        }
        if let label = item.label, knownLabels.contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) {
            return true
        }
        if let executablePath = item.executablePath, knownExecutablePaths.contains(executablePath) {
            return true
        }
        return false
    }
}
