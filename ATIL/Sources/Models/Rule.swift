import Foundation
import GRDB

// MARK: - Rule Model

struct AutoRule: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "rules"

    var id: Int64?
    var name: String
    var matcherType: MatcherType
    var matcherValue: String
    var conditionJSON: String // serialized [RuleCondition]
    var contextAppBundleId: String?
    var contextAppMustBeRunning: Bool?
    var action: RuleAction
    var cooldownSeconds: Int
    var enabled: Bool
    var createdAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    enum MatcherType: String, Codable, Sendable, CaseIterable {
        case name
        case path
        case bundleId
        case regex
    }

    enum RuleAction: String, Codable, Sendable, CaseIterable {
        case kill
        case suspend
        case markRedundant

        var displayName: String {
            switch self {
            case .kill: "Kill"
            case .suspend: "Suspend"
            case .markRedundant: "Mark Redundant"
            }
        }
    }

    // MARK: - Condition Serialization

    var conditions: [RuleCondition] {
        get {
            guard let data = conditionJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([RuleCondition].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                conditionJSON = String(data: data, encoding: .utf8) ?? "[]"
            }
        }
    }

    // MARK: - Matching

    func matches(_ process: ATILProcess) -> Bool {
        switch matcherType {
        case .name:
            return process.name.lowercased() == matcherValue.lowercased()
        case .path:
            return process.executablePath?.lowercased() == matcherValue.lowercased()
        case .bundleId:
            return process.bundleIdentifier?.lowercased() == matcherValue.lowercased()
        case .regex:
            guard let regex = try? NSRegularExpression(pattern: matcherValue, options: .caseInsensitive) else {
                return false
            }
            let name = process.name
            return regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
        }
    }

    func conditionsMet(for process: ATILProcess) -> Bool {
        conditions.allSatisfy { $0.isMet(for: process) }
    }
}

// MARK: - Rule Condition

struct RuleCondition: Codable, Sendable {
    var type: ConditionType
    var value: String // threshold value as string

    enum ConditionType: String, Codable, Sendable, CaseIterable {
        case cpuIdleGreaterThan // value in seconds
        case memoryGreaterThan // value in bytes
        case isOrphaned
        case isZombie
        case noTTY
        case noSockets // deferred

        var displayName: String {
            switch self {
            case .cpuIdleGreaterThan: "CPU Idle >"
            case .memoryGreaterThan: "Memory >"
            case .isOrphaned: "Is Orphaned"
            case .isZombie: "Is Zombie"
            case .noTTY: "No Terminal"
            case .noSockets: "No Sockets"
            }
        }

        var needsValue: Bool {
            switch self {
            case .cpuIdleGreaterThan, .memoryGreaterThan: true
            default: false
            }
        }
    }

    func isMet(for process: ATILProcess) -> Bool {
        switch type {
        case .cpuIdleGreaterThan:
            guard let idleSince = process.idleSince,
                  let threshold = TimeInterval(value)
            else { return false }
            return Date().timeIntervalSince(idleSince) > threshold

        case .memoryGreaterThan:
            guard let threshold = UInt64(value) else { return false }
            return process.residentMemory > threshold

        case .isOrphaned:
            return process.isOrphaned

        case .isZombie:
            return process.processState == .zombie

        case .noTTY:
            return !process.hasTTY

        case .noSockets:
            return true // deferred
        }
    }
}

// MARK: - Rule Event

struct RuleEvent: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "ruleEvents"

    var id: Int64?
    let ruleId: Int64
    let processIdentity: String
    let actionTaken: String
    let timestamp: Date

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
