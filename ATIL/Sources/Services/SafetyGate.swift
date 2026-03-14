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

    /// User-ignored paths/bundleIDs — in-memory for v0.1, persisted in v0.3
    private var ignoredIdentifiers: Set<String> = []

    private var selfPID: pid_t {
        ProcessInfo.processInfo.processIdentifier
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
        } else if let path = process.executablePath {
            ignoredIdentifiers.insert(path)
        }
    }

    func unignore(_ process: ATILProcess) {
        if let bundleID = process.bundleIdentifier {
            ignoredIdentifiers.remove(bundleID)
        }
        if let path = process.executablePath {
            ignoredIdentifiers.remove(path)
        }
    }
}
