import Darwin
import Foundation

enum StartupItemKind: String, CaseIterable, Codable, Sendable {
    case launchAgent
    case launchDaemon
    case loginItem
    case backgroundHelper

    var displayName: String {
        switch self {
        case .launchAgent: "Launch Agent"
        case .launchDaemon: "Launch Daemon"
        case .loginItem: "Login Item"
        case .backgroundHelper: "Background Helper"
        }
    }
}

enum StartupItemScope: String, CaseIterable, Codable, Sendable {
    case user
    case system

    var displayName: String {
        switch self {
        case .user: "User"
        case .system: "System"
        }
    }
}

enum StartupItemState: String, CaseIterable, Codable, Sendable {
    case enabled
    case disabled
    case running
    case unknown

    var displayName: String {
        rawValue.capitalized
    }
}

enum StartupAttributionConfidence: Int, Comparable, Codable, Sendable {
    case low = 0
    case medium = 1
    case high = 2

    static func < (lhs: StartupAttributionConfidence, rhs: StartupAttributionConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

struct StartupAppIdentity: Hashable, Codable, Sendable {
    let displayName: String
    let bundleIdentifier: String?
    let teamIdentifier: String?
    let bundlePath: String?

    var id: String {
        bundleIdentifier
            ?? bundlePath
            ?? teamIdentifier.map { "team:\($0)" }
            ?? "name:\(displayName.lowercased())"
    }
}

struct StartupItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let kind: StartupItemKind
    let scope: StartupItemScope
    var state: StartupItemState
    let label: String?
    let plistPath: String?
    let executablePath: String?
    let programArguments: [String]
    let domain: String
    let app: StartupAppIdentity
    let attributionConfidence: StartupAttributionConfidence
    let attributionSources: [String]
    let matchedProcessIDs: [pid_t]
    let matchedProcessNames: [String]

    var displayLabel: String {
        if let label, !label.isEmpty {
            return label
        }
        if let executablePath {
            return (executablePath as NSString).lastPathComponent
        }
        return app.displayName
    }

    var isRunning: Bool {
        state == .running || !matchedProcessIDs.isEmpty
    }

    var requiresHelper: Bool {
        scope == .system
    }

    var canDisable: Bool {
        label != nil && state != .unknown
    }

    var canDeletePlist: Bool {
        plistPath != nil && state != .unknown
    }

    var serviceTarget: String? {
        guard let label else { return nil }
        return "\(domain)/\(label)"
    }
}

struct StartupAppGroup: Identifiable, Sendable {
    let app: StartupAppIdentity
    let items: [StartupItem]
    let isBlocked: Bool

    var id: String { app.id }

    var runningItemCount: Int {
        items.filter(\.isRunning).count
    }

    var enabledItemCount: Int {
        items.filter { $0.state == .enabled || $0.state == .running }.count
    }
}

struct StartupItemFocus: Sendable {
    let bundleIdentifier: String?
    let bundlePath: String?
    let label: String?
}
