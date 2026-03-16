import AppKit
import Foundation

struct InstalledAppInfo: Hashable, Sendable {
    let bundlePath: String
    let bundleIdentifier: String?
    let displayName: String
    let executablePath: String?
    let teamIdentifier: String?
}

struct DiscoveredLoginItem: Hashable, Sendable {
    let helperBundlePath: String
    let helperBundleIdentifier: String?
    let helperDisplayName: String
    let helperExecutablePath: String?
    let parentApp: InstalledAppInfo
}

struct StartupDiscoveryContext: Sendable {
    let installedApps: [InstalledAppInfo]
    let appsByBundleIdentifier: [String: InstalledAppInfo]
    let loginItems: [DiscoveredLoginItem]
}

struct CuratedStartupAttribution: Sendable {
    let displayName: String
    let bundleIdentifiers: [String]
    let teamIdentifier: String?
}

struct StartupAttributionService: Sendable {
    private let codeSignatureReader = CodeSignatureReader()

    func discoverContext() -> StartupDiscoveryContext {
        let runningApplicationPaths = Set(
            NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.path }
        )
        return discoverContext(runningApplicationPaths: runningApplicationPaths)
    }

    func discoverContext(runningApplicationPaths: Set<String>) -> StartupDiscoveryContext {
        let installedApps = discoverInstalledApps(runningApplicationPaths: runningApplicationPaths)
        let appsByBundleIdentifier: [String: InstalledAppInfo] = Dictionary(
            uniqueKeysWithValues: installedApps.compactMap { app in
                guard let bundleIdentifier = app.bundleIdentifier else { return nil }
                return (bundleIdentifier, app)
            }
        )

        let loginItems = installedApps.flatMap { app in
            discoverLoginItems(inside: app)
        }

        return StartupDiscoveryContext(
            installedApps: installedApps,
            appsByBundleIdentifier: appsByBundleIdentifier,
            loginItems: loginItems
        )
    }

    func curatedAttributions() -> [String: CuratedStartupAttribution] {
        Self.curatedAttributionCache
    }

    func resolve(
        label: String?,
        executablePath: String?,
        discovery: StartupDiscoveryContext,
        loginItem: DiscoveredLoginItem? = nil,
        curatedAttribution: CuratedStartupAttribution? = nil
    ) -> (app: StartupAppIdentity, confidence: StartupAttributionConfidence, sources: [String]) {
        if let loginItem {
            return (
                StartupAppIdentity(
                    displayName: loginItem.parentApp.displayName,
                    bundleIdentifier: loginItem.parentApp.bundleIdentifier,
                    teamIdentifier: loginItem.parentApp.teamIdentifier,
                    bundlePath: loginItem.parentApp.bundlePath
                ),
                .high,
                ["loginItemBundle"]
            )
        }

        if let executablePath {
            if let owningAppPath = ProcessHeuristics.owningAppBundlePath(forExecutablePath: executablePath),
               let app = appInfo(at: owningAppPath) {
                return (
                    StartupAppIdentity(
                        displayName: app.displayName,
                        bundleIdentifier: app.bundleIdentifier,
                        teamIdentifier: app.teamIdentifier,
                        bundlePath: app.bundlePath
                    ),
                    .high,
                    ["owningBundlePath"]
                )
            }

            if let bundlePath = ProcessHeuristics.nearestBundlePath(forExecutablePath: executablePath),
               let app = appInfo(at: bundlePath) {
                return (
                    StartupAppIdentity(
                        displayName: app.displayName,
                        bundleIdentifier: app.bundleIdentifier,
                        teamIdentifier: app.teamIdentifier,
                        bundlePath: app.bundlePath
                    ),
                    .medium,
                    ["bundlePath"]
                )
            }
        }

        if let curatedAttribution {
            let resolvedApp = curatedAttribution.bundleIdentifiers.lazy
                .compactMap { discovery.appsByBundleIdentifier[$0] }
                .first

            return (
                StartupAppIdentity(
                    displayName: resolvedApp?.displayName ?? curatedAttribution.displayName,
                    bundleIdentifier: resolvedApp?.bundleIdentifier ?? curatedAttribution.bundleIdentifiers.first,
                    teamIdentifier: resolvedApp?.teamIdentifier ?? curatedAttribution.teamIdentifier,
                    bundlePath: resolvedApp?.bundlePath
                ),
                resolvedApp == nil ? .medium : .high,
                ["curatedAttribution"]
            )
        }

        let signature = executablePath.flatMap { codeSignatureReader.read(path: $0) }
        let fallbackName = label
            ?? executablePath.map { ($0 as NSString).lastPathComponent }
            ?? "Unknown Item"

        return (
            StartupAppIdentity(
                displayName: fallbackName,
                bundleIdentifier: nil,
                teamIdentifier: signature?.teamIdentifier,
                bundlePath: executablePath.flatMap(ProcessHeuristics.owningAppBundlePath(forExecutablePath:))
            ),
            signature?.teamIdentifier == nil ? .low : .medium,
            signature?.teamIdentifier == nil ? ["fallback"] : ["codeSignature"]
        )
    }

    private func discoverInstalledApps(runningApplicationPaths: Set<String>) -> [InstalledAppInfo] {
        let fm = FileManager.default
        let searchRoots = [
            "/Applications",
            "\(NSHomeDirectory())/Applications",
        ]

        var appPaths = runningApplicationPaths

        for root in searchRoots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                appPaths.insert((root as NSString).appendingPathComponent(entry))
            }
        }

        return appPaths.compactMap(appInfo(at:)).sorted { $0.displayName < $1.displayName }
    }

    private func discoverLoginItems(inside app: InstalledAppInfo) -> [DiscoveredLoginItem] {
        let loginItemsDirectory = (app.bundlePath as NSString)
            .appendingPathComponent("Contents/Library/LoginItems")

        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: loginItemsDirectory) else {
            return []
        }

        return entries.compactMap { entry in
            guard entry.hasSuffix(".app") else { return nil }
            let helperBundlePath = (loginItemsDirectory as NSString).appendingPathComponent(entry)
            guard let helperBundle = Bundle(path: helperBundlePath) else { return nil }

            let helperExecutablePath = helperBundle.executableURL?.path
            let teamIdentifier = helperExecutablePath.flatMap { codeSignatureReader.read(path: $0)?.teamIdentifier }

            return DiscoveredLoginItem(
                helperBundlePath: helperBundlePath,
                helperBundleIdentifier: helperBundle.bundleIdentifier,
                helperDisplayName: helperBundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? helperBundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? ((helperBundlePath as NSString).lastPathComponent as NSString).deletingPathExtension,
                helperExecutablePath: helperExecutablePath,
                parentApp: InstalledAppInfo(
                    bundlePath: app.bundlePath,
                    bundleIdentifier: app.bundleIdentifier,
                    displayName: app.displayName,
                    executablePath: app.executablePath,
                    teamIdentifier: app.teamIdentifier ?? teamIdentifier
                )
            )
        }
    }

    private func appInfo(at path: String) -> InstalledAppInfo? {
        guard let bundle = Bundle(path: path) else { return nil }

        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? (path as NSString).lastPathComponent
                .replacingOccurrences(of: ".app", with: "")

        let executablePath = bundle.executableURL?.path
        let teamIdentifier = executablePath.flatMap { codeSignatureReader.read(path: $0)?.teamIdentifier }

        return InstalledAppInfo(
            bundlePath: path,
            bundleIdentifier: bundle.bundleIdentifier,
            displayName: displayName,
            executablePath: executablePath,
            teamIdentifier: teamIdentifier
        )
    }

    private static let curatedAttributionCache: [String: CuratedStartupAttribution] = {
        let path = "/System/Library/PrivateFrameworks/BackgroundTaskManagement.framework/Versions/A/Resources/attributions.plist"
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return [:]
        }

        return plist.reduce(into: [:]) { partialResult, entry in
            guard let value = entry.value as? [String: Any] else { return }
            let displayName = value["Attribution"] as? String ?? entry.key
            let bundleIdentifiers = value["AssociatedBundleIdentifiers"] as? [String] ?? []
            let teamIdentifier = value["TeamIdentifier"] as? String
            partialResult[entry.key] = CuratedStartupAttribution(
                displayName: displayName,
                bundleIdentifiers: bundleIdentifiers,
                teamIdentifier: teamIdentifier
            )
        }
    }()
}
