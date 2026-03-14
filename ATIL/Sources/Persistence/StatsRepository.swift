import Foundation
import GRDB

/// Repository for aggregate lifetime stats.
struct StatsRepository: Sendable {
    let db: DatabaseManager

    func incrementKills(by count: Int = 1) throws {
        try db.dbPool.write { db in
            try db.execute(
                sql: "UPDATE stats SET value = value + ? WHERE key = 'totalKills'",
                arguments: [count]
            )
        }
    }

    func incrementMemoryFreed(by bytes: Int64) throws {
        try db.dbPool.write { db in
            try db.execute(
                sql: "UPDATE stats SET value = value + ? WHERE key = 'totalMemoryFreed'",
                arguments: [bytes]
            )
        }
    }

    func totalKills() throws -> Int64 {
        try db.dbPool.read { db in
            try Int64.fetchOne(db, sql: "SELECT value FROM stats WHERE key = 'totalKills'") ?? 0
        }
    }

    func totalMemoryFreed() throws -> Int64 {
        try db.dbPool.read { db in
            try Int64.fetchOne(db, sql: "SELECT value FROM stats WHERE key = 'totalMemoryFreed'") ?? 0
        }
    }
}
