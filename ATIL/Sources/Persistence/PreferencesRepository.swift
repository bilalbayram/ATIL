import Foundation
import GRDB

struct PreferencesRepository: Sendable {
    let db: DatabaseManager

    func string(forKey key: String) throws -> String? {
        try db.dbPool.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM preferences WHERE key = ?", arguments: [key])
        }
    }

    func bool(forKey key: String, defaultValue: Bool) throws -> Bool {
        guard let value = try string(forKey: key) else { return defaultValue }
        return NSString(string: value).boolValue
    }

    func int(forKey key: String, defaultValue: Int) throws -> Int {
        guard let value = try string(forKey: key), let intValue = Int(value) else { return defaultValue }
        return intValue
    }

    func set(_ value: String, forKey key: String) throws {
        try db.dbPool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO preferences (key, value) VALUES (?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """,
                arguments: [key, value]
            )
        }
    }
}
