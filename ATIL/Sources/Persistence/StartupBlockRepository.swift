import Foundation
import GRDB

struct StartupBlockRepository: Sendable {
    let db: DatabaseManager

    func allRules() throws -> [StartupBlockRule] {
        try db.dbPool.read { db in
            struct StartupBlockRow: FetchableRecord, Decodable {
                let id: Int64
                let displayName: String
                let bundleIdentifier: String?
                let teamIdentifier: String?
                let bundlePath: String?
                let knownLabelsJSON: String
                let knownExecutablePathsJSON: String
                let createdAt: Date
            }

            return try StartupBlockRow.fetchAll(
                db,
                sql: """
                    SELECT id, displayName, bundleIdentifier, teamIdentifier, bundlePath,
                           knownLabelsJSON, knownExecutablePathsJSON, createdAt
                    FROM startupBlocks
                    ORDER BY displayName COLLATE NOCASE ASC
                """
            ).map {
                StartupBlockRule(
                    id: $0.id,
                    displayName: $0.displayName,
                    bundleIdentifier: $0.bundleIdentifier,
                    teamIdentifier: $0.teamIdentifier,
                    bundlePath: $0.bundlePath,
                    knownLabels: decodeJSONStringArray($0.knownLabelsJSON),
                    knownExecutablePaths: decodeJSONStringArray($0.knownExecutablePathsJSON),
                    createdAt: $0.createdAt
                )
            }
        }
    }

    func save(_ rule: StartupBlockRule) throws -> StartupBlockRule {
        try db.dbPool.write { db in
            let existingID = try existingRuleID(matching: rule, db: db)
            let labelsJSON = encodeJSONStringArray(rule.knownLabels)
            let pathsJSON = encodeJSONStringArray(rule.knownExecutablePaths)

            if let id = existingID ?? rule.id {
                try db.execute(
                    sql: """
                        UPDATE startupBlocks
                        SET displayName = ?, bundleIdentifier = ?, teamIdentifier = ?, bundlePath = ?,
                            knownLabelsJSON = ?, knownExecutablePathsJSON = ?
                        WHERE id = ?
                    """,
                    arguments: [
                        rule.displayName,
                        rule.bundleIdentifier,
                        rule.teamIdentifier,
                        rule.bundlePath,
                        labelsJSON,
                        pathsJSON,
                        id,
                    ]
                )
                var updated = rule
                updated.id = id
                return updated
            }

            try db.execute(
                sql: """
                    INSERT INTO startupBlocks (
                        displayName, bundleIdentifier, teamIdentifier, bundlePath,
                        knownLabelsJSON, knownExecutablePathsJSON, createdAt
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    rule.displayName,
                    rule.bundleIdentifier,
                    rule.teamIdentifier,
                    rule.bundlePath,
                    labelsJSON,
                    pathsJSON,
                    rule.createdAt,
                ]
            )

            var inserted = rule
            inserted.id = db.lastInsertedRowID
            return inserted
        }
    }

    func delete(ruleID: Int64) throws {
        try db.dbPool.write { db in
            try db.execute(
                sql: "DELETE FROM startupBlocks WHERE id = ?",
                arguments: [ruleID]
            )
        }
    }

    func matchingRule(for item: StartupItem) throws -> StartupBlockRule? {
        try allRules().first { $0.matches(item) }
    }

    private func existingRuleID(matching rule: StartupBlockRule, db: Database) throws -> Int64? {
        if let id = rule.id {
            return id
        }

        if let bundleIdentifier = rule.bundleIdentifier {
            return try Int64.fetchOne(
                db,
                sql: "SELECT id FROM startupBlocks WHERE bundleIdentifier = ? LIMIT 1",
                arguments: [bundleIdentifier]
            )
        }

        if let teamIdentifier = rule.teamIdentifier, let bundlePath = rule.bundlePath {
            return try Int64.fetchOne(
                db,
                sql: """
                    SELECT id FROM startupBlocks
                    WHERE teamIdentifier = ? AND bundlePath = ?
                    LIMIT 1
                """,
                arguments: [teamIdentifier, bundlePath]
            )
        }

        return nil
    }

    private func encodeJSONStringArray(_ values: [String]) -> String {
        let sorted = Array(Set(values)).sorted()
        let data = (try? JSONEncoder().encode(sorted)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private func decodeJSONStringArray(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return values
    }
}
