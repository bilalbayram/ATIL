import AppKit

/// Groups related processes by application bundle for presentation.
/// Chrome helper processes appear under "Google Chrome", Electron sub-processes
/// under their parent app, etc. Processes without a bundle appear individually.
struct ProcessGroup: Identifiable, Sendable {
    let id: String // bundleIdentifier or executable path
    let displayName: String
    let appIcon: NSImage?
    var processes: [ATILProcess]

    var totalMemory: UInt64 {
        processes.reduce(0) { $0 + $1.residentMemory }
    }

    var processCount: Int {
        processes.count
    }

    var category: ProcessCategory {
        // Group takes the worst category of its members
        processes.map(\.category).min() ?? .healthy
    }

    var isGrouped: Bool {
        processes.count > 1
    }

    /// Build groups from a flat process list.
    static func group(_ processes: [ATILProcess]) -> [ProcessGroup] {
        var groups: [String: [ATILProcess]] = [:]

        for process in processes {
            let key: String
            if let bundleID = process.bundleIdentifier {
                key = bundleID
            } else if let path = process.executablePath {
                // Group by executable name for unbundled processes
                key = (path as NSString).lastPathComponent
            } else {
                key = "pid-\(process.pid)"
            }
            groups[key, default: []].append(process)
        }

        return groups.map { key, procs in
            let displayName: String
            let icon: NSImage?

            if let first = procs.first {
                displayName = first.bundlePath.flatMap { path in
                    Bundle(path: path)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? Bundle(path: path)?.object(forInfoDictionaryKey: "CFBundleName") as? String
                } ?? first.name
                icon = first.appIcon
            } else {
                displayName = key
                icon = nil
            }

            return ProcessGroup(
                id: key,
                displayName: displayName,
                appIcon: icon,
                processes: procs.sorted { $0.residentMemory > $1.residentMemory }
            )
        }
        .sorted { $0.totalMemory > $1.totalMemory }
    }
}
