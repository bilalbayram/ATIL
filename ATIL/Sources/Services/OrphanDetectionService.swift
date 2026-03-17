import AppKit
import Foundation

struct OrphanedStartupItem: Identifiable, Sendable, Equatable {
    let item: StartupItem
    let executableMissing: Bool
    let appBundleMissing: Bool

    var id: String { item.id }
}

struct OrphanDetectionService: Sendable {
    func detectOrphans(in items: [StartupItem]) -> [OrphanedStartupItem] {
        let fileManager = FileManager.default

        return items.compactMap { item in
            guard item.plistPath != nil else { return nil }

            // Skip Apple's own agents/daemons
            if let label = item.label, label.hasPrefix("com.apple.") {
                return nil
            }

            let executableMissing: Bool
            if let executablePath = item.executablePath {
                executableMissing = !fileManager.fileExists(atPath: executablePath)
            } else {
                // No executable path to check — can't confirm it's orphaned via executable
                executableMissing = true
            }

            let appBundleMissing: Bool
            if let bundleIdentifier = item.app.bundleIdentifier {
                appBundleMissing = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: bundleIdentifier
                ) == nil
            } else if let bundlePath = item.app.bundlePath {
                appBundleMissing = !fileManager.fileExists(atPath: bundlePath)
            } else {
                // No bundle info to check — can't confirm it's orphaned via bundle
                appBundleMissing = true
            }

            // Both must be missing to consider it orphaned
            guard executableMissing && appBundleMissing else { return nil }

            return OrphanedStartupItem(
                item: item,
                executableMissing: executableMissing,
                appBundleMissing: appBundleMissing
            )
        }
    }
}
