import Foundation

struct ProcessClassifier: Sendable {
    private static let idleThreshold: TimeInterval = 5 * 60 // 5 minutes
    private static let highMemoryThreshold: UInt64 = 100 * 1_048_576 // 100 MB

    private static let knownSystemPaths: Set<String> = [
        "/usr/sbin/",
        "/usr/libexec/",
        "/System/Library/",
        "/sbin/",
    ]

    @MainActor
    func classify(
        _ process: ATILProcess,
        safetyGate: SafetyGate,
        categoryOverride: ProcessCategory? = nil
    ) -> ATILProcess {
        var p = process
        var reasons: Set<ClassificationReason> = []

        // Layer 0: Suspended processes → quarantined
        if p.processState == .suspended {
            p.category = .quarantined
            p.classificationReasons = reasons
            return p
        }

        // Layer 1: Safety gate — protected or ignored → healthy
        if safetyGate.isProtected(p) {
            reasons.insert(.protectedProcess)
            p.category = .healthy
            p.classificationReasons = reasons
            return p
        }

        if safetyGate.isIgnored(p) {
            reasons.insert(.userIgnored)
            p.category = .healthy
            p.classificationReasons = reasons
            return p
        }

        // Layer 2: Gather signals
        // Orphaned check: ppid == 1 and not a launchd-managed daemon
        if p.isOrphaned && !p.parentAlive {
            reasons.insert(.orphanedNoParent)
        }

        // Long idle: no CPU activity for > 5 minutes
        if let idleSince = p.idleSince {
            let idleDuration = p.lastSeen.timeIntervalSince(idleSince)
            if idleDuration > Self.idleThreshold {
                reasons.insert(.longIdle)
            }
        }

        // No TTY
        if !p.hasTTY && !p.hasOwningApp {
            reasons.insert(.noTTY)
        }

        // No sockets
        if !p.hasSockets && !p.hasOwningApp {
            reasons.insert(.noListeningSockets)
        } else {
            reasons.insert(.hasListeningSockets)
        }

        // High memory + idle
        if p.residentMemory > Self.highMemoryThreshold && p.idleSince != nil {
            reasons.insert(.highMemoryLowActivity)
        }

        // Blocklist match
        if BlocklistService.shared.isBlocklisted(p) {
            reasons.insert(.blocklistMatch)
        }

        // Unknown binary: no bundle ID and not in known system paths
        let isKnownSystemPath = p.executablePath.map { path in
            Self.knownSystemPaths.contains { path.hasPrefix($0) }
        } ?? false

        if p.bundleIdentifier == nil && !isKnownSystemPath {
            reasons.insert(.unknownBinary)
        }

        // Healthy signals
        if p.cpuTimeTotal > 0.1 && p.idleSince == nil {
            reasons.insert(.recentCPUActivity)
        }

        if p.hasOwningApp {
            reasons.insert(.activeApp)
        } else {
            reasons.insert(.noOwningApp)
        }

        if p.launchdJob != nil {
            reasons.insert(.launchdManaged)
        }

        if let categoryOverride {
            switch categoryOverride {
            case .redundant:
                reasons.insert(.userRuleMarkedRedundant)
            case .suspicious:
                reasons.insert(.userRuleMarkedSuspicious)
            default:
                break
            }
            p.category = categoryOverride
            p.classificationReasons = reasons
            return p
        }

        // Layer 3: Classify based on signal count
        let redundantSignals = reasons.filter(\.isRedundantSignal)
        let redundantCount = redundantSignals.count
        let strongSignals: Set<ClassificationReason> = [
            .orphanedNoParent,
            .longIdle,
            .highMemoryLowActivity,
            .userRuleMarkedRedundant,
        ]
        let hasStrongSignal = !reasons.intersection(strongSignals).isEmpty

        if reasons.contains(.launchdManaged) {
            p.category = .suspicious
        } else if hasStrongSignal && redundantCount >= 3 {
            p.category = .redundant
        } else if redundantCount >= 1 {
            p.category = .suspicious
        } else {
            p.category = .healthy
        }

        p.classificationReasons = reasons
        return p
    }
}
