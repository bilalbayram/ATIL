// ProcessGroup — app-level grouping model
// Stub for v0.1, fully implemented in v0.2

struct ProcessGroup: Identifiable, Sendable {
    let id: String // bundleIdentifier or executable path
    let displayName: String
    var processes: [ATILProcess]

    var totalMemory: UInt64 {
        processes.reduce(0) { $0 + $1.residentMemory }
    }

    var processCount: Int {
        processes.count
    }
}
