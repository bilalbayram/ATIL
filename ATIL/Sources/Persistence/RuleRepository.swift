import Foundation
import GRDB

struct RuleRepository: Sendable {
    let db: DatabaseManager

    // MARK: - Rules CRUD

    func allRules() throws -> [AutoRule] {
        try db.dbPool.read { db in
            try AutoRule.fetchAll(db)
        }
    }

    func enabledRules() throws -> [AutoRule] {
        try db.dbPool.read { db in
            try AutoRule.filter(Column("enabled") == true).fetchAll(db)
        }
    }

    func save(_ rule: AutoRule) throws -> AutoRule {
        try db.dbPool.write { db in
            var r = rule
            try r.save(db)
            return r
        }
    }

    func delete(_ rule: AutoRule) throws {
        try db.dbPool.write { db in
            _ = try rule.delete(db)
        }
    }

    func toggleEnabled(_ rule: AutoRule) throws -> AutoRule {
        try db.dbPool.write { db in
            var r = rule
            r.enabled = !r.enabled
            try r.update(db)
            return r
        }
    }

    // MARK: - Rule Events

    func recordEvent(ruleId: Int64, processIdentity: String, action: String) throws {
        try db.dbPool.write { db in
            var event = RuleEvent(
                ruleId: ruleId,
                processIdentity: processIdentity,
                actionTaken: action,
                timestamp: Date()
            )
            try event.insert(db)
        }
    }

    func lastEvent(ruleId: Int64, processIdentity: String) throws -> RuleEvent? {
        try db.dbPool.read { db in
            try RuleEvent
                .filter(Column("ruleId") == ruleId)
                .filter(Column("processIdentity") == processIdentity)
                .order(Column("timestamp").desc)
                .fetchOne(db)
        }
    }

    /// Check if a rule action is within cooldown for a specific process.
    func isInCooldown(ruleId: Int64, processIdentity: String, cooldownSeconds: Int) throws -> Bool {
        guard let lastEvent = try lastEvent(ruleId: ruleId, processIdentity: processIdentity) else {
            return false
        }
        let cooldownEnd = lastEvent.timestamp.addingTimeInterval(TimeInterval(cooldownSeconds))
        return Date() < cooldownEnd
    }
}
