import Foundation

@Observable
@MainActor
final class ProcessInspectorViewModel {
    var selectedProcess: ATILProcess?
    var inspectionData = ProcessInspectionData()
    var loadingSections: Set<InspectionSection> = []
    var loadedSections: Set<InspectionSection> = []

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
        return formatDuration(Date().timeIntervalSince(process.startTime))
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

    var formattedCPUPercent: String {
        guard let process = selectedProcess else { return "—" }
        return String(format: "%.1f%%", process.cpuPercent)
    }

    var bundleVersion: String {
        guard let bundlePath = selectedProcess?.bundlePath,
              let bundle = Bundle(path: bundlePath)
        else { return "—" }

        return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "—"
    }

    func isLoading(_ section: InspectionSection) -> Bool {
        loadingSections.contains(section)
    }

    func hasLoaded(_ section: InspectionSection) -> Bool {
        loadedSections.contains(section)
    }

    func load(section: InspectionSection, launchdMap: [String: LaunchdJobInfo]) async {
        guard let process = selectedProcess, !loadingSections.contains(section) else { return }

        loadingSections.insert(section)
        defer { loadingSections.remove(section) }

        let inspector = self.inspector
        let result = await Task.detached {
            inspector.load(section: section, process: process, launchdMap: launchdMap)
        }.value

        guard selectedProcess?.identity == process.identity else { return }
        inspectionData.merge(result)
        loadedSections.insert(section)
    }

    func clearInspection() {
        inspectionData = ProcessInspectionData()
        loadingSections.removeAll()
        loadedSections.removeAll()
    }
}
