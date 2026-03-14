import Foundation

/// An entry in the curated blocklist of known low-value processes.
struct BlocklistEntry: Codable, Sendable {
    let identifier: String
    let type: String // "bundleId", "name", "namePrefix"
    let name: String
    let reason: String
}

/// Manages the app-bundled blocklist of known redundant processes.
struct BlocklistService: Sendable {
    static let shared = BlocklistService()

    let entries: [BlocklistEntry]
    private let bundleIdSet: Set<String>
    private let nameSet: Set<String>
    private let namePrefixes: [String]

    init() {
        guard let url = Bundle.main.url(forResource: "blocklist", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode(BlocklistRoot.self, from: data)
        else {
            entries = []
            bundleIdSet = []
            nameSet = []
            namePrefixes = []
            return
        }

        entries = root.entries

        var bundleIds: Set<String> = []
        var names: Set<String> = []
        var prefixes: [String] = []

        for entry in entries {
            switch entry.type {
            case "bundleId":
                bundleIds.insert(entry.identifier.lowercased())
            case "name":
                names.insert(entry.identifier.lowercased())
            case "namePrefix":
                prefixes.append(entry.identifier.lowercased())
            default:
                break
            }
        }

        bundleIdSet = bundleIds
        nameSet = names
        namePrefixes = prefixes
    }

    /// Check if a process matches the blocklist.
    func isBlocklisted(_ process: ATILProcess) -> Bool {
        if let bundleId = process.bundleIdentifier?.lowercased() {
            if bundleIdSet.contains(bundleId) { return true }
        }

        let name = process.name.lowercased()
        if nameSet.contains(name) { return true }
        if namePrefixes.contains(where: { name.hasPrefix($0) }) { return true }

        return false
    }

    /// Get the reason for a blocklisted process.
    func reason(for process: ATILProcess) -> String? {
        if let bundleId = process.bundleIdentifier?.lowercased() {
            if let entry = entries.first(where: { $0.type == "bundleId" && $0.identifier.lowercased() == bundleId }) {
                return entry.reason
            }
        }

        let name = process.name.lowercased()
        if let entry = entries.first(where: { $0.type == "name" && $0.identifier.lowercased() == name }) {
            return entry.reason
        }
        if let entry = entries.first(where: { $0.type == "namePrefix" && name.hasPrefix($0.identifier.lowercased()) }) {
            return entry.reason
        }

        return nil
    }
}

private struct BlocklistRoot: Codable {
    let version: Int
    let description: String
    let entries: [BlocklistEntry]
}
