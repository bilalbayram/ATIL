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
        case launchdLabel
        case regex
    }

    enum RuleAction: String, Codable, Sendable, CaseIterable {
        case kill
        case suspend
        case markRedundant
        case markSuspicious

        var displayName: String {
            switch self {
            case .kill: "Kill"
            case .suspend: "Suspend"
            case .markRedundant: "Mark Redundant"
            case .markSuspicious: "Mark Suspicious"
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
        case .launchdLabel:
            return process.launchdJob?.label.lowercased() == matcherValue.lowercased()
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
        case hasSockets
        case noSockets
        case hasOwningApp
        case noOwningApp

        var displayName: String {
            switch self {
            case .cpuIdleGreaterThan: "CPU Idle >"
            case .memoryGreaterThan: "Memory >"
            case .isOrphaned: "Is Orphaned"
            case .isZombie: "Is Zombie"
            case .noTTY: "No Terminal"
            case .hasSockets: "Has Sockets"
            case .noSockets: "No Sockets"
            case .hasOwningApp: "Has Owning App"
            case .noOwningApp: "No Owning App"
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

        case .hasSockets:
            return process.hasSockets

        case .noSockets:
            return !process.hasSockets

        case .hasOwningApp:
            return process.hasOwningApp

        case .noOwningApp:
            return !process.hasOwningApp
        }
    }
}

// MARK: - Rule Presentation

extension AutoRule.RuleAction {
    var summaryPhrase: String {
        switch self {
        case .kill: "kill them"
        case .suspend: "suspend them"
        case .markRedundant: "mark them as redundant"
        case .markSuspicious: "mark them as suspicious"
        }
    }
}

extension RuleCondition {
    var summaryFragment: String {
        switch type {
        case .cpuIdleGreaterThan:
            if let seconds = TimeInterval(value), seconds > 0 {
                return "they have been idle for over \(formatDuration(seconds))"
            }
            return "their idle time is over \(value) seconds"

        case .memoryGreaterThan:
            if let bytes = UInt64(value), bytes > 0 {
                return "they use over \(formatBytes(bytes)) of memory"
            }
            return "their memory use is over \(value) bytes"

        case .isOrphaned:
            return "they are orphaned"

        case .isZombie:
            return "they are zombie processes"

        case .noTTY:
            return "they do not have a terminal"

        case .hasSockets:
            return "they have open sockets"

        case .noSockets:
            return "they have no open sockets"

        case .hasOwningApp:
            return "they belong to an app"

        case .noOwningApp:
            return "they have no owning app"
        }
    }

    var badgeText: String {
        switch type {
        case .cpuIdleGreaterThan:
            if let seconds = TimeInterval(value), seconds > 0 {
                return "idle > \(formatDuration(seconds))"
            }
            return "idle > \(value)s"

        case .memoryGreaterThan:
            if let bytes = UInt64(value), bytes > 0 {
                return "mem > \(formatBytes(bytes))"
            }
            return "mem > \(value)"

        case .isOrphaned:
            return "orphaned"

        case .isZombie:
            return "zombie"

        case .noTTY:
            return "no terminal"

        case .hasSockets:
            return "has sockets"

        case .noSockets:
            return "no sockets"

        case .hasOwningApp:
            return "has app"

        case .noOwningApp:
            return "no app"
        }
    }
}

extension AutoRule {
    var targetDescription: String {
        let value = matcherValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "these processes" }

        switch matcherType {
        case .name:
            return "processes named \(value)"
        case .path:
            return "processes at \(value)"
        case .bundleId:
            return "processes from app \(value)"
        case .launchdLabel:
            return "launchd jobs labeled \(value)"
        case .regex:
            return "processes whose names match \(value)"
        }
    }

    var shortTargetLabel: String {
        let value = matcherValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "rule" }

        switch matcherType {
        case .path:
            return URL(fileURLWithPath: value).lastPathComponent
        default:
            return value
        }
    }

    var suggestedName: String {
        var name = "\(action.displayName) \(shortTargetLabel)"
        if let idleCondition = conditions.first(where: { $0.type == .cpuIdleGreaterThan }),
           let seconds = TimeInterval(idleCondition.value),
           seconds > 0 {
            name += " after \(formatDuration(seconds)) idle"
        }
        return name
    }

    var summarySentence: String {
        var parts = ["When \(targetDescription)"]
        let conditionDescriptions = conditions.map(\.summaryFragment)
        if !conditionDescriptions.isEmpty {
            parts[0] += " and \(naturalLanguageList(conditionDescriptions))"
        }

        parts.append(action.summaryPhrase)
        parts.append("at most once every \(formatDuration(TimeInterval(cooldownSeconds)))")

        if let contextDescription {
            parts.append(contextDescription)
        }

        return parts.joined(separator: ", ") + "."
    }

    private var contextDescription: String? {
        guard let contextAppBundleId,
              !contextAppBundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let contextAppMustBeRunning
        else {
            return nil
        }

        return contextAppMustBeRunning
            ? "only while \(contextAppBundleId) is running"
            : "only when \(contextAppBundleId) is not running"
    }
}

// MARK: - MatcherType Display

extension AutoRule.MatcherType {
    var displayName: String {
        switch self {
        case .name: "Process Name"
        case .path: "Executable Path"
        case .bundleId: "Bundle ID"
        case .launchdLabel: "Launchd Label"
        case .regex: "Regex Pattern"
        }
    }
}

private func naturalLanguageList(_ items: [String]) -> String {
    switch items.count {
    case 0:
        return ""
    case 1:
        return items[0]
    case 2:
        return "\(items[0]) and \(items[1])"
    default:
        let prefix = items.dropLast().joined(separator: ", ")
        return "\(prefix), and \(items[items.count - 1])"
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
