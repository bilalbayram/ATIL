import Foundation

@MainActor
final class SafetyGate: Sendable {
    static let shared = SafetyGate()

    private let protectedNames: Set<String> = [
        "kernel_task",
        "launchd",
        "loginwindow",
        "WindowServer",
        "opendirectoryd",
        "securityd",
        "diskarbitrationd",
        "CoreServicesUIAgent",
        "SystemUIServer",
        "Dock",
        "Finder",
        "mds",
        "mds_stores",
        "coreaudiod",
        "bluetoothd",
    ]

    /// In-memory cache of ignored identifiers, synced with SQLite
    private var ignoredIdentifiers: Set<String> = []

    private let ignoredRepo = IgnoredRepository(db: DatabaseManager.shared)

    private var selfPID: pid_t {
        ProcessInfo.processInfo.processIdentifier
    }

    init() {
        loadIgnoredFromDB()
    }

    private func loadIgnoredFromDB() {
        do {
            let records = try ignoredRepo.allIgnored()
            ignoredIdentifiers = Set(records.map(\.identifier))
        } catch {
            // If DB fails, fall back to empty set
        }
    }

    func isProtected(_ process: ATILProcess) -> Bool {
        if process.pid == selfPID { return true }
        if process.pid == 0 || process.pid == 1 { return true }
        return protectedNames.contains(process.name)
    }

    func isIgnored(_ process: ATILProcess) -> Bool {
        if let bundleID = process.bundleIdentifier, ignoredIdentifiers.contains(bundleID) {
            return true
        }
        if let path = process.executablePath, ignoredIdentifiers.contains(path) {
            return true
        }
        return false
    }

    func ignore(_ process: ATILProcess) {
        if let bundleID = process.bundleIdentifier {
            ignoredIdentifiers.insert(bundleID)
            try? ignoredRepo.addIgnored(
                identifier: bundleID, type: "bundleId", displayName: process.name
            )
        } else if let path = process.executablePath {
            ignoredIdentifiers.insert(path)
            try? ignoredRepo.addIgnored(
                identifier: path, type: "path", displayName: process.name
            )
        }
    }

    func unignore(_ process: ATILProcess) {
        if let bundleID = process.bundleIdentifier {
            ignoredIdentifiers.remove(bundleID)
            try? ignoredRepo.removeIgnored(identifier: bundleID)
        }
        if let path = process.executablePath {
            ignoredIdentifiers.remove(path)
            try? ignoredRepo.removeIgnored(identifier: path)
        }
    }
}
