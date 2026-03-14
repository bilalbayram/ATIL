import Foundation

@Observable
@MainActor
final class ProcessInspectorViewModel {
    var selectedProcess: ATILProcess?
    var inspectionData: ProcessInspectionData?
    var isLoadingInspection = false

    private let inspector = ProcessInspector()

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

    /// Load expensive inspection data on demand.
    func loadInspection(launchdMap: [String: LaunchdJobInfo]) async {
        guard let process = selectedProcess else { return }
        isLoadingInspection = true
        defer { isLoadingInspection = false }

        let inspector = self.inspector
        let result = await Task.detached {
            inspector.inspect(process: process, launchdMap: launchdMap)
        }.value

        // Only apply if still viewing the same process
        if selectedProcess?.identity == process.identity {
            inspectionData = result
        }
    }

    func clearInspection() {
        inspectionData = nil
    }
}
