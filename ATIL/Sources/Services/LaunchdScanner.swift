import Foundation

/// Information about a launchd job associated with a process.
struct LaunchdJobInfo: Sendable {
    let label: String
    let plistPath: String
    let domain: String
    let programPath: String?
    let programArguments: [String]?
    let keepAlive: Bool
    let runAtLoad: Bool

    /// Whether killing this process will cause launchd to respawn it.
    var willRespawn: Bool {
        keepAlive || runAtLoad
    }

    var scope: StartupItemScope {
        domain == "system" ? .system : .user
    }
}

/// Scans launchd plist directories and builds a lookup from executable path → job info.
struct LaunchdScanner: Sendable {

    /// Standard launchd plist directories.
    static let searchDirectories: [String] = {
        var dirs = [
            "/Library/LaunchDaemons",
            "/Library/LaunchAgents",
        ]
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            dirs.append("\(home)/Library/LaunchAgents")
        }
        return dirs
    }()

    /// Scans all launchd directories and returns a map from executable path to job info.
    func scanAll() -> [String: LaunchdJobInfo] {
        var map: [String: LaunchdJobInfo] = [:]
        for info in scanJobs() {
            if let program = info.programPath {
                map[program] = info
            }
            if let args = info.programArguments, let first = args.first {
                map[first] = info
            }
        }
        return map
    }

    func scanJobs() -> [LaunchdJobInfo] {
        Self.searchDirectories.flatMap(scanDirectory)
    }

    /// Scans a single directory for .plist files and parses them.
    private func scanDirectory(_ path: String) -> [LaunchdJobInfo] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: path) else { return [] }

        return entries.compactMap { entry -> LaunchdJobInfo? in
            guard entry.hasSuffix(".plist") else { return nil }
            let fullPath = (path as NSString).appendingPathComponent(entry)
            return parsePlist(at: fullPath)
        }
    }

    /// Parses a single launchd plist into LaunchdJobInfo.
    private func parsePlist(at path: String) -> LaunchdJobInfo? {
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = plist["Label"] as? String
        else { return nil }

        let program = plist["Program"] as? String
        let programArguments = plist["ProgramArguments"] as? [String]

        // KeepAlive can be a Bool or a dictionary of conditions
        let keepAlive: Bool = {
            if let flag = plist["KeepAlive"] as? Bool { return flag }
            if plist["KeepAlive"] is [String: Any] { return true }
            return false
        }()

        let runAtLoad = plist["RunAtLoad"] as? Bool ?? false
        let domain: String
        if path.contains("/LaunchDaemons/") {
            domain = "system"
        } else {
            domain = "gui/\(getuid())"
        }

        return LaunchdJobInfo(
            label: label,
            plistPath: path,
            domain: domain,
            programPath: program ?? programArguments?.first,
            programArguments: programArguments,
            keepAlive: keepAlive,
            runAtLoad: runAtLoad
        )
    }
}
