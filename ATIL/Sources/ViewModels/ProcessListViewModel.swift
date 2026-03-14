import SwiftUI

@Observable
@MainActor
final class ProcessListViewModel {
    let monitor: ProcessMonitor
    private let actionService = ProcessActionService()
    private let safetyGate = SafetyGate.shared

    // State
    var searchText = ""
    var selectedProcessID: ProcessIdentity?
    var expandedCategories: Set<ProcessCategory> = [.redundant, .suspicious]
    var showGrouped = true
    var lastError: String?

    // Session stats
    var sessionKillCount = 0
    var sessionMemoryFreed: UInt64 = 0

    init(monitor: ProcessMonitor? = nil) {
        self.monitor = monitor ?? ProcessMonitor()
    }

    // MARK: - Computed

    var filteredProcesses: [ATILProcess] {
        let all = monitor.snapshot
        guard !searchText.isEmpty else { return all }
        let query = searchText.lowercased()
        return all.filter { p in
            p.name.lowercased().contains(query)
            || "\(p.pid)".contains(query)
            || (p.executablePath?.lowercased().contains(query) ?? false)
            || (p.bundleIdentifier?.lowercased().contains(query) ?? false)
        }
    }

    var categorizedProcesses: [(category: ProcessCategory, processes: [ATILProcess])] {
        let grouped = Dictionary(grouping: filteredProcesses, by: \.category)
        return ProcessCategory.allCases.compactMap { cat in
            guard let procs = grouped[cat], !procs.isEmpty else { return nil }
            return (category: cat, processes: procs.sorted { $0.residentMemory > $1.residentMemory })
        }
    }

    var selectedProcess: ATILProcess? {
        guard let id = selectedProcessID else { return nil }
        return monitor.snapshot.first { $0.identity == id }
    }

    var totalRedundantMemory: UInt64 {
        monitor.snapshot
            .filter { $0.category == .redundant }
            .reduce(0) { $0 + $1.residentMemory }
    }

    /// Processes grouped by app bundle for display (v0.2).
    var groupedProcesses: [ProcessCategory: [ProcessGroup]] {
        let cats = Dictionary(grouping: filteredProcesses, by: \.category)
        var result: [ProcessCategory: [ProcessGroup]] = [:]
        for (cat, procs) in cats {
            result[cat] = ProcessGroup.group(procs)
        }
        return result
    }

    // MARK: - Actions

    func refresh() async {
        await monitor.scan()
    }

    func killSelected() async {
        guard let process = selectedProcess else { return }
        guard !safetyGate.isProtected(process) else {
            lastError = "Cannot kill protected process: \(process.name)"
            return
        }

        do {
            let freedMemory = try await actionService.kill(process: process)
            sessionKillCount += 1
            sessionMemoryFreed += freedMemory
            selectedProcessID = nil
            await monitor.scan()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func ignoreSelected() {
        guard let process = selectedProcess else { return }
        safetyGate.ignore(process)
        // Trigger reclassification by scanning
        Task { await monitor.scan() }
    }

    func startMonitoring() {
        monitor.startPolling()
        Task { await monitor.scan() }
    }

    func stopMonitoring() {
        monitor.stopPolling()
    }
}
