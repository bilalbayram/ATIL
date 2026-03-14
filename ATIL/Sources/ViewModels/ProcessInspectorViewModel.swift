import Foundation

@Observable
@MainActor
final class ProcessInspectorViewModel {
    var selectedProcess: ATILProcess?

    var formattedStartTime: String {
        guard let process = selectedProcess else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: process.startTime)
    }

    var formattedUptime: String {
        guard let process = selectedProcess else { return "—" }
        let interval = Date().timeIntervalSince(process.startTime)
        return formatDuration(interval)
    }

    var formattedCPUTime: String {
        guard let process = selectedProcess else { return "—" }
        return formatDuration(process.cpuTimeTotal)
    }

    var formattedResidentMemory: String {
        guard let process = selectedProcess else { return "—" }
        return formatBytes(process.residentMemory)
    }

    var formattedVirtualMemory: String {
        guard let process = selectedProcess else { return "—" }
        return formatBytes(process.virtualMemory)
    }
}
