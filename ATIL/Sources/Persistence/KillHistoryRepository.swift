import Foundation
import GRDB

/// A record of a kill or suspend action.
struct KillHistoryRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "killHistory"

    enum RelaunchKind: String, Codable, Sendable {
        case appBundle
        case launchdJob
    }

    var id: Int64?
    let timestamp: Date
    let pid: Int32
    let processStartTime: Date?
    let processName: String
    let executablePath: String?
    let bundleIdentifier: String?
    let action: String // "kill" or "suspend"
    let result: String // "success" or "failed"
    let memoryFreed: Int64
    let relaunchToken: String? // bundlePath or launchd label for relaunch
    let relaunchKind: RelaunchKind?
    let launchdLabel: String?
    let launchdDomain: String?

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var isSuccessfulKill: Bool {
        action == "kill" && result == "success"
    }
}

/// Repository for kill history operations.
struct KillHistoryRepository: Sendable {
    let db: DatabaseManager

    func record(_ entry: KillHistoryRecord) throws {
        try db.dbPool.write { db in
            let record = entry
            try record.insert(db)
        }
    }

    func recentHistory(limit: Int = 50) throws -> [KillHistoryRecord] {
        try db.dbPool.read { db in
            try KillHistoryRecord
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func sessionHistory(since: Date) throws -> [KillHistoryRecord] {
        try db.dbPool.read { db in
            try KillHistoryRecord
                .filter(Column("timestamp") >= since)
                .order(Column("timestamp").desc)
                .fetchAll(db)
        }
    }

    /// Find a recent kill record for relaunch purposes.
    func findRelaunchable(processName: String) throws -> KillHistoryRecord? {
        try db.dbPool.read { db in
            try KillHistoryRecord
                .filter(Column("processName") == processName)
                .filter(Column("relaunchToken") != nil)
                .filter(Column("action") == "kill")
                .filter(Column("result") == "success")
                .order(Column("timestamp").desc)
                .fetchOne(db)
        }
    }
}
