import Foundation
import GRDB

/// Manages the SQLite database for ATIL's persistent data.
final class DatabaseManager: Sendable {
    static let shared = DatabaseManager()

    let dbPool: DatabasePool

    private init() {
        do {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first!.appendingPathComponent("ATIL", isDirectory: true)

            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

            let dbPath = appSupport.appendingPathComponent("atil.db").path
            var config = Configuration()
            config.prepareDatabase { db in
                db.trace { print("SQL: \($0)") }
            }
            #if DEBUG
            // Verbose logging in debug only
            #else
            config = Configuration()
            #endif

            dbPool = try DatabasePool(path: dbPath, configuration: config)
            try migrator.migrate(dbPool)
        } catch {
            fatalError("Database initialization failed: \(error)")
        }
    }

    /// For testing with in-memory database
    init(inMemory: Bool) throws {
        if inMemory {
            dbPool = try DatabasePool(path: ":memory:")
        } else {
            fatalError("Use DatabaseManager.shared for on-disk database")
        }
        try migrator.migrate(dbPool)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            // Kill history
            try db.create(table: "killHistory") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .datetime).notNull()
                t.column("pid", .integer).notNull()
                t.column("processStartTime", .datetime)
                t.column("processName", .text).notNull()
                t.column("executablePath", .text)
                t.column("bundleIdentifier", .text)
                t.column("action", .text).notNull() // "kill", "suspend"
                t.column("result", .text).notNull() // "success", "failed"
                t.column("memoryFreed", .integer).notNull().defaults(to: 0)
                t.column("relaunchToken", .text) // bundlePath or launchd label
            }

            // Ignored identifiers
            try db.create(table: "ignored") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("identifier", .text).notNull().unique()
                t.column("identifierType", .text).notNull() // "bundleId", "path", "signingIdentity"
                t.column("displayName", .text)
                t.column("dateIgnored", .datetime).notNull()
            }

            // Aggregate stats
            try db.create(table: "stats") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .integer).notNull().defaults(to: 0)
            }

            // Initialize stats
            try db.execute(sql: """
                INSERT INTO stats (key, value) VALUES ('totalKills', 0);
                INSERT INTO stats (key, value) VALUES ('totalMemoryFreed', 0);
            """)
        }

        migrator.registerMigration("v2_rules") { db in
            // Auto-action rules
            try db.create(table: "rules") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("matcherType", .text).notNull() // "name", "path", "bundleId", "regex"
                t.column("matcherValue", .text).notNull()
                t.column("conditionJSON", .text).notNull() // JSON array of conditions
                t.column("contextAppBundleId", .text) // optional: another app must/must not be running
                t.column("contextAppMustBeRunning", .boolean) // true = must be running, false = must not
                t.column("action", .text).notNull() // "kill", "suspend", "markRedundant"
                t.column("cooldownSeconds", .integer).notNull().defaults(to: 600) // 10 min default
                t.column("enabled", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .datetime).notNull()
            }

            // Rule event log (tracks last action per rule/process)
            try db.create(table: "ruleEvents") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("ruleId", .integer).notNull()
                    .references("rules", onDelete: .cascade)
                t.column("processIdentity", .text).notNull() // "pid:startTime"
                t.column("actionTaken", .text).notNull()
                t.column("timestamp", .datetime).notNull()
            }
        }

        return migrator
    }
}
