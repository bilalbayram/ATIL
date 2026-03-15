import Foundation

struct ProcessClassifier: Sendable {
    private static let idleThreshold: TimeInterval = 5 * 60 // 5 minutes
    private static let highMemoryThreshold: UInt64 = 100 * 1_048_576 // 100 MB

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
        let isKnownSystemPath = ProcessHeuristics.isKnownSystemPath(p.executablePath)
        let hasConcreteBundle = p.bundleIdentifier != nil || p.bundlePath != nil
        let hasOwningAppBundle = p.owningAppBundleIdentifier != nil || p.owningAppBundlePath != nil
        let isUnmanagedBinary = !hasConcreteBundle
            && !hasOwningAppBundle
            && p.launchdJob == nil
            && !isKnownSystemPath

        // Orphaned check: prefiltered to unmanaged, unowned processes.
        if p.isOrphaned {
            reasons.insert(.orphanedNoParent)
        }

        // Long idle: no CPU activity for > 5 minutes
        let idleDuration: TimeInterval? = {
            guard let idleSince = p.idleSince else { return nil }
            return p.lastSeen.timeIntervalSince(idleSince)
        }()

        if let idleDuration, idleDuration > Self.idleThreshold {
            reasons.insert(.longIdle)
        }

        // No TTY
        if !p.hasTTY && isUnmanagedBinary {
            reasons.insert(.noTTY)
        }

        // No sockets
        if !p.hasSockets && isUnmanagedBinary {
            reasons.insert(.noListeningSockets)
        } else if p.hasSockets {
            reasons.insert(.hasListeningSockets)
        }

        // High memory + idle
        if p.residentMemory > Self.highMemoryThreshold,
           let idleDuration,
           idleDuration > Self.idleThreshold {
            reasons.insert(.highMemoryLowActivity)
        }

        // Blocklist match
        if BlocklistService.shared.isBlocklisted(p) {
            reasons.insert(.blocklistMatch)
        }

        // Unknown binary: unmanaged and outside system locations
        if isUnmanagedBinary {
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

        // Layer 3: Classify based on weighted signals
        let strongSignalKinds: Set<ClassificationReason> = [
            .orphanedNoParent,
            .blocklistMatch,
            .unknownBinary,
        ]
        let weakSignalKinds: Set<ClassificationReason> = [
            .longIdle,
            .highMemoryLowActivity,
            .noTTY,
            .noListeningSockets,
        ]
        let strongSignals = reasons.intersection(strongSignalKinds)
        let weakSignals = reasons.intersection(weakSignalKinds)
        let negativeSignalCount = strongSignals.count + weakSignals.count
        let isStale = reasons.contains(.longIdle) || reasons.contains(.highMemoryLowActivity)

        if !strongSignals.isEmpty && isStale {
            p.category = .redundant
        } else if isUnmanagedBinary && negativeSignalCount >= 3 {
            p.category = .redundant
        } else if !strongSignals.isEmpty {
            p.category = .suspicious
        } else if isUnmanagedBinary && weakSignals.count >= 2 {
            p.category = .suspicious
        } else {
            p.category = .healthy
        }

        p.classificationReasons = reasons
        return p
    }
}
