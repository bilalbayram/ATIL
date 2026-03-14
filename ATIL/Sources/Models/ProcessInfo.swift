import AppKit
import Darwin

// MARK: - Process Identity (survives PID reuse)

struct ProcessIdentity: Hashable, Sendable {
    let pid: pid_t
    let startTime: Date
}

// MARK: - Process State

enum ProcessState: String, Sendable {
    case running
    case sleeping
    case suspended
    case zombie
    case unknown
}

// MARK: - Process Category (ordered for display — worst first)

enum ProcessCategory: Int, CaseIterable, Comparable, Sendable {
    case quarantined = 0
    case redundant = 1
    case suspicious = 2
    case healthy = 3

    static func < (lhs: ProcessCategory, rhs: ProcessCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .quarantined: "Quarantined"
        case .redundant: "Redundant"
        case .suspicious: "Suspicious"
        case .healthy: "Healthy"
        }
    }

    var systemImage: String {
        switch self {
        case .quarantined: "lock.circle.fill"
        case .redundant: "xmark.circle.fill"
        case .suspicious: "exclamationmark.triangle.fill"
        case .healthy: "checkmark.circle.fill"
        }
    }
}

// MARK: - Classification Reasons

enum ClassificationReason: String, Sendable, CaseIterable {
    // Redundant/suspicious signals
    case orphanedNoParent
    case longIdle
    case noListeningSockets
    case noTTY
    case highMemoryLowActivity
    case blocklistMatch
    case unknownBinary

    // Healthy signals
    case protectedProcess
    case userIgnored
    case activeApp
    case hasListeningSockets
    case recentCPUActivity

    var isRedundantSignal: Bool {
        switch self {
        case .orphanedNoParent, .longIdle, .noListeningSockets, .noTTY,
             .highMemoryLowActivity, .blocklistMatch, .unknownBinary:
            true
        default:
            false
        }
    }
}

// MARK: - ATILProcess

struct ATILProcess: Identifiable, Sendable {
    var id: ProcessIdentity { identity }

    let identity: ProcessIdentity
    let pid: pid_t
    let ppid: pid_t
    let uid: uid_t
    let name: String
    let executablePath: String?
    let startTime: Date
    let residentMemory: UInt64
    let virtualMemory: UInt64
    let cpuTimeUser: TimeInterval
    let cpuTimeSystem: TimeInterval
    let threadCount: Int32
    let processState: ProcessState
    let isOrphaned: Bool
    let parentAlive: Bool
    let hasTTY: Bool
    let bundleIdentifier: String?
    let bundlePath: String?

    var category: ProcessCategory
    var classificationReasons: Set<ClassificationReason>
    var lastSeen: Date
    var idleSince: Date?

    // Launchd association (v0.2)
    var launchdJob: LaunchdJobInfo?

    // Resolved at display time
    var appIcon: NSImage?

    var cpuTimeTotal: TimeInterval {
        cpuTimeUser + cpuTimeSystem
    }

    var isUserOwned: Bool {
        uid == getuid()
    }
}
