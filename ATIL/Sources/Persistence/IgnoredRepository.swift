import Foundation
import GRDB

/// A persistently ignored process identifier.
struct IgnoredRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "ignored"

    var id: Int64?
    let identifier: String
    let identifierType: String // "bundleId", "path"
    let displayName: String?
    let dateIgnored: Date

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Repository for ignored identifiers — persists across sessions.
struct IgnoredRepository: Sendable {
    let db: DatabaseManager

    func addIgnored(identifier: String, type: String, displayName: String?) throws {
        try db.dbPool.write { db in
            var record = IgnoredRecord(
                identifier: identifier,
                identifierType: type,
                displayName: displayName,
                dateIgnored: Date()
            )
            try record.insert(db)
        }
    }

    func removeIgnored(identifier: String) throws {
        try db.dbPool.write { db in
            try db.execute(
                sql: "DELETE FROM ignored WHERE identifier = ?",
                arguments: [identifier]
            )
        }
    }

    func allIgnored() throws -> [IgnoredRecord] {
        try db.dbPool.read { db in
            try IgnoredRecord.fetchAll(db)
        }
    }

    func isIgnored(identifier: String) throws -> Bool {
        try db.dbPool.read { db in
            try IgnoredRecord
                .filter(Column("identifier") == identifier)
                .fetchCount(db) > 0
        }
    }
}
