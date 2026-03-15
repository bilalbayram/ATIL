import SwiftUI

enum ProcessStatusTag: String, CaseIterable, Hashable, Sendable {
    case orphaned
    case respawns
    case idle
    case blocklist
    case protected
    case none

    var displayName: String {
        switch self {
        case .orphaned: "Orphaned"
        case .respawns: "Respawns"
        case .idle: "Idle"
        case .blocklist: "Blocklist"
        case .protected: "Protected"
        case .none: "None"
        }
    }

    var color: Color {
        switch self {
        case .orphaned: .orange
        case .respawns: .purple
        case .idle: .yellow
        case .blocklist: .red
        case .protected: .blue
        case .none: .gray
        }
    }

    var icon: String? {
        switch self {
        case .orphaned: nil
        case .respawns: "arrow.counterclockwise"
        case .idle: nil
        case .blocklist: "list.bullet"
        case .protected: "lock.fill"
        case .none: nil
        }
    }

    func matches(_ process: ATILProcess) -> Bool {
        switch self {
        case .orphaned:
            return process.isOrphaned
        case .respawns:
            return process.launchdJob?.willRespawn == true
        case .idle:
            guard let idle = process.idleSince else { return false }
            return Date().timeIntervalSince(idle) > 300
        case .blocklist:
            return process.classificationReasons.contains(.blocklistMatch)
        case .protected:
            return process.classificationReasons.contains(.protectedProcess)
        case .none:
            let hasOrphaned = process.isOrphaned
            let hasRespawns = process.launchdJob?.willRespawn == true
            let hasIdle: Bool = {
                guard let idle = process.idleSince else { return false }
                return Date().timeIntervalSince(idle) > 300
            }()
            let hasBlocklist = process.classificationReasons.contains(.blocklistMatch)
            let hasProtected = process.classificationReasons.contains(.protectedProcess)
            return !hasOrphaned && !hasRespawns && !hasIdle && !hasBlocklist && !hasProtected
        }
    }
}
